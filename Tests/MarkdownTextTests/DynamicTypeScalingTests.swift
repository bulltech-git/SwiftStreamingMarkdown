//
//  Copyright (c) Microsoft Corporation. All rights reserved.
//  Licensed under the MIT License. See LICENSE in the project root for license information.
//

#if canImport(UIKit)
@testable import SwiftStreamingMarkdown
import SwiftUI
import UIKit
import XCTest

/// Dynamic Type support.
///
/// The rule these tests protect: every font a `MarkdownRenderConfig` carries is
/// authored at the design size (`DynamicTypeSize.large`), and the *only* thing
/// that scales it for the reader's chosen text size is
/// `MarkdownRenderConfig.scaled(for:)`, applied at render time.
///
/// Scaling used to live inside `Typography`, which fed `static let` defaults —
/// computed once per process, so the text size froze at whatever it was when
/// the app first rendered Markdown (and, because parsing runs off the main
/// actor where the trait collection is unspecified, usually did not scale at
/// all). Anything that re-introduces scaling into `Typography` brings the bug
/// back, so `testTypographyIsAuthoredAtTheDesignSize` fails on it.
///
/// How to test by hand: open a conversation, then change
/// Settings ▸ Accessibility ▸ Display & Text Size ▸ Larger Text and come back —
/// the answer text must resize without relaunching the app.
final class DynamicTypeScalingTests: XCTestCase {

  // MARK: - Typography stays unscaled

  /// `Typography` must hand back the literal design sizes, never a scaled
  /// value: its output is cached in `static let` config defaults for the whole
  /// life of the process.
  func testTypographyIsAuthoredAtTheDesignSize() {
    XCTAssertEqual(Typography.base.mdFont.pointSize, 17.0)
    XCTAssertEqual(Typography.extraLarge.mdFont.pointSize, 28.0)
    XCTAssertEqual(Typography.code.mdFont.pointSize, 15.0)
    XCTAssertEqual(Typography.small.mdFont.pointSize, 15.0)
  }

  // MARK: - Scaling

  /// The design size is the identity: no allocation, no rounding drift, and the
  /// snapshot tests (which run at `.large`) keep their reference images.
  func testDesignSizeReturnsTheConfigUnchanged() {
    let config = MarkdownRenderConfig.default

    XCTAssertEqual(config.scaled(for: .large), config)
  }

  /// A smaller-than-default text size shrinks the text.
  func testSmallerTextSizeShrinksParagraphs() {
    let scaled = MarkdownRenderConfig.default.scaled(for: .xSmall)

    XCTAssertLessThan(
      scaled.paragraphStyle.textFonts.normal.pointSize,
      MarkdownRenderConfig.default.paragraphStyle.textFonts.normal.pointSize
    )
  }

  /// Every run of text the renderer can produce has to grow — a single one left
  /// behind is a paragraph, a heading or a table that ignores the setting.
  func testAccessibilitySizeGrowsEveryTextSurface() {
    let base = MarkdownRenderConfig.default
    let scaled = base.scaled(for: .accessibility3)

    XCTAssertGreaterThan(scaled.paragraphStyle.textFonts.normal.pointSize,
                         base.paragraphStyle.textFonts.normal.pointSize)
    XCTAssertGreaterThan(scaled.blockQuoteStyle.textFonts.normal.pointSize,
                         base.blockQuoteStyle.textFonts.normal.pointSize)
    XCTAssertGreaterThan(scaled.orderedListStyle.textFonts.normal.pointSize,
                         base.orderedListStyle.textFonts.normal.pointSize)
    XCTAssertGreaterThan(scaled.headingStyle.h1Font.normal.pointSize,
                         base.headingStyle.h1Font.normal.pointSize)
    XCTAssertGreaterThan(scaled.headingStyle.h6Font.normal.pointSize,
                         base.headingStyle.h6Font.normal.pointSize)
    XCTAssertGreaterThan(scaled.tableStyle.textFonts.normal.pointSize,
                         base.tableStyle.textFonts.normal.pointSize)
    XCTAssertGreaterThan(scaled.inlineStyle.linkTextFont.pointSize,
                         base.inlineStyle.linkTextFont.pointSize)
    XCTAssertGreaterThan(scaled.inlineStyle.codeTextFont.pointSize,
                         base.inlineStyle.codeTextFont.pointSize)
    XCTAssertGreaterThan(scaled.citationConfig.font.pointSize,
                         base.citationConfig.font.pointSize)
    XCTAssertGreaterThan(scaled.codeBlockConfig.codeTextFonts.normal.pointSize,
                         base.codeBlockConfig.codeTextFonts.normal.pointSize)
    XCTAssertGreaterThan(scaled.codeBlockConfig.chromeTextFonts.normal.pointSize,
                         base.codeBlockConfig.chromeTextFonts.normal.pointSize)
  }

