//
//  Copyright (c) Microsoft Corporation. All rights reserved.
//  Licensed under the MIT License. See LICENSE in the project root for license information.
//

import Foundation
import SwiftUI

struct BlockQuoteView: View {
  let item: BlockQuoteType

  init(item: BlockQuoteRenderable) {
    self.item = item.quoteType
  }

  var body: some View {
    InternalBlockQuoteView(item: item)
  }
}

private struct InternalBlockQuoteView: View {
  let item: BlockQuoteType

  var body: some View {
    HStack(spacing: 8.0) {

      if item.isNested {
        QuoteDivider()
          .frame(width: 3.0)
      }

      VStack(spacing: 12.0) {
        switch item {
        case .text(let content):
          QuoteTextView(content: content)
            .fixedSize(horizontal: false, vertical: true)
        case .nested(let subItems):
          ForEach(subItems.indices, id: \.self) { index in
            InternalBlockQuoteView(item: subItems[index])
              .fixedSize(horizontal: false, vertical: true)
          }
          .fixedSize(horizontal: false, vertical: true)
        case .block(let renderable):
          SingleBlockView(renderable: renderable)
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
        }
      }
      .padding(.vertical, 4.0)
      .fixedSize(horizontal: false, vertical: true)
    }
    .fixedSize(horizontal: false, vertical: true)
  }
}

/// Renders through the same `ParagraphView` (UITextView/NSTextView) that
/// paragraphs use — not plain SwiftUI `Text` — so a block quote gets
/// everything paragraphs already get for free: tappable links (`ParagraphView`
/// reads `\.openURL` directly), preserved bold/italic/citations, and correct
/// RTL alignment via `.natural` (resolved by the text system from the
/// content's own script, so no separate direction heuristic is needed here).
struct QuoteTextView: View {
  let content: NSMutableAttributedString

  var body: some View {
    ParagraphView(contents: content)
      .fixedSize(horizontal: false, vertical: true)
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(.vertical, 4.0)
  }
}

struct QuoteDivider: View {
  var body: some View {
    RoundedRectangle(cornerRadius: 8.0, style: .continuous)
      .foregroundStyle(Color.Theme.Stroke.Muted.Muted300)
  }
}

indirect enum BlockQuoteType: Equatable {
  case text(NSMutableAttributedString)
  case nested([BlockQuoteType])
  /// A non-inline child of the quote — a list, code block, table, rule — kept
  /// as a full renderable so it draws through `SingleBlockView` like it would
  /// outside the quote. Before this case existed such children were dropped.
  case block(MarkdownRenderable)

  /// Whether this node draws the quote's vertical bar. Only the wrapper that
  /// holds a quote's children does; the children themselves sit inside it.
  var isNested: Bool {
    switch self {
    case .text, .block:
      false
    case .nested:
      true
    }
  }
}
