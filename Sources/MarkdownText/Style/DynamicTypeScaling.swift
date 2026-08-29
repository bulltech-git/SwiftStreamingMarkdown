//
//  Copyright (c) Microsoft Corporation. All rights reserved.
//  Licensed under the MIT License. See LICENSE in the project root for license information.
//

import Foundation
import SwiftUI
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

// MARK: - Dynamic Type scaling
//
// Every font in a `MarkdownRenderConfig` is authored at the design size
// (`DynamicTypeSize.large`). Scaling is applied here, at render time, from the
// ambient `\.dynamicTypeSize` — never inside `Typography`, whose values end up
// in `static let` defaults that are computed once per process and would freeze
// the text size for the whole run of the app.
//
// `MarkdownView` scales the config it parses with, and `DocumentView` scales
// the config it publishes to the view tree, so a consumer never calls
// `scaled(for:)` itself. Calling it on an already-scaled config compounds the
// scaling, so scale a config once, from its design-size original.

extension DynamicTypeSize {

  #if canImport(UIKit)
  /// The UIKit content-size category matching this SwiftUI size, used to build
  /// the trait collection `UIFontMetrics` scales against. Unknown future cases
  /// fall back to the design size rather than guessing.
  var contentSizeCategory: UIContentSizeCategory {
    switch self {
    case .xSmall: return .extraSmall
    case .small: return .small
    case .medium: return .medium
    case .large: return .large
    case .xLarge: return .extraLarge
    case .xxLarge: return .extraExtraLarge
    case .xxxLarge: return .extraExtraExtraLarge
    case .accessibility1: return .accessibilityMedium
    case .accessibility2: return .accessibilityLarge
    case .accessibility3: return .accessibilityExtraLarge
    case .accessibility4: return .accessibilityExtraExtraLarge
    case .accessibility5: return .accessibilityExtraExtraExtraLarge
    @unknown default: return .large
    }
  }

  /// Trait collection carrying only this content-size category. Passed to
  /// `UIFontMetrics` so scaling never depends on `UITraitCollection.current`,
  /// which is unspecified on the background queue where parsing runs.
  var fontScalingTraits: UITraitCollection {
    UITraitCollection(preferredContentSizeCategory: contentSizeCategory)
  }
  #endif

  /// `true` when this size needs no work: the design size the package's fonts
  /// are authored at, and every size on AppKit, which has no Dynamic Type.
  var isDesignSize: Bool {
    #if canImport(UIKit)
    return self == .large
    #else
    return true
    #endif
  }
}

extension MDFont {
  /// This font scaled for the given Dynamic Type size, using the body metrics
  /// so every size in the scale keeps its relative proportions.
  func scaled(for dynamicTypeSize: DynamicTypeSize) -> MDFont {
    #if canImport(UIKit)
    guard !dynamicTypeSize.isDesignSize else { return self }
    return UIFontMetrics.default.scaledFont(for: self, compatibleWith: dynamicTypeSize.fontScalingTraits)
    #else
    return self
    #endif
  }
}

/// A point value (line height, letter spacing) scaled alongside the fonts it
/// belongs to, so line rhythm and kerning follow the text.
func scaledPointValue(_ value: CGFloat, for dynamicTypeSize: DynamicTypeSize) -> CGFloat {
  #if canImport(UIKit)
  guard !dynamicTypeSize.isDesignSize else { return value }
  return UIFontMetrics.default.scaledValue(for: value, compatibleWith: dynamicTypeSize.fontScalingTraits)
  #else
  return value
  #endif
}

extension TextFonts {
  /// Every variant, plus the preferred line height and letter spacing, scaled
  /// for the given Dynamic Type size.
  public func scaled(for dynamicTypeSize: DynamicTypeSize) -> TextFonts {
    guard !dynamicTypeSize.isDesignSize else { return self }
    return TextFonts(
      normal: normal.scaled(for: dynamicTypeSize),
      italic: italic?.scaled(for: dynamicTypeSize),
      bold: bold?.scaled(for: dynamicTypeSize),
      boldItalic: boldItalic?.scaled(for: dynamicTypeSize),
      preferredLetterSpacing: preferredLetterSpacing.map { scaledPointValue($0, for: dynamicTypeSize) },
      preferredLineHeight: preferredLineHeight.map { scaledPointValue($0, for: dynamicTypeSize) }
    )
  }
}

extension MarkdownRenderConfig.MarkdownTextStyle {
  func scaled(for dynamicTypeSize: DynamicTypeSize) -> Self {
    .init(textFonts: textFonts.scaled(for: dynamicTypeSize), textColor: textColor)
  }
}

