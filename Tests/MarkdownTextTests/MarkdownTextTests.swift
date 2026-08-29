//
//  Copyright (c) Microsoft Corporation. All rights reserved.
//  Licensed under the MIT License. See LICENSE in the project root for license information.
//

#if canImport(UIKit)
import Markdown
@testable import SwiftStreamingMarkdown
import SwiftUI
import UIKit
import XCTest

@MainActor
final class MarkdownTextTests: XCTestCase {

  let parser: MarkdownParser = MarkdownParserImpl()

  /// Tests regular citation format (old format) by directly testing the convert method
  func testRegularCitationFormat() async throws {
    let markdown = """
    [Microsoft](http://example.com?citationMarker=9F742443)
    """

    let document = await parser.parse(text: markdown)

    // Find the link in the parsed document
    var link: Markdown.Link?
    for child in document.children {
      if let paragraph = child as? Markdown.Paragraph {
        for paragraphChild in paragraph.children {
          if let foundLink = paragraphChild as? Markdown.Link {
            link = foundLink
            break
          }
        }
      }
      if link != nil { break }
    }

    guard let link = link else {
      XCTFail("Expected to find a link in the parsed markdown")
      return
    }

    // Verify this is NOT an attachment citation (it's a regular citation)
    XCTAssertFalse(link.isInlineCitation(coder: .default), "Link should NOT be detected as attachment citation")

    // Test the convert method directly
    let attributeContainer: [NSAttributedString.Key: Any] = [:]
    let convertedString = link.convert(
      attributeContainer: attributeContainer,
      config: .default
    )

    // Regular citations should show the link text "Microsoft", not the internal marker
    XCTAssertTrue(
      convertedString.string.contains("Microsoft"),
      "DIRECT convert() call should return the link text for regular citations. Got: '\(convertedString.string)'"
    )
    XCTAssertFalse(
      convertedString.string.contains("9F742443"),
      "Regular citations should not show the internal marker UUID"
    )
  }

  /// Tests attachment citation format by directly testing the convert method
  func testAttachmentCitationFormat() async throws {
    let markdown = """
    [9F742443](http://example.com?citationMarker=9F742443&citationTitle=Microsoft&citationA11yValue=Microsoft)
    """

    let document = await parser.parse(text: markdown)

    // Find the link in the parsed document - need to traverse children properly
    var link: Markdown.Link?
    for child in document.children {
      if let paragraph = child as? Markdown.Paragraph {
        for paragraphChild in paragraph.children {
          if let foundLink = paragraphChild as? Markdown.Link {
            link = foundLink
            break
          }
        }
      }
      if link != nil { break }
    }

    guard let link = link else {
      XCTFail("Expected to find a link in the parsed markdown")
      return
    }

    // Verify this is an attachment citation
    XCTAssertTrue(link.isInlineCitation(coder: .default), "Link should be detected as attachment citation")

    // Test the convert method directly - this should expose the bug
    let attributeContainer: [NSAttributedString.Key: Any] = [:]
    let convertedString = link.convert(
      attributeContainer: attributeContainer,
      config: .default
    )

    // Verify that we get an attachment, not plain text
    XCTAssertEqual(convertedString.length, 1, "Should have exactly one attachment character")

    // Get the attachment and verify it contains the correct data
    var attachmentFound = false
    convertedString.enumerateAttribute(.attachment, in: NSRange(location: 0, length: convertedString.length), options: []) { (attachment, _, _) in
      if let citationAttachment = attachment as? InlineCitationAttachment,
         let citationData = citationAttachment.citationData {
        XCTAssertEqual(citationData.title, "Microsoft", "Citation attachment should contain title 'Microsoft'")
        XCTAssertEqual(citationData.accessibilityLabel, "Microsoft", "Citation attachment should have accessibility label 'Microsoft'")
        attachmentFound = true
      }
    }

    XCTAssertTrue(attachmentFound, "Should find a citation attachment with proper data")
  }

  /// Tests fallback behavior when attachment citation data is malformed
  func testAttachmentCitationFallbackBehavior() async throws {
    // Malformed attachment citation - missing citationTitle parameter
    let markdown = """
    [9F742443](http://example.com?citationMarker=9F742443&brokenParam=value)
    """

    let document = await parser.parse(text: markdown)

    // Find the link in the parsed document
    var link: Markdown.Link?
    for child in document.children {
      if let paragraph = child as? Markdown.Paragraph {
        for paragraphChild in paragraph.children {
          if let foundLink = paragraphChild as? Markdown.Link {
            link = foundLink
            break
          }
        }
      }
      if link != nil { break }
    }

    guard let link = link else {
      XCTFail("Expected to find a link in the parsed markdown")
      return
    }

    // Verify this is an attachment citation (UUID in link text)
    XCTAssertTrue(link.isInlineCitation(coder: .default), "Link should be detected as attachment citation")

    // Test the convert method - should return empty for malformed attachment citations
    let attributeContainer: [NSAttributedString.Key: Any] = [:]
    let convertedString = link.convert(
      attributeContainer: attributeContainer,
      config: .default
    )

    // Should return empty string when attachment data extraction fails (better UX than showing UUID)
    XCTAssertEqual(
      convertedString.string,
      "",
      "Malformed attachment citations should return empty string rather than showing confusing UUIDs to users"
    )
  }

  // MARK: - BlockQuote Citation Integration Tests

