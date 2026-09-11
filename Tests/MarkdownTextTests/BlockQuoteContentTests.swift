//
//  Copyright (c) Microsoft Corporation. All rights reserved.
//  Licensed under the MIT License. See LICENSE in the project root for license information.
//

import Foundation
@testable import SwiftStreamingMarkdown
import XCTest

/// Regression coverage for a block quote's inline content surviving intact.
///
/// THE BUG: block quotes used to build their text via `extractPlainText`,
/// which walks the parsed markdown tree and returns only the visible
/// characters — a `[text](url)` link became just `text`, its destination
/// discarded before the view layer ever saw it, so a link inside a quote
/// could never be tapped. Bold/italic collapsed the same way. Paragraphs
/// never had this problem because they build a real `NSMutableAttributedString`
/// (`buildParagraphContent`) that carries link/font/color as attributes on
/// the run of text — block quotes now use that exact same builder.
final class BlockQuoteContentTests: XCTestCase {

  private let parser = MarkdownParserImpl()

  private func blockQuoteContent(_ renderables: [MarkdownRenderable]) -> NSMutableAttributedString? {
    // quoteTypes always wraps its children in .nested(...), even a single one.
    guard case .blockQuote(_, let item) = renderables.first,
          case .nested(let children) = item.quoteType,
          case .text(let content) = children.first else {
      return nil
    }
    return content
  }

  func test_linkInsideQuote_keepsItsDestination() async {
    let document = await parser.parse(text: "> check the [docs](https://example.com) here")
    let renderables = document.convert(with: .default)

    guard let content = blockQuoteContent(renderables) else {
      return XCTFail("Expected a block quote with text content")
    }

    let linkLocation = content.string.range(of: "docs")?.lowerBound.utf16Offset(in: content.string)
    let url = linkLocation.flatMap { content.attribute(.link, at: $0, effectiveRange: nil) as? URL }
    XCTAssertEqual(url, URL(string: "https://example.com"),
                   "the link's destination must survive into the quote's attributed content, not just its visible text")
  }

  func test_boldInsideQuote_keepsItsFont() async {
    let document = await parser.parse(text: "> normal **bold** normal")
    let renderables = document.convert(with: .default)

    guard let content = blockQuoteContent(renderables) else {
      return XCTFail("Expected a block quote with text content")
    }

    let boldLocation = content.string.range(of: "bold")?.lowerBound.utf16Offset(in: content.string)
    let normalLocation = content.string.range(of: "normal")?.lowerBound.utf16Offset(in: content.string)
    let boldFont = boldLocation.flatMap { content.attribute(.font, at: $0, effectiveRange: nil) as? MDFont }
    let normalFont = normalLocation.flatMap { content.attribute(.font, at: $0, effectiveRange: nil) as? MDFont }

    XCTAssertNotNil(boldFont)
    XCTAssertNotEqual(boldFont, normalFont, "bold text inside a quote must render in a different font, not flatten to plain text")
  }

  func test_quoteContent_stillHasAQuoteColor() async {
    let document = await parser.parse(text: "> plain quoted text")
    let renderables = document.convert(with: .default)

    guard let content = blockQuoteContent(renderables) else {
      return XCTFail("Expected a block quote with text content")
    }

    let color = content.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? MDColor
    XCTAssertEqual(color, MDColor(MarkdownRenderConfig.default.blockQuoteStyle.textColor),
                   "the quote's own text color (config.blockQuoteStyle.textColor) must still apply, same as before")
  }
}

/// Regression coverage for a block quote keeping *every* child, not just its
/// inline ones.
///
/// THE BUG: `quoteTypes` walked a quote's children and handled exactly two
/// shapes — an `InlineContainer` (paragraph/heading) and a nested `BlockQuote`.
/// Every other child fell off the end of the `if` chain and was gone. A quote
/// whose body was a list is the common case in a real answer:
///
///     >DEFINITIONS
///     >- **Sinoatrial (SA) Node**: the heart's natural pacemaker.
///
/// rendered as the single word "DEFINITIONS". Upstream can afford to drop a
/// block mid-stream because the next chunk redraws the document; this fork
/// renders finished answers, where a dropped block is just missing content.
final class BlockQuoteCompletenessTests: XCTestCase {

