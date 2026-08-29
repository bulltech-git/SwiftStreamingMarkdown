//
//  Copyright (c) Microsoft Corporation. All rights reserved.
//  Licensed under the MIT License. See LICENSE in the project root for license information.
//

import SwiftUI

/// A scrollable, uneditable, selectable text view used by `TextSelectionView`.
/// On appearance it preselects the first paragraph so the user can immediately
/// extend the selection.
struct SelectableTextView: View {

  /// Paragraph fonts, already scaled for the reader's text size by
  /// `DocumentView` — never `Typography`, whose values are design-size only.
  @Environment(\.markdownConfig) private var config: MarkdownRenderConfig

  let text: String

  var body: some View {
    SelectableTextViewRepresentable(text: text, fonts: config.paragraphStyle.textFonts)
  }
}

private func selectionAttributedString(for text: String, fonts: TextFonts) -> NSAttributedString {
  let font = fonts.normal
  let paragraphStyle = NSMutableParagraphStyle()
  // .natural (not .left) so RTL content (Arabic, Hebrew, ...) reads right,
  // matching ParagraphUIView/ParagraphNSView's own alignment.
  paragraphStyle.alignment = .natural
  if let preferredLineHeight = fonts.preferredLineHeight, preferredLineHeight > font.lineHeight {
    paragraphStyle.lineSpacing = preferredLineHeight - font.lineHeight
  }
  var attributes: [NSAttributedString.Key: Any] = [
    .font: font,
    .foregroundColor: MDColor(Color.Theme.Foreground.Primary.Primary800),
    .paragraphStyle: paragraphStyle
  ]
  if let kern = fonts.preferredLetterSpacing {
    attributes[.kern] = kern
  }
  return NSAttributedString(string: text, attributes: attributes)
}

/// The range of the first paragraph (up to the first newline), or the whole
/// string when it contains no newline.
private func firstParagraphRange(in text: String) -> NSRange {
  let nsText = text as NSString
  guard nsText.length > 0 else { return NSRange(location: 0, length: 0) }
  let newline = nsText.rangeOfCharacter(from: .newlines)
  if newline.location != NSNotFound {
    return NSRange(location: 0, length: newline.location)
  }
  return NSRange(location: 0, length: nsText.length)
}

#if canImport(UIKit)
import UIKit

private struct SelectableTextViewRepresentable: UIViewRepresentable {
  let text: String
  let fonts: TextFonts

  func makeUIView(context: Context) -> UITextView {
    let textView = UITextView()
    textView.isEditable = false
    textView.isSelectable = true
    textView.backgroundColor = .clear
    textView.showsVerticalScrollIndicator = false
    textView.tintColor = UIColor(Color.Theme.Accent.Accent600)
    textView.attributedText = selectionAttributedString(for: text, fonts: fonts)
    DispatchQueue.main.async {
      let range = firstParagraphRange(in: text)
      if let start = textView.position(from: textView.beginningOfDocument, offset: range.location),
         let end = textView.position(from: start, offset: range.length) {
        textView.selectedTextRange = textView.textRange(from: start, to: end)
        textView.becomeFirstResponder()
      }
    }
    return textView
  }

  func updateUIView(_ textView: UITextView, context: Context) {
    // Also when only the fonts moved: the text is unchanged when the reader
    // changes their text size mid-selection.
    if textView.attributedText.string != text || textView.font != fonts.normal {
      textView.attributedText = selectionAttributedString(for: text, fonts: fonts)
    }
  }
}
#elseif canImport(AppKit)
import AppKit

private struct SelectableTextViewRepresentable: NSViewRepresentable {
  let text: String
  let fonts: TextFonts

  func makeNSView(context: Context) -> NSScrollView {
    let scrollView = NSTextView.scrollableTextView()
    scrollView.drawsBackground = false
    scrollView.hasVerticalScroller = true

    guard let textView = scrollView.documentView as? NSTextView else {
      return scrollView
    }
    textView.isEditable = false
    textView.isSelectable = true
    textView.drawsBackground = false
    textView.textContainerInset = NSSize(width: 0, height: 0)
    textView.textStorage?.setAttributedString(selectionAttributedString(for: text, fonts: fonts))

    DispatchQueue.main.async {
      textView.setSelectedRange(firstParagraphRange(in: text))
      textView.window?.makeFirstResponder(textView)
    }
    return scrollView
  }

  func updateNSView(_ scrollView: NSScrollView, context: Context) {
    guard let textView = scrollView.documentView as? NSTextView else { return }
    if textView.string != text || textView.font != fonts.normal {
      textView.textStorage?.setAttributedString(selectionAttributedString(for: text, fonts: fonts))
    }
  }
}
#endif