  /// Bold and italic variants scale with the regular one, or emphasis inside a
  /// sentence would render at a different size than the sentence.
  func testEveryVariantOfAFontSetScalesTogether() {
    let base = MarkdownRenderConfig.default.paragraphStyle.textFonts
    let scaled = base.scaled(for: .accessibility3)

    XCTAssertGreaterThan(scaled.normal.pointSize, base.normal.pointSize)
    XCTAssertEqual(scaled.italic?.pointSize, scaled.normal.pointSize)
    XCTAssertEqual(scaled.bold?.pointSize, scaled.normal.pointSize)
    XCTAssertEqual(scaled.boldItalic?.pointSize, scaled.normal.pointSize)
  }

  /// Line height and letter spacing are point values too: leaving them behind
  /// gives cramped lines at accessibility sizes.
  func testLineHeightAndLetterSpacingFollowTheFonts() throws {
    let base = Typography.extraLargeTextFonts
    let scaled = base.scaled(for: .accessibility3)

    XCTAssertGreaterThan(try XCTUnwrap(scaled.preferredLineHeight),
                         try XCTUnwrap(base.preferredLineHeight))
    // -0.28 at the design size: a negative kern must scale away from zero.
    XCTAssertLessThan(try XCTUnwrap(scaled.preferredLetterSpacing),
                      try XCTUnwrap(base.preferredLetterSpacing))
  }

  /// Bigger text size, bigger text — at every step of the scale.
  func testScalingIsMonotonic() throws {
    let sizes: [DynamicTypeSize] = [
      .xSmall, .small, .medium, .large, .xLarge, .xxLarge, .xxxLarge,
      .accessibility1, .accessibility2, .accessibility3, .accessibility4, .accessibility5
    ]

    let pointSizes = sizes.map {
      MarkdownRenderConfig.default.scaled(for: $0).paragraphStyle.textFonts.normal.pointSize
    }

    for (smaller, larger) in zip(pointSizes, pointSizes.dropFirst()) {
      XCTAssertLessThanOrEqual(smaller, larger)
    }
    XCTAssertGreaterThan(try XCTUnwrap(pointSizes.last), try XCTUnwrap(pointSizes.first))
  }

  /// Scaling never depends on `UITraitCollection.current`: parsing runs off the
  /// main actor, where it is unspecified. Same size in, same fonts out.
  func testScalingIsIndependentOfTheAmbientTraitCollection() async {
    let expected = MarkdownRenderConfig.default.scaled(for: .accessibility5)

    let offMainActor = await Task.detached {
      MarkdownRenderConfig.default.scaled(for: .accessibility5)
    }.value

    XCTAssertEqual(offMainActor, expected)
  }

  /// A custom font set supplied by the app (the code viewer's monospaced
  /// config, for instance) is scaled like the bundled one — the consumer does
  /// not have to know about Dynamic Type at all.
  func testConsumerSuppliedFontsAreScaledToo() {
    let monospaced = MDFont.monospacedSystemFont(ofSize: 15, weight: .regular)
    let fonts = TextFonts(normal: monospaced, italic: nil, bold: nil, boldItalic: nil,
                          preferredLetterSpacing: nil, preferredLineHeight: nil)
    let config = MarkdownRenderConfig(paragraphStyle: .init(textFonts: fonts, textColor: .primary))

    let scaled = config.scaled(for: .accessibility3)

    XCTAssertGreaterThan(scaled.paragraphStyle.textFonts.normal.pointSize, 15)
    XCTAssertTrue(scaled.paragraphStyle.textFonts.normal.fontDescriptor.symbolicTraits.contains(.traitMonoSpace))
  }

