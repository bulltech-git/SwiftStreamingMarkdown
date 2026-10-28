//
//  Copyright (c) Microsoft Corporation. All rights reserved.
//  Licensed under the MIT License. See LICENSE in the project root for license information.
//

import CoreGraphics
import Foundation

/// Who presents the menu that follows a text selection.
public enum TextSelectionMenuStyle: Hashable, Sendable {
  /// The system edit menu (Copy, Look Up, Translate, …) with
  /// `MarkdownRenderConfig.textContextMenu` merged in. The default.
  case system

  /// No system menu. The selection is handed to
  /// `MarkdownListener.onSelectionMenuRequest(_:)` so the host can present its
  /// own UI — for example one menu shared by a long press on the text and a
  /// long press anywhere else on the message. `textContextMenu` is not shown.
  ///
  /// UIKit only (iOS, visionOS). On macOS the native right-click menu stays,
  /// because a right-click menu is what Mac users expect there.
  case custom
}

/// A selection waiting for the host's menu, delivered to
/// `MarkdownListener.onSelectionMenuRequest(_:)` when the render config uses
/// `TextSelectionMenuStyle.custom`.
///
/// The selection stays highlighted until the host calls `clearSelection()`,
/// so the reader can see what the host's menu will act on.
///
/// The request ends when the reader changes or clears that selection — drags
/// a handle, taps elsewhere — and the listener hears it through
/// `MarkdownListener.onSelectionMenuEnd(_:)`. A request that has ended, or
/// that a newer request for the same text replaced, no longer owns the
/// highlight: its `clearSelection()` does nothing.
@MainActor
public final class TextSelectionMenuRequest {
  /// The selected text, as plain text.
  public let selectedContent: String

  /// The selection's bounds in window coordinates — where a host anchors its
  /// menu. Matches SwiftUI's `.global` coordinate space.
  public let anchorRect: CGRect

  /// Whether `selectMore()` will do anything: `false` when
  /// `TextSelectionConfig.isEnabled` is `false`.
  public let canSelectMore: Bool

  /// The range the request was made for, in its paragraph's text.
  let selectedRange: NSRange

  /// `false` once the selection has moved on from this request.
  private(set) var isCurrent = true

  private let onSelectMore: @MainActor () -> Void
  private let onClearSelection: @MainActor () -> Void

  init(
    selectedContent: String,
    anchorRect: CGRect,
    canSelectMore: Bool,
    selectedRange: NSRange,
    selectMore: @escaping @MainActor () -> Void,
    clearSelection: @escaping @MainActor () -> Void
  ) {
    self.selectedContent = selectedContent
    self.anchorRect = anchorRect
    self.canSelectMore = canSelectMore
    self.selectedRange = selectedRange
    self.onSelectMore = selectMore
    self.onClearSelection = clearSelection
  }

  /// Presents the full-document text selection modal — the same one as the
  /// system menu's built-in "Select more text" action.
  public func selectMore() {
    guard canSelectMore else { return }
    onSelectMore()
  }

  /// Removes the selection highlight. Call it when the host's menu goes away.
  /// Does nothing once the request has ended, so a stale request never clears
  /// a selection the reader is still making.
  public func clearSelection() {
    guard isCurrent else { return }
    isCurrent = false
    onClearSelection()
  }

  /// The selection moved on: the reader changed it, or a newer request took over.
  func end() {
    isCurrent = false
  }
}