extension MarkdownRenderConfig.MarkdownHeadingTextStyle {
  func scaled(for dynamicTypeSize: DynamicTypeSize) -> Self {
    .init(
      h1Font: h1Font.scaled(for: dynamicTypeSize),
      h2Font: h2Font.scaled(for: dynamicTypeSize),
      h3Font: h3Font.scaled(for: dynamicTypeSize),
      h4Font: h4Font.scaled(for: dynamicTypeSize),
      h5Font: h5Font.scaled(for: dynamicTypeSize),
      h6Font: h6Font.scaled(for: dynamicTypeSize),
      textColor: textColor
    )
  }
}

extension MarkdownRenderConfig.MarkdownTableTextStyle {
  func scaled(for dynamicTypeSize: DynamicTypeSize) -> Self {
    .init(
      textFonts: textFonts.scaled(for: dynamicTypeSize),
      headerTextColor: headerTextColor,
      regularTextColor: regularTextColor,
      headerBackgroundColor: headerBackgroundColor,
      borderColor: borderColor,
      actionButtonColor: actionButtonColor
    )
  }
}

extension MarkdownRenderConfig.MarkdownInlineTextStyle {
  func scaled(for dynamicTypeSize: DynamicTypeSize) -> Self {
    .init(
      boldTextColor: boldTextColor,
      linkTextFont: linkTextFont.scaled(for: dynamicTypeSize),
      linkTextColor: linkTextColor,
      linkUnderlineStyle: linkUnderlineStyle,
      codeTextFont: codeTextFont.scaled(for: dynamicTypeSize),
      codeTextColor: codeTextColor,
      codeBackgroundColor: codeBackgroundColor,
      codeUnderlineColor: codeUnderlineColor
    )
  }
}

extension MarkdownRenderConfig.CitationConfig {
  func scaled(for dynamicTypeSize: DynamicTypeSize) -> Self {
    .init(
      isEnabled: isEnabled,
      coder: coder,
      font: font.scaled(for: dynamicTypeSize),
      textColor: textColor,
      backgroundColor: backgroundColor
    )
  }
}

extension CodeBlockConfig {
  func scaled(for dynamicTypeSize: DynamicTypeSize) -> CodeBlockConfig {
    CodeBlockConfig(
      theme: theme,
      backgroundColor: backgroundColor,
      foregroundColor: foregroundColor,
      codeTextFonts: codeTextFonts.scaled(for: dynamicTypeSize),
      chromeTextFonts: chromeTextFonts.scaled(for: dynamicTypeSize)
    )
  }
}

extension MarkdownRenderConfig {

  /// A copy of this configuration with every font — paragraphs, headings,
  /// lists, block quotes, tables, inline code and links, citations and code
  /// blocks — scaled for the given Dynamic Type size, along with their line
  /// heights and letter spacing.
  ///
  /// Returns `self` unchanged at the design size (`.large`) and on AppKit, so
  /// the common path costs nothing. `blockSpacing` is deliberately left alone:
  /// it is layout rhythm, not type, and scaling it turns accessibility sizes
  /// into pages of whitespace.
  ///
  /// - Important: scale a design-size config. Scaling an already-scaled config
  ///   compounds, and `MarkdownView`/`DocumentView` already do this for you.
  public func scaled(for dynamicTypeSize: DynamicTypeSize) -> MarkdownRenderConfig {
    guard !dynamicTypeSize.isDesignSize else { return self }
    return MarkdownRenderConfig(
      shouldAnimateText: shouldAnimateText,
      blockQuoteStyle: blockQuoteStyle.scaled(for: dynamicTypeSize),
      headingStyle: headingStyle.scaled(for: dynamicTypeSize),
      orderedListStyle: orderedListStyle.scaled(for: dynamicTypeSize),
      paragraphStyle: paragraphStyle.scaled(for: dynamicTypeSize),
      tableStyle: tableStyle.scaled(for: dynamicTypeSize),
      inlineStyle: inlineStyle.scaled(for: dynamicTypeSize),
      textContextMenu: textContextMenu,
      citationConfig: citationConfig.scaled(for: dynamicTypeSize),
      codeBlockConfig: codeBlockConfig.scaled(for: dynamicTypeSize),
      blockSpacing: blockSpacing,
      textSelectionConfig: textSelectionConfig,
      thematicBreakColor: thematicBreakColor,
      imageConfig: imageConfig
    )
  }
}

/// Publishes `config`, scaled to the ambient Dynamic Type size, to the view
/// tree. A modifier rather than an inline `.environment(…)` call so the
/// `\.dynamicTypeSize` read lives in its own view-graph node: the views that
/// apply it are `@Equatable`, and SwiftUI may skip their body when only the
/// environment changed.
struct ScaledMarkdownConfig: ViewModifier {

  @Environment(\.dynamicTypeSize) private var dynamicTypeSize

  let config: MarkdownRenderConfig

  func body(content: Content) -> some View {
    content.environment(\.markdownConfig, config.scaled(for: dynamicTypeSize))
  }
}