  /// Scaling touches type only. `blockSpacing` is layout rhythm; scaling it as
  /// well turns an accessibility size into pages of whitespace.
  func testNonTypeSettingsAreLeftAlone() {
    let base = MarkdownRenderConfig.default
    let scaled = base.scaled(for: .accessibility5)

    XCTAssertEqual(scaled.blockSpacing, base.blockSpacing)
    XCTAssertEqual(scaled.thematicBreakColor, base.thematicBreakColor)
    XCTAssertEqual(scaled.paragraphStyle.textColor, base.paragraphStyle.textColor)
    XCTAssertEqual(scaled.shouldAnimateText, base.shouldAnimateText)
    XCTAssertEqual(scaled.imageConfig, base.imageConfig)
    XCTAssertEqual(scaled.textSelectionConfig, base.textSelectionConfig)
  }

  // MARK: - Parsed output

  /// The end of the chain: paragraph fonts are baked into the attributed string
  /// at parse time, so parsing with a scaled config is what actually resizes
  /// the answer on screen.
  func testParsingWithAScaledConfigProducesScaledText() async throws {
    let parser = MarkdownParserImpl()
    let markdown = "# Heading\n\nA paragraph with **bold** text."

    let base = await parser.parse(text: markdown, config: .default)
    let scaled = await parser.parse(text: markdown,
                                    config: MarkdownRenderConfig.default.scaled(for: .accessibility3))

    XCTAssertGreaterThan(try XCTUnwrap(firstFontPointSize(in: scaled)),
                         try XCTUnwrap(firstFontPointSize(in: base)))
  }

  private func firstFontPointSize(in document: RenderableDocument) -> CGFloat? {
    for renderable in document.renderables {
      guard case .heading(_, _, let contents) = renderable, contents.length > 0 else { continue }
      return (contents.attribute(.font, at: 0, effectiveRange: nil) as? MDFont)?.pointSize
    }
    return nil
  }
}

/// The bug this whole feature exists for, tested the way the reader meets it:
/// the text is already on screen when they change their text size.
///
/// `MarkdownView` and `DocumentView` are `@Equatable` — their value has not
/// changed, only the environment — so a regression here looks like "the text
/// only resizes after relaunching the app", which is exactly the behaviour that
/// was reported. The two views therefore read `\.dynamicTypeSize` from a plain
/// nested view and a modifier of their own; this test fails if that plumbing is
/// flattened back into them.
@MainActor
final class DynamicTypeLiveUpdateTests: XCTestCase {

  /// Drives the text size the way Settings does: the view stays, the
  /// environment changes underneath it.
  private final class TextSizeBox: ObservableObject {
    @Published var size: DynamicTypeSize = .large
  }

  private struct Harness: View {
    @ObservedObject var box: TextSizeBox

    var body: some View {
      MarkdownView(text: "A paragraph the reader is already looking at.")
        .dynamicTypeSize(box.size)
    }
  }

  func testTextResizesWhileItIsAlreadyOnScreen() async throws {
    let box = TextSizeBox()
    let host = UIHostingController(rootView: Harness(box: box))
    let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 800))
    window.rootViewController = host
    window.makeKeyAndVisible()
    host.view.layoutIfNeeded()

    let designSize = try await paragraphPointSize(in: window) { _ in true }
    box.size = .accessibility3
    let readerSize = try await paragraphPointSize(in: window) { $0 > designSize }

    XCTAssertGreaterThan(readerSize, designSize,
                         "Answer text must follow the reader's text size without a relaunch")
  }

  /// Waits for a rendered paragraph whose font satisfies `matches`, pumping the
  /// run loop: parsing is asynchronous, so the first pass after a change still
  /// shows the previous size.
  private func paragraphPointSize(
    in window: UIWindow,
    timeout: TimeInterval = 10,
    matches: (CGFloat) -> Bool
  ) async throws -> CGFloat {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
      window.layoutIfNeeded()
      if let size = firstParagraphPointSize(in: window), matches(size) {
        return size
      }
      RunLoop.main.run(until: Date().addingTimeInterval(0.05))
      await Task.yield()
    }
    XCTFail("No paragraph matching the expected size rendered within \(timeout)s — the text is not following Dynamic Type")
    throw WaitFailure.timedOut
  }

  private enum WaitFailure: Error { case timedOut }

  private func firstParagraphPointSize(in view: UIView) -> CGFloat? {
    if let paragraph = view as? ParagraphUIView, paragraph.paragraphContents.length > 0 {
      return (paragraph.paragraphContents.attribute(.font, at: 0, effectiveRange: nil) as? MDFont)?.pointSize
    }
    for subview in view.subviews {
      if let size = firstParagraphPointSize(in: subview) { return size }
    }
    return nil
  }
}
#endif
