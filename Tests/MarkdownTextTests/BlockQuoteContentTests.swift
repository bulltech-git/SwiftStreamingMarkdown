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
