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
//   • the request ends when the reader moves the selection on (drags a
//     handle, taps elsewhere): the listener is told, so the host can hide its
//     menu, and the stale request can no longer clear the new selection
//   • UIKit asking again for the same selection replaces the request quietly
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

  /// A handle drag (or a tap elsewhere) changes the selection the host's menu
  /// was opened for: the listener hears the request ended, and the stale
  /// request can no longer clear the selection the reader is making now.
  @MainActor
  func testChangingTheSelectionEndsTheRequest() async {
    let listener = SelectionRecordingListener()
    let controller = MarkdownController(listener: listener)
    let view = makeParagraph(style: .custom, controller: controller)
    view.selectedRange = wonderful

    _ = view.textView(view, editMenuForTextIn: wonderful, suggestedActions: [])
    let request = await listener.nextRequest()

    let wonderfulWorld = NSRange(location: 6, length: 15)
    view.selectedRange = wonderfulWorld
    view.textViewDidChangeSelection(view) // what UIKit calls as the handle moves

    let ended = await listener.nextEnd()
    XCTAssertTrue(ended === request)
    request.clearSelection()
    XCTAssertEqual(view.selectedRange, wonderfulWorld, "a stale request must not clear the new selection")
  }

  /// UIKit asks again for a selection it already asked about (a tap on it, a
  /// handle drag that ends). The newer request takes over with no end event,
  /// and the replaced one can no longer clear the highlight.
  @MainActor
  func testNewerRequestForTheSameSelectionTakesOverQuietly() async {
    let listener = SelectionRecordingListener()
    let controller = MarkdownController(listener: listener)
    let view = makeParagraph(style: .custom, controller: controller)
    view.selectedRange = wonderful

    _ = view.textView(view, editMenuForTextIn: wonderful, suggestedActions: [])
    let first = await listener.nextRequest()
    _ = view.textView(view, editMenuForTextIn: wonderful, suggestedActions: [])
    let second = await listener.nextRequest()

    first.clearSelection()
    XCTAssertEqual(view.selectedRange, wonderful, "the replaced request must not clear the live selection")

    view.selectedRange = NSRange(location: 0, length: 0)
    view.textViewDidChangeSelection(view)
    let ended = await listener.nextEnd()
    XCTAssertTrue(ended === second, "only the request on screen ends — ends arrive in order, so the first never did")
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

/// Records the selection-menu requests it receives, and the ones that end.
@MainActor
private final class SelectionRecordingListener: MarkdownListener {

  private let requests = RequestInbox()
  private let ends = RequestInbox()

  func nextRequest() async -> TextSelectionMenuRequest { await requests.next() }
  func nextEnd() async -> TextSelectionMenuRequest { await ends.next() }

  func onSelectionMenuRequest(_ request: TextSelectionMenuRequest) async { requests.deliver(request) }
  func onSelectionMenuEnd(_ request: TextSelectionMenuRequest) async { ends.deliver(request) }

  nonisolated func onRender(markdown: RenderableDocument) async {}
  nonisolated func onTableCopyTap(content: String) async {}
  nonisolated func onTableDownloadTap(content: String) async {}
  nonisolated func onContextMenuAppear(id: String, selectedContent: String) async {}
  nonisolated func onContextMenuTap(id: String, selectedContent: String) async {}
  nonisolated func onImageTap(image: MarkdownImage) async {}
}

/// Requests in the order they arrived, handed out one at a time.
@MainActor
private final class RequestInbox {

  private var queued: [TextSelectionMenuRequest] = []
  private var waiter: CheckedContinuation<TextSelectionMenuRequest, Never>?

  func next() async -> TextSelectionMenuRequest {
    if !queued.isEmpty { return queued.removeFirst() }
    return await withCheckedContinuation { waiter = $0 }
  }

  func deliver(_ request: TextSelectionMenuRequest) {
    if let waiter {
      self.waiter = nil
      waiter.resume(returning: request)
    } else {
      queued.append(request)
    }
  }
}
