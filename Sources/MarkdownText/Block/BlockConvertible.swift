//
//  Copyright (c) Microsoft Corporation. All rights reserved.
//  Licensed under the MIT License. See LICENSE in the project root for license information.
//

import Foundation
import Markdown
import SwiftUI

/// A markdown block that can be converted into `MarkdownRenderable`

protocol BlockConvertible {

  /// Convert into `MarkdownRenderable`
  /// - Parameter attributeContainer: The inherited attributes
  /// - Parameter config: The mark down rendering config used to override fonts & text color if needed.
  /// - Returns: A `MarkdownRenderable` that is ready to be rendered by Views.
  func convert(attributeContainer: NSAttributeContainer, config: MarkdownRenderConfig) -> MarkdownRenderable
}

extension Markup {

  /// Converts every block-level child into a renderable, dropping none.
  ///
  /// The way in used to be `children.compactMap { $0 as? BlockConvertible }`,
  /// which silently discarded anything this renderer has no dedicated view for
  /// — a raw HTML block, a block directive, a custom block. A streaming
  /// renderer can shrug that off, since the next chunk redraws everything; a
  /// finished answer cannot, because the content is then simply gone from the
  /// screen with nothing to signal it. Anything unconvertible now falls back to
  /// its readable text (`unconvertibleBlockFallback`) instead of vanishing.
  func convertedBlockChildren(attributeContainer: NSAttributeContainer,
                              config: MarkdownRenderConfig) -> [MarkdownRenderable] {
    return children.compactMap { child in
      if let convertible = child as? BlockConvertible {
        return convertible.convert(attributeContainer: attributeContainer, config: config)
      }
      return child.unconvertibleBlockFallback(attributeContainer: attributeContainer, config: config)
    }
  }

  /// Last resort for a block this renderer has no view for: show its readable
  /// text as a paragraph. `nil` only when there is genuinely nothing to read,
  /// which is the one case where dropping loses nothing.
  ///
  /// Attributes already carried by `attributeContainer` win, so a fallback
  /// inside a block quote keeps the quote's own font and color rather than
  /// reverting to the body style.
  func unconvertibleBlockFallback(attributeContainer: NSAttributeContainer,
                                  config: MarkdownRenderConfig) -> MarkdownRenderable? {
    let text: String
    if let htmlBlock = self as? HTMLBlock {
      // `extractPlainText` bottoms out at "" for an HTML block: it is a leaf
      // node holding a raw string, with no inline children to recurse into.
      text = htmlBlock.rawHTML.strippingHTMLTags
    } else {
      text = extractPlainText(removeHeading: false, coder: config.citationConfig.coder)
    }

    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else {
      return nil
    }

    var container = attributeContainer
    container[.font] = container[.font] ?? config.paragraphStyle.textFonts.normal
    container[.typography] = container[.typography] ?? config.paragraphStyle.textFonts
    if container[.kern] == nil, let kern = config.paragraphStyle.textFonts.preferredLetterSpacing {
      container[.kern] = kern
    }
    container[.foregroundColor] = container[.foregroundColor] ?? MDColor(config.paragraphStyle.textColor)

    return .paragraph(id: id, content: NSMutableAttributedString(string: trimmed, attributes: container))
  }
}