  private let parser = MarkdownParserImpl()

  private func quoteChildren(_ renderables: [MarkdownRenderable]) -> [BlockQuoteType] {
    guard case .blockQuote(_, let item) = renderables.first,
          case .nested(let children) = item.quoteType else {
      return []
    }
    return children
  }

  func test_listInsideQuote_isKept() async {
    let markdown = """
    >DEFINITIONS
    >- **Sinoatrial (SA) Node**: the heart's natural pacemaker.
    >- **Arrhythmia**: any disruption of the heartbeat.
    """
    let document = await parser.parse(text: markdown)
    let children = quoteChildren(document.convert(with: .default))

    XCTAssertEqual(children.count, 2, "the quote must keep both its paragraph and its list, not only the paragraph")

    guard children.count == 2, case .block(let renderable) = children[1],
          case .unorderedList(_, let items, _) = renderable else {
      return XCTFail("Expected the quote's second child to be an unordered list, got \(children.dropFirst().first as Any)")
    }
    XCTAssertEqual(items.count, 2)
  }

  func test_listInsideQuote_keepsItemTextAndBold() async {
    let document = await parser.parse(text: ">DEFINITIONS\n>- **Arrhythmia**: any disruption of the heartbeat.")
    let children = quoteChildren(document.convert(with: .default))

    guard case .block(let renderable) = children.last,
          case .unorderedList(_, let items, _) = renderable,
          case .paragraph(_, let content) = items.first?.children.first else {
      return XCTFail("Expected a list item paragraph inside the quote")
    }

    XCTAssertTrue(content.string.contains("Arrhythmia"))
    XCTAssertTrue(content.string.contains("any disruption of the heartbeat."))
    XCTAssertTrue(items.first?.startsWithBold == true, "the item's leading bold term must survive into the quote")
  }

  func test_orderedListCodeBlockAndRuleInsideQuote_areKept() async {
    let markdown = """
    > intro
    >
    > 1. first
    > 2. second
    >
    > ```swift
    > let x = 1
    > ```
    >
    > ---
    """
    let document = await parser.parse(text: markdown)
    let children = quoteChildren(document.convert(with: .default))

    let kinds = children.compactMap { child -> String? in
      switch child {
      case .text: return "text"
      case .nested: return "nested"
      case .block(let renderable):
        switch renderable {
        case .orderedList: return "orderedList"
        case .codeBlock: return "codeBlock"
        case .thematicBreak: return "thematicBreak"
        default: return "other"
        }
      }
    }
    XCTAssertEqual(kinds, ["text", "orderedList", "codeBlock", "thematicBreak"],
                   "no block kind may be dropped just because it is inside a quote")
  }

  func test_quotedListContributesToPlainText() async {
    let document = await parser.parse(text: ">DEFINITIONS\n>- **Arrhythmia**: any disruption of the heartbeat.")
    let renderable = RenderableDocument(renderables: document.convert(with: .default))

    XCTAssertTrue(renderable.plainText.contains("Arrhythmia"),
                  "text selection and copy must see the quoted list too")
  }

  func test_rawHTMLBlock_fallsBackToItsTextInsteadOfVanishing() async {
    let document = await parser.parse(text: "<div class=\"note\">Heads up &amp; take care</div>")
    let renderables = document.convert(with: .default)

    guard case .paragraph(_, let content) = renderables.first else {
      return XCTFail("Expected the HTML block to survive as a paragraph, got \(renderables)")
    }
    XCTAssertEqual(content.string, "Heads up & take care")
  }
}
