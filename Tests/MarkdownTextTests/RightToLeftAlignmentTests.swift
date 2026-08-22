//
//  Copyright (c) Microsoft Corporation. All rights reserved.
//  Licensed under the MIT License. See LICENSE in the project root for license information.
//

import Foundation
@testable import SwiftStreamingMarkdown
import XCTest

/// Covers the direction heuristic behind right-to-left rendering.
///
/// THE RULE: alignment follows the *content's* script, never the device's
/// locale. An Arabic answer reads right-to-left on a device set to English,
/// and an English answer reads left-to-right on a device set to Arabic —
/// otherwise a multilingual chat mis-aligns half its messages.
///
/// Paragraphs and headings get this for free: `ParagraphUIView`/`ParagraphNSView`
/// use `.natural` alignment, which TextKit resolves per paragraph from the
/// text itself. Block quotes cannot — they render through a plain SwiftUI
/// `Text`, which has no attributed-string paragraph style for `.natural` to
/// act on — so `BlockQuoteView` reads `startsRightToLeft` instead. These tests
/// pin that helper's behavior, since it is the only place the two paths can
/// drift apart.
final class RightToLeftAlignmentTests: XCTestCase {

  // MARK: - Right-to-left scripts

  /// Every RTL script the helper claims to know must be detected, not just
  /// Arabic — Hebrew, Syriac, Thaana and N'Ko share the same layout need.
  func testRightToLeftScriptsAreDetected() {
    let samples: [String: String] = [
      "Arabic": "أهلا بك",
      "Arabic (Moroccan darija)": "مول الكوتشي.. جمع كلشي",
      "Hebrew": "שלום עולם",
      "Syriac": "ܫܠܡܐ",
      "Thaana": "ދިވެހި",
      "N'Ko": "ߒߞߏ"
    ]

    for (script, text) in samples {
      XCTAssertTrue(text.startsRightToLeft, "\(script) should be detected as right-to-left")
    }
  }

  // MARK: - Left-to-right scripts

  /// The mirror case: nothing that isn't an RTL script may be flipped.
  func testLeftToRightScriptsAreNotFlipped() {
    let samples: [String: String] = [
      "English": "Hello world",
      "French": "Bonjour le monde",
      "Cyrillic": "Привет мир",
      "Greek": "Γειά σου κόσμε",
      "Han": "你好世界",
      "Japanese": "こんにちは"
    ]

    for (script, text) in samples {
      XCTAssertFalse(text.startsRightToLeft, "\(script) should stay left-to-right")
    }
  }

  // MARK: - Leading non-letters

  /// Markdown quotes routinely open with punctuation, digits, emoji or
  /// whitespace. Those carry no direction of their own, so the decision must
  /// come from the first actual letter — otherwise an Arabic quote that starts
  /// with `"` or a bullet renders flush left.
  func testDirectionComesFromFirstLetterNotLeadingSymbols() {
    XCTAssertTrue("  \"أهلا بك\"".startsRightToLeft,
                  "leading whitespace and quotes must not decide direction")
    XCTAssertTrue("1986 — مشينا فرحانين".startsRightToLeft,
                  "a leading number must not decide direction")
    XCTAssertTrue("📜 أهلا".startsRightToLeft,
                  "a leading emoji must not decide direction")
    XCTAssertFalse("📜 Hello".startsRightToLeft,
                   "the same rule must not flip left-to-right text")
  }

  // MARK: - Mixed content

  /// Mixed text is decided by whichever script opens it, matching how TextKit
  /// resolves `.natural` for a paragraph.
  func testMixedTextFollowsTheOpeningScript() {
    XCTAssertTrue("أهلا بك in Morocco".startsRightToLeft,
                  "Arabic-led text stays right-to-left when it embeds English")
    XCTAssertFalse("Welcome to المغرب".startsRightToLeft,
                   "English-led text stays left-to-right when it embeds Arabic")
  }

  // MARK: - Degenerate input

  /// Text with no letters at all has no direction to read; it must not throw
  /// or guess RTL, because the default layout everywhere else is left-to-right.
  func testTextWithoutLettersDefaultsToLeftToRight() {
    XCTAssertFalse("".startsRightToLeft)
    XCTAssertFalse("   ".startsRightToLeft)
    XCTAssertFalse("123 456".startsRightToLeft)
    XCTAssertFalse("--- *** ---".startsRightToLeft)
  }
}
