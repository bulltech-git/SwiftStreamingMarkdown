//
//  Copyright (c) Microsoft Corporation. All rights reserved.
//  Licensed under the MIT License. See LICENSE in the project root for license information.
//

// What is covered: `TextSelectionMenuStyle`, the switch that lets a host app
// replace the system edit menu on a text selection with its own menu.
//
// The rules:
//   • `.system` is the default, so nothing changes for anyone who doesn't ask
//   • every `with…` builder keeps the style (and `imageConfig`, which the
//     builders used to drop on the floor)
//   • `.custom` shows NO system menu and hands the selection to the listener,
//     with the selected text, a usable anchor, and working selectMore /
//     clearSelection callbacks
//   • `.custom` with nobody to hand the selection to keeps the system menu,
//     because a selection with no menu at all is a dead end for the reader
//
// How to run: the UIKit half needs an iOS simulator destination —
// `xcodebuild test -scheme SwiftStreamingMarkdown -destination 'platform=iOS Simulator,id=<udid>'
//  -only-testing:SwiftStreamingMarkdownTests/TextSelectionMenuStyleTests`.

import XCTest
@testable import SwiftStreamingMarkdown

final class TextSelectionMenuStyleTests: XCTestCase {

  /// Consumers who never heard of the option keep the system edit menu.
  func testDefaultStyleIsSystem() {
    XCTAssertEqual(MarkdownRenderConfig.default.textSelectionMenuStyle, .system)
    XCTAssertEqual(MarkdownRenderConfig().textSelectionMenuStyle, .system)
  }

  /// A builder rebuilds the whole config; it must not silently reset the style
  /// or the image config set by an earlier builder in the chain.
  func testBuildersKeepStyleAndImageConfig() {
    let images = ImageConfig(enabled: true, allowedImageTypes: [.remote(allowedDomains: [])])
    let config = MarkdownRenderConfig.default
      .withTextSelectionMenuStyle(.custom)
      .withImageConfig(images)
      .withBlockSpacing(value: 12)
      .withThematicBreakColor(value: .red)

    XCTAssertEqual(config.textSelectionMenuStyle, .custom)
    XCTAssertEqual(config.imageConfig, images)
    XCTAssertEqual(config.blockSpacing, 12)
  }

  /// Dynamic Type scaling rebuilds the config too — same promise.
  func testDynamicTypeScalingKeepsStyle() {
    let scaled = MarkdownRenderConfig.default
      .withTextSelectionMenuStyle(.custom)
      .scaled(for: .accessibility2)

    XCTAssertEqual(scaled.textSelectionMenuStyle, .custom)
  }

#if canImport(UIKit)
  private let text = "Hello wonderful world"
  private let wonderful = NSRange(location: 6, length: 9)

  @MainActor
  private func makeParagraph(style: TextSelectionMenuStyle,
                             controller: MarkdownController?,
                             canSelectMore: Bool = true) -> ParagraphUIView {
    let view = ParagraphUIView(frame: CGRect(x: 0, y: 0, width: 320, height: 60), textContainer: nil)
    view.setParagraphContents(NSMutableAttributedString(string: text), lineSpacing: nil, animatedByWord: false)
    view.setTextContextMenu(TextContextMenu(menuGroups: [
      TextContextMenuGroup(title: nil, image: nil, displayInline: true,
                           items: [TextContextMenuItem(id: "host.item", title: "Host item")])
    ]))
    view.setMarkdownController(controller)
    view.setTextSelectionMenuStyle(style, canSelectMore: canSelectMore)
    view.layoutIfNeeded()
    return view
  }

  /// `.custom`: the edit menu comes back empty (nothing on screen) and the
  /// listener gets the selection instead.
  @MainActor
  func testCustomStyleHandsSelectionToListenerAndShowsNoMenu() async {
    let listener = SelectionRecordingListener()
    let controller = MarkdownController(listener: listener)
    let view = makeParagraph(style: .custom, controller: controller)

    let menu = view.textView(view, editMenuForTextIn: wonderful, suggestedActions: [])

    XCTAssertEqual(menu?.children.count, 0, "the system edit menu must not appear")
    let request = await listener.nextRequest()
    XCTAssertEqual(request.selectedContent, "wonderful")
    XCTAssertFalse(request.anchorRect.isEmpty, "the host needs somewhere to anchor its menu")
  }

  /// The request's callbacks reach back into the package: Select more opens
  /// the full-document modal, clearSelection drops the highlight.
  @MainActor
  func testRequestCallbacksSelectMoreAndClearSelection() async {
    let listener = SelectionRecordingListener()
    let controller = MarkdownController(listener: listener)
    let view = makeParagraph(style: .custom, controller: controller)
    view.selectedRange = wonderful

    _ = view.textView(view, editMenuForTextIn: wonderful, suggestedActions: [])
    let request = await listener.nextRequest()

    XCTAssertTrue(request.canSelectMore)
    request.selectMore()
    XCTAssertTrue(controller.isTextSelectionRequested)

    request.clearSelection()
    XCTAssertEqual(view.selectedRange.length, 0)
  }

  /// With "Select more text" disabled in the config, the request says so and
  /// does nothing when asked anyway.
  @MainActor
  func testSelectMoreIsInertWhenDisabled() async {
    let listener = SelectionRecordingListener()
    let controller = MarkdownController(listener: listener)
    let view = makeParagraph(style: .custom, controller: controller, canSelectMore: false)

    _ = view.textView(view, editMenuForTextIn: wonderful, suggestedActions: [])
    let request = await listener.nextRequest()

    XCTAssertFalse(request.canSelectMore)
    request.selectMore()
    XCTAssertFalse(controller.isTextSelectionRequested)
  }

  /// `.system` keeps today's behavior: the host's items merged into a real menu.
  @MainActor
  func testSystemStyleBuildsTheMergedMenu() {
    let view = makeParagraph(style: .system, controller: MarkdownController(listener: nil))

    let menu = view.textView(view, editMenuForTextIn: wonderful, suggestedActions: [])

    XCTAssertFalse(menu?.children.isEmpty ?? true)
  }

  /// `.custom` with no controller: nobody would receive the selection, so the
  /// system path stays rather than leaving the reader with no menu.
  @MainActor
  func testCustomStyleWithoutControllerFallsBackToSystemMenu() {
    let view = makeParagraph(style: .custom, controller: nil)

    let menu = view.textView(view, editMenuForTextIn: wonderful, suggestedActions: [])

    XCTAssertFalse(menu?.children.isEmpty ?? true)
  }
#endif
}

/// Records the first selection-menu request it receives.
@MainActor
private final class SelectionRecordingListener: MarkdownListener {

  private var received: TextSelectionMenuRequest?
  private var continuation: CheckedContinuation<TextSelectionMenuRequest, Never>?

  func nextRequest() async -> TextSelectionMenuRequest {
    if let received { return received }
    return await withCheckedContinuation { self.continuation = $0 }
  }

  func onSelectionMenuRequest(_ request: TextSelectionMenuRequest) async {
    if let continuation {
      self.continuation = nil
      continuation.resume(returning: request)
    } else {
      received = request
    }
  }

  nonisolated func onRender(markdown: RenderableDocument) async {}
  nonisolated func onTableCopyTap(content: String) async {}
  nonisolated func onTableDownloadTap(content: String) async {}
  nonisolated func onContextMenuAppear(id: String, selectedContent: String) async {}
  nonisolated func onContextMenuTap(id: String, selectedContent: String) async {}
  nonisolated func onImageTap(image: MarkdownImage) async {}
}