  /// A citation inside a block quote shows its title, never the raw marker.
  ///
  /// Two shapes go in: one citation carrying a `citationTitle` (rendered as an
  /// attachment chip) and one plain link that merely mentions a marker
  /// (rendered as ordinary link text). Either way the reader must see a name —
  /// "Microsoft", "Google" — and never the `9F742443` marker.
  ///
  /// Reads the quote through `convert(with:)`, the same route the view takes,
  /// since block quotes now build a real attributed string rather than a
  /// flattened plain one (see `BlockQuoteContentTests`).
  func testBlockQuoteWithAttachmentCitations() async throws {
    let markdown = """
    > This quote contains an attachment citation [9F742443](http://example.com?citationMarker=9F742443&citationTitle=Microsoft&citationA11yValue=Microsoft) and regular citation [Google](http://example.com?citationMarker=9F742443)
    """

    let renderables = await parser.parse(text: markdown).convert(with: .default)

    // The quote's inline content, as the attributed string the view renders.
    guard case .blockQuote(_, let item) = renderables.first,
          case .nested(let children) = item.quoteType,
          case .text(let content) = children.first else {
      return XCTFail("Expected a block quote with text content")
    }

    // The titled citation became a chip carrying its title.
    var citationTitles: [String] = []
    content.enumerateAttribute(.attachment, in: NSRange(location: 0, length: content.length)) { value, _, _ in
      if let title = (value as? InlineCitationAttachment)?.citationData?.title {
        citationTitles.append(title)
      }
    }
    XCTAssertEqual(citationTitles, ["Microsoft"])

    // The plain link stayed readable text...
    XCTAssertTrue(
      content.string.contains("Google"),
      "BlockQuote should show the regular citation's text 'Google'. Got: '\(content.string)'"
    )
    // ...and the marker never reaches the reader, in either shape.
    XCTAssertFalse(
      content.string.contains("9F742443"),
      "BlockQuote should NOT show the marker in its text. Got: '\(content.string)'"
    )
  }

  /// Tests that plain text extraction works correctly for both citation types
  func testPlainTextExtractionForCitations() async throws {
    let markdownWithBothTypes = """
    Regular citation: [Microsoft](http://example.com?citationMarker=9F742443)

    Attachment citation: [9F742443](http://example.com?citationMarker=9F742443&citationTitle=Google&citationA11yValue=Google)
    """

    let plainText = await markdownWithBothTypes.markdownToPlainText()

    // Verify both citation types show proper titles
    XCTAssertTrue(
      plainText.contains("Microsoft"),
      "Plain text should show regular citation title. Got: '\(plainText)'"
    )
    XCTAssertTrue(
      plainText.contains("Google"),
      "Plain text should show attachment citation title extracted from URL. Got: '\(plainText)'"
    )
    XCTAssertFalse(
      plainText.contains("9F742443"),
      "Plain text should NOT contain UUID marker. Got: '\(plainText)'"
    )
  }

  func testMarkdownNestedFormatting() async throws {
    let text = """
    # Header with *italic* and **bold** and ***both***

    Normal text with ***bold italic*** and **nested *italic* inside** bold.
    """

    let document = await parser.parse(text: text)
    let renderableDoc = await RenderableDocument(document: document, config: .default)
    let renderables = renderableDoc.renderables

    // Verify it parses without error
    XCTAssertEqual(renderables.count, 2)

    let headingFonts = Typography.extraLargeTextFonts
    let paragraphFonts = Typography.baseTextFonts

    // 1. Inspect Heading
    guard case let .heading(_, level, headingContent) = renderables[0] else {
      XCTFail("First renderable should be a heading")
      return
    }
    XCTAssertEqual(level, 1)

    // Check that "italic" has italic font
    let italicRange = (headingContent.string as NSString).range(of: "italic")
    let italicFont = headingContent.attribute(.font, at: italicRange.location, effectiveRange: nil) as? UIFont
    XCTAssertEqual(italicFont, headingFonts.italic)

    // Check that "bold" has bold font
    let boldRange = (headingContent.string as NSString).range(of: "bold")
    let boldFont = headingContent.attribute(.font, at: boldRange.location, effectiveRange: nil) as? UIFont
    XCTAssertEqual(boldFont, headingFonts.bold)

    // Check that "both" has boldItalic font (nested Strong(Emphasis) resolves to boldItalic)
    let bothRange = (headingContent.string as NSString).range(of: "both")
    let bothFont = headingContent.attribute(.font, at: bothRange.location, effectiveRange: nil) as? UIFont
    XCTAssertEqual(bothFont, headingFonts.boldItalic)

    // 2. Inspect Paragraph
    guard case let .paragraph(_, paragraphContent) = renderables[1] else {
      XCTFail("Second renderable should be a paragraph")
      return
    }

    // Check "nested " (part of **nested *italic* inside**)
    let nestedRange = (paragraphContent.string as NSString).range(of: "nested ")
    let nestedFont = paragraphContent.attribute(.font, at: nestedRange.location, effectiveRange: nil) as? UIFont
    XCTAssertEqual(nestedFont, paragraphFonts.bold)

    // Check "italic" (nested inside bold) -> boldItalic
    let nestedItalicRange = (paragraphContent.string as NSString).range(of: "italic")
    let nestedItalicFont = paragraphContent.attribute(.font, at: nestedItalicRange.location, effectiveRange: nil) as? UIFont
    XCTAssertEqual(nestedItalicFont, paragraphFonts.boldItalic)
  }
}
#endif
