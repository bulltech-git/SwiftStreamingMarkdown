//
//  Copyright (c) Microsoft Corporation. All rights reserved.
//  Licensed under the MIT License. See LICENSE in the project root for license information.
//

import Foundation
import Markdown
import SwiftUI
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// A `MarkdownRenderConfig`-aware snapshot of a parsed markdown `Document`,
/// ready to be handed to a `MarkdownView` for rendering. Producing one is
/// the heavyweight step; rendering it is cheap.
public struct RenderableDocument: Equatable, Sendable {
  let renderables: [MarkdownRenderable]

  var containsCodeBlock: Bool {
    return renderables.contains(where: { $0.isCodeBlock })
  }

  var containsBlockQuote: Bool {
    return renderables.contains(where: { $0.isBlockQuote })
  }

  var isEmpty: Bool {
    return renderables.isEmpty
  }

  /// Convert a parsed `Document` into a `RenderableDocument` using the supplied config.
  /// - Parameters:
  ///   - document: The parsed markdown tree.
  ///   - config: Styling and behavior used during conversion.
  public init(document: Markdown.Document, config: MarkdownRenderConfig) async {
    self.renderables = document.convert(with: config)
  }

  /// Construct a renderable wrapping a single plain-text paragraph styled
  /// with `config.paragraphStyle`. Useful for showing non-markdown text in a
  /// `MarkdownView` without round-tripping through the parser.
  public init(plainText: String, config: MarkdownRenderConfig) {
    var attributes: [NSAttributedString.Key: Any] = [
      .font: config.paragraphStyle.textFonts.normal,
      .foregroundColor: MDColor(config.paragraphStyle.textColor)
    ]
    if let kern = config.paragraphStyle.textFonts.preferredLetterSpacing {
      attributes[.kern] = kern
    }
    let content = NSMutableAttributedString(string: plainText, attributes: attributes)
    self.init(renderables: [.paragraph(id: UUID().uuidString, content: content)])
  }

  init(renderables: [MarkdownRenderable]) {
    self.renderables = renderables
  }

  /// An empty document, equivalent to `RenderableDocument(plainText: "", …)`
  /// but allocation-free.
  public static let empty = RenderableDocument(renderables: [])

  /// The renderable for `text` under `config`: parsed on the caller's thread
  /// the first time, served from memory after that.
  ///
  /// Synchronous on purpose. A view that parsed in a `.task` drew an empty
  /// document first and grew a frame later — inside a lazy stack, every row
  /// built while scrolling changed height under the reader. Parsing is a few
  /// milliseconds once per text; the jump was on every appearance.
  static func cached(text: String, config: MarkdownRenderConfig) -> RenderableDocument {
    let key = CacheKey(text: text, config: config)
    if let hit = cache.object(forKey: key) { return hit.document }

    let document = MarkdownParserImpl().parseNow(
      text: text,
      option: .init(speculativeRewrite: false, imageSupport: config.imageConfig.enabled)
    ).document
    let renderable = RenderableDocument(renderables: document.convert(with: config))
    cache.setObject(CachedDocument(renderable), forKey: key, cost: text.utf16.count)
    return renderable
  }

  /// Bounded by characters parsed, so one huge answer cannot evict a whole
  /// conversation of short ones. NSCache is documented thread-safe.
  private static let cache: NSCache<CacheKey, CachedDocument> = {
    let cache = NSCache<CacheKey, CachedDocument>()
    cache.totalCostLimit = 4_000_000
    return cache
  }()

  /// Text and the (already Dynamic Type-scaled) config: either one changes
  /// the attributed strings a parse bakes in.
  private final class CacheKey: NSObject {
    let text: String
    let config: MarkdownRenderConfig

    init(text: String, config: MarkdownRenderConfig) {
      self.text = text
      self.config = config
    }

    override var hash: Int {
      var hasher = Hasher()
      hasher.combine(text)
      hasher.combine(config)
      return hasher.finalize()
    }

    override func isEqual(_ object: Any?) -> Bool {
      guard let other = object as? CacheKey else { return false }
      return text == other.text && config == other.config
    }
  }

  private final class CachedDocument {
    let document: RenderableDocument
    init(_ document: RenderableDocument) { self.document = document }
  }
}

extension RenderableDocument {
  var attributedStrings: [NSAttributedString] {
    return renderables.flatMap { $0.extractAttributedStrings() }
  }

  /// The full document rendered as plain text, across every block kind
  /// (headings, paragraphs, lists, code blocks, tables, block quotes). Used to
  /// populate the "Select more text" modal.
  var plainText: String {
    renderables
      .compactMap { $0.plainText }
      .joined(separator: "\n\n")
  }
}

extension MarkdownRenderable {
  /// A plain-text representation of this block, or `nil` for blocks that carry
  /// no selectable text (e.g. thematic breaks).
  var plainText: String? {
    switch self {
    case .paragraph(_, let content), .heading(_, _, let content):
      return content.string
    case .latex(_, let content):
      return content
    case .orderedList(_, let items):
      return items.plainText(separator: "\n")
    case .unorderedList(_, let items, _):
      return items.plainText(separator: "\n")
    case .codeBlock(_, _, let code):
      return code
    case .table(_, let headers, let rows, _):
      let headerLine = headers.map { $0.string }.joined(separator: "\t")
      let rowLines = rows.map { row in row.map { $0.string }.joined(separator: "\t") }
      return ([headerLine] + rowLines).joined(separator: "\n")
    case .blockQuote(_, let item):
      return item.quoteType.plainText
    case .thematicBreak:
      return nil
    case .image(_, let data):
      return data.alt.isEmpty ? nil : data.alt
    }
  }
}

private extension Array where Element == MarkdownListItem {
  func plainText(separator: String) -> String? {
    let lines = flatMap { item in
      item.children.compactMap { $0.plainText }
    }
    return lines.isEmpty ? nil : lines.joined(separator: separator)
  }
}

private extension BlockQuoteType {
  var plainText: String {
    switch self {
    case .text(let content):
      return content.string
    case .nested(let items):
      return items.map { $0.plainText }.joined(separator: "\n")
    case .block(let renderable):
      return renderable.plainText ?? ""
    }
  }
}

extension MarkdownRenderable {
  func extractAttributedStrings() -> [NSAttributedString] {
    switch self {
    case .paragraph(_, let str):
      return [str]
    case .orderedList(_, let items):
      return items.flatMap { $0.attributedStrings() }
    case .unorderedList(_, let items, _):
      return items.flatMap { $0.attributedStrings() }
    case .table(_, let headers, let rows, _):
      return headers + rows.flatMap { $0 }
    default:
      return []
    }
  }
}

extension MarkdownListItem {
  func attributedStrings() -> [NSAttributedString] {
    return self.children.flatMap { $0.extractAttributedStrings() }
  }
}
