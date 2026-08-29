//
//  Copyright (c) Microsoft Corporation. All rights reserved.
//  Licensed under the MIT License. See LICENSE in the project root for license information.
//

import Foundation
import SwiftUI
import Equatable

/// This is a view that is able to both parse and render markdown with default configuration.
/// Use this view instead of `DocumentView` if you don't want to perform the parsing yourself.
@Equatable
public struct MarkdownView: View {

  private let text: String
  private let config: MarkdownRenderConfig
  @StateObject var controller: MarkdownViewController

  /// Create a `MarkdownView`.
  /// - Parameters:
  ///   - text: The raw Markdown source to parse and render.
  ///   - config: Render configuration. Defaults to `.default`.
  ///   - listener: Optional listener that receives render and interaction events.
  public init(
    text: String,
    config: MarkdownRenderConfig = .default,
    listener: MarkdownListener? = nil
  ) {
    self.text = text
    self.config = config
    _controller = StateObject(wrappedValue: MarkdownViewController(listener: listener))
  }

  public var body: some View {
    // The Dynamic Type read lives one level down, in a plain (non-`@Equatable`)
    // view: this one declares its own equality, so SwiftUI is free to skip its
    // body when nothing but the environment changed.
    ScaledMarkdownView(text: text, config: config, controller: controller)
  }
}

/// Parses and renders on behalf of `MarkdownView`, re-parsing whenever the text
/// *or* the Dynamic Type size changes — paragraph fonts are baked into the
/// attributed strings at parse time, so a text-size change is a re-parse.
private struct ScaledMarkdownView: View {

  @Environment(\.dynamicTypeSize) private var dynamicTypeSize

  let text: String
  let config: MarkdownRenderConfig
  @ObservedObject var controller: MarkdownViewController

  /// `.task` identity: either half invalidates the parsed document.
  private struct ParseKey: Equatable {
    let text: String
    let dynamicTypeSize: DynamicTypeSize
  }

  var body: some View {
    // `config` is passed on unscaled: `DocumentView` scales what it publishes to
    // the tree, so scaling it here as well would compound.
    DocumentView(renderableDocument: controller.renderable ?? .empty,
                 config: config,
                 listener: controller.listener)
    .task(id: ParseKey(text: text, dynamicTypeSize: dynamicTypeSize)) {
      await controller.parse(text: text, config: config.scaled(for: dynamicTypeSize))
    }
  }
}

final class MarkdownViewController: ObservableObject {

  @Published var renderable: RenderableDocument?

  private let parser = MarkdownParserImpl()

  let listener: MarkdownListener?

  init(listener: MarkdownListener? = nil) {
    self.listener = listener
  }

  /// Parses `text` with the Dynamic Type-scaled config supplied by the view.
  /// The config is a parameter rather than stored state because it follows the
  /// reader's text size, which can change at any moment.
  func parse(text: String, config: MarkdownRenderConfig) async {
    let renderable = await parser.parse(text: text, config: config)
    await MainActor.run {
      self.renderable = renderable
    }
  }
}
