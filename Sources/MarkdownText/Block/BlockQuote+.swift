//
//  Copyright (c) Microsoft Corporation. All rights reserved.
//  Licensed under the MIT License. See LICENSE in the project root for license information.
//

import Foundation
import Markdown
import SwiftUI

extension BlockQuote: BlockConvertible {
  /// Builds each child as real attributed content — via the same
  /// `buildParagraphContent` paragraphs use — rather than flattening it to a
  /// plain string. A plain string would discard link destinations and
  /// bold/italic/citations along with them; nothing downstream could recover
  /// them, since the quote's own text view has no attributed string to
  /// re-derive from. `container` already carries this quote's font/color
  /// (set by `convert`, below), so nested quotes keep it too.
  ///
  /// Every child is kept. This loop used to handle only inline containers
  /// (paragraphs, headings) and nested quotes, so a quote whose body was a
  /// list, a code block, a table or a rule had that body silently deleted —
  /// `> DEFINITIONS` followed by `> - **term**: meaning` rendered as the bare
  /// word "DEFINITIONS". Those children now go through their own converter and
  /// render as the real thing inside the quote (`BlockQuoteType.block`).
  private func quoteTypes(attributeContainer: NSAttributeContainer, config: MarkdownRenderConfig) -> BlockQuoteType {
    var finalQuoteTypes = [BlockQuoteType]()

    for child in children {
      if child is InlineContainer, let blockMarkup = child as? BlockMarkup {
        let content = blockMarkup.buildParagraphContent(container: attributeContainer, config: config)
        finalQuoteTypes.append(.text(content))
      } else if let blockQuoteContainer = child as? BlockQuote {
        finalQuoteTypes.append(blockQuoteContainer.quoteTypes(attributeContainer: attributeContainer, config: config))
      } else if let convertible = child as? BlockConvertible {
        finalQuoteTypes.append(.block(convertible.convert(attributeContainer: attributeContainer, config: config)))
      } else if let fallback = child.unconvertibleBlockFallback(attributeContainer: attributeContainer, config: config) {
        finalQuoteTypes.append(.block(fallback))
      }
    }

    return .nested(finalQuoteTypes)
  }

  func convert(attributeContainer: NSAttributeContainer, config: MarkdownRenderConfig) -> MarkdownRenderable {
    var container = attributeContainer
    container[.font] = config.blockQuoteStyle.textFonts.normal
    container[.typography] = config.blockQuoteStyle.textFonts
    if let kern = config.blockQuoteStyle.textFonts.preferredLetterSpacing {
      container[.kern] = kern
    }
    container[.foregroundColor] = MDColor(config.blockQuoteStyle.textColor)
    return .blockQuote(id: id, item: .init(quoteType: quoteTypes(attributeContainer: container, config: config)))
  }
}

struct BlockQuoteRenderable: Equatable {
  let quoteType: BlockQuoteType
}
