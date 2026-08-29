//
//  Copyright (c) Microsoft Corporation. All rights reserved.
//  Licensed under the MIT License. See LICENSE in the project root for license information.
//

import Foundation
import SwiftUI
import Equatable

/// A source of incremental Markdown text for `StreamedMarkdownView`.
///
/// Each value yielded by `text` is a *complete snapshot* of the Markdown
/// source so far (a growing prefix), not an incremental delta. The view
/// re-parses each snapshot and updates the rendered output.
public protocol StreamedMarkdownSource {
  var text: AsyncStream<String> { get }
}

/// A SwiftUI view that incrementally parses and renders streamed Markdown.
///
/// Provide a `StreamedMarkdownSource` whose `text` async sequence yields
/// progressively larger snapshots of the Markdown source; the view re-parses
/// on each emission and refreshes the rendered output.
@Equatable
public struct StreamedMarkdownView: View {

  private let config: MarkdownRenderConfig
  @StateObject private var controller: StreamedMarkdownController

  /// Create a `StreamedMarkdownView`.
  /// - Parameters:
  ///   - source: The streamed Markdown source. Each emission must be the
  ///     complete Markdown source so far, not an incremental delta.
  ///   - config: Render configuration. Defaults to `.default`.
  ///   - listener: Optional listener that receives render and interaction events.
  public init(
    source: StreamedMarkdownSource,
    config: MarkdownRenderConfig = .default,
    listener: MarkdownListener? = nil
  ) {
    self.config = config
    _controller = StateObject(
      wrappedValue: StreamedMarkdownController(source: source, config: config, listener: listener)
    )
  }

  public var body: some View {
    // The Dynamic Type read lives one level down, in a plain (non-`@Equatable`)
    // view: this one declares its own equality, so SwiftUI is free to skip its
    // body when nothing but the environment changed.
    ScaledStreamedMarkdownView(config: config, controller: controller)
  }
}

/// Renders on behalf of `StreamedMarkdownView` and keeps the controller's parse
/// config in step with the reader's text size — paragraph fonts are baked into
/// the attributed strings at parse time, so a text-size change re-parses the
/// latest snapshot without disturbing the running stream.
private struct ScaledStreamedMarkdownView: View {

  @Environment(\.dynamicTypeSize) private var dynamicTypeSize

  let config: MarkdownRenderConfig
  @ObservedObject var controller: StreamedMarkdownController

  var body: some View {
    // `config` is passed on unscaled: `DocumentView` scales what it publishes to
    // the tree, so scaling it here as well would compound.
    DocumentView(
      renderableDocument: controller.markdownToRender,
      config: config,
      listener: controller.listener
    )
    .task(id: dynamicTypeSize) {
      await controller.setParseConfig(config.scaled(for: dynamicTypeSize))
    }
    .task {
      await controller.start()
    }
    .onDisappear {
      Task {
        await controller.end()
      }
    }
  }
}

final class StreamedMarkdownController: ObservableObject {

  @Published var markdownToRender: RenderableDocument = .empty
  let listener: MarkdownListener?

  /// The config every snapshot is parsed with, already scaled for the reader's
  /// text size. Locked: the view writes it from the main actor while the
  /// streaming task reads it off it.
  @WithLock private var config: MarkdownRenderConfig
  /// The most recent snapshot, kept so a text-size change can re-parse it
  /// without touching the stream, which yields only once per emission.
  @WithLock private var latestText: String? = nil

  private let source: StreamedMarkdownSource
  private let parser = MarkdownParserImpl()
  private var task: Task<Void, Never>?

  init(
    source: StreamedMarkdownSource,
    config: MarkdownRenderConfig,
    listener: MarkdownListener? = nil
  ) {
    self.source = source
    self.config = config
    self.listener = listener
  }

  func start() async {
    task?.cancel()
    task = Task { [weak self] in
      guard let self else { return }
      for await text in self.source.text {
        if Task.isCancelled { return }
        self.latestText = text
        let renderable = await self.parser.parse(text: text, config: self.config)
        if Task.isCancelled { return }
        await MainActor.run {
          self.markdownToRender = renderable
        }
      }
    }
  }

  /// Adopts a new parse config and re-renders the latest snapshot with it.
  func setParseConfig(_ config: MarkdownRenderConfig) async {
    guard self.config != config else { return }
    self.config = config
    guard let text = latestText else { return }
    let renderable = await parser.parse(text: text, config: config)
    await MainActor.run {
      self.markdownToRender = renderable
    }
  }

  func end() async {
    task?.cancel()
    task = nil
  }
}
