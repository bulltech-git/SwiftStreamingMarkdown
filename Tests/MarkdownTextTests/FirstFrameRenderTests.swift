//
//  Copyright (c) Microsoft Corporation. All rights reserved.
//  Licensed under the MIT License. See LICENSE in the project root for license information.
//

#if canImport(UIKit)
@testable import SwiftStreamingMarkdown
import SwiftUI
import UIKit
import XCTest

/// `MarkdownView` is laid out at its real height on its first frame.
///
/// The rule these tests protect: the view never draws an empty document while
/// a parse runs elsewhere. It used to parse in a `.task` and draw `.empty`
/// until the result came back a frame or more later — so inside a lazy stack
/// every row grew after it was built, and a chat thread jumped under the
/// reader whenever a row above them was built while scrolling up, or when an
/// answer replaced its loading indicator. Parsing now happens in the body,
/// once per text, through `RenderableDocument.cached(text:config:)`.
///
/// How to test by hand: open a long conversation in the app and scroll up
/// through answers that were never on screen — the text under your finger must
/// not move as rows above it come in.
final class FirstFrameRenderTests: XCTestCase {

  private let answer = """
    # A heading

    A first paragraph, long enough to wrap over several lines at a phone's \
    width, so that its height is unmistakably more than a single line.

    - one
    - two
    - three

    A closing paragraph.
    """

  // MARK: - The view

  /// One synchronous layout pass, as a lazy stack does when it builds a row,
  /// already measures the whole document — not an empty placeholder.
  @MainActor
  func testFirstLayoutPassMeasuresTheWholeDocument() {
    let host = UIHostingController(rootView: MarkdownView(text: answer))
    let size = host.sizeThatFits(in: CGSize(width: 320, height: CGFloat.greatestFiniteMagnitude))

    XCTAssertGreaterThan(size.height, 150)
  }

  /// A different text is a different document on that same first pass.
  @MainActor
  func testFirstLayoutPassFollowsTheText() {
    let short = UIHostingController(rootView: MarkdownView(text: "One line."))
    let long = UIHostingController(rootView: MarkdownView(text: answer))
    let fit = CGSize(width: 320, height: CGFloat.greatestFiniteMagnitude)

    XCTAssertLessThan(short.sizeThatFits(in: fit).height, long.sizeThatFits(in: fit).height)
  }

  // MARK: - The cache

  /// The cached document is exactly what the asynchronous parser produces, so
  /// moving the parse into the body changed when it runs, not what it makes.
  func testCachedDocumentMatchesTheAsyncParse() async {
    let config = MarkdownRenderConfig.default
    let parsed = await MarkdownParserImpl().parse(text: answer, config: config)

    XCTAssertEqual(RenderableDocument.cached(text: answer, config: config), parsed)
    XCTAssertFalse(RenderableDocument.cached(text: answer, config: config).isEmpty)
  }

  /// The config is part of the key: a reader's larger text size must get
  /// paragraphs set in the larger font, never the document cached for `.large`.
  func testScaledConfigIsItsOwnEntry() {
    let regular = RenderableDocument.cached(text: answer, config: .default)
    let larger = RenderableDocument.cached(text: answer, config: MarkdownRenderConfig.default.scaled(for: .accessibility3))

    XCTAssertNotEqual(regular, larger)
  }
}
#endif
