//
//  Copyright (c) Microsoft Corporation. All rights reserved.
//  Licensed under the MIT License. See LICENSE in the project root for license information.
//

import Foundation
import Markdown

extension String {

  /// Unicode ranges for scripts written right-to-left (Hebrew, Arabic and its
  /// related blocks, Syriac, Thaana, N'Ko, Samaritan, Mandaic).
  private static let rightToLeftRanges: [ClosedRange<UInt32>] = [
    0x0590...0x05FF, 0x0600...0x06FF, 0x0700...0x074F, 0x0750...0x077F,
    0x0780...0x07BF, 0x07C0...0x07FF, 0x0800...0x083F, 0x0840...0x085F,
    0x08A0...0x08FF, 0xFB1D...0xFDFF, 0xFE70...0xFEFF
  ]

  /// True when the first letter reads right-to-left. Mirrors the heuristic
  /// UIKit/AppKit's `.natural` text alignment resolves per paragraph
  /// automatically — needed here because plain SwiftUI `Text` has no
  /// attributed-string paragraph style to hang that behavior on, so call
  /// sites that build layout from content (rather than inheriting
  /// `\.layoutDirection`) read this instead.
  var startsRightToLeft: Bool {
    for scalar in unicodeScalars where CharacterSet.letters.contains(scalar) {
      return Self.rightToLeftRanges.contains { $0.contains(scalar.value) }
    }
    return false
  }

  public func markdownToPlainText(removeHeading: Bool = false, coder: CitationCoder = .default) async -> String {
    let markdownParser = MarkdownParserImpl()
    let document = await markdownParser.parse(text: self)
    return document.extractPlainText(removeHeading: removeHeading, coder: coder)
  }

  static func itemPositionInTable(rowIndex: Int, totalRow: Int, columnIndex: Int, totalColumn: Int) -> String {
    return String(format:
      NSLocalizedString(
        "a11y_item_position_in_table",
        bundle: .module,
        value: "Row %d of %d, Column %d of %d",
        comment: "a11y understand their position in the table"
      ), rowIndex, totalRow, columnIndex, totalColumn)
  }

  static func openCitation(citationLabel: String) -> String {
    return String(format:
      NSLocalizedString(
        "a11y_open_citation",
        bundle: .module,
        value: "Open %@, link",
        comment: "Accessibility action to open a citation link"
      ), citationLabel)
  }

  static func markdownListItem(length: Int, index: Int, item: String) -> String {
    return String(format:
      NSLocalizedString(
        "markdown_list_item",
        bundle: .module,
        value: "List with %1$d items, item %2$d: %3$@",
        comment: "Accessibility label describing a list item's position, the list length, and the item's text"
      ),
      length,
      index,
      item)
  }

  static let taskListItemChecked = NSLocalizedString(
    "a11y_task_list_item_checked",
    bundle: .module,
    value: "checked",
    comment: "Accessibility suffix for a completed task list item"
  )

  static let taskListItemUnchecked = NSLocalizedString(
    "a11y_task_list_item_unchecked",
    bundle: .module,
    value: "unchecked",
    comment: "Accessibility suffix for an incomplete task list item"
  )

  static let codeCopyLabel = NSLocalizedString(
    "code_block_copy",
    bundle: .module,
    value: "Copy",
    comment: "Button label to copy a code block to clipboard"
  )

  static let codeCopiedLabel = NSLocalizedString(
    "code_block_copied",
    bundle: .module,
    value: "Copied",
    comment: "Button label shown after a code block has been copied to clipboard"
  )

  static let selectMoreTextLabel = NSLocalizedString(
    "select_more_text",
    bundle: .module,
    value: "Select more text",
    comment: "Edit-menu action and modal title for selecting the full document text"
  )

  static let textSelectionCloseLabel = NSLocalizedString(
    "a11y_text_selection_close",
    bundle: .module,
    value: "Close",
    comment: "Accessibility label for the button that dismisses the text selection modal"
  )

  static let imageLabel = NSLocalizedString(
    "a11y_image",
    bundle: .module,
    value: "Image",
    comment: "Accessibility label for a block image that has no alt text"
  )

  static let imageViewerCloseLabel = NSLocalizedString(
    "a11y_image_viewer_close",
    bundle: .module,
    value: "Close",
    comment: "Accessibility label for the button that dismisses the fullscreen image viewer"
  )

}

extension Markdown.Document {
  func extractPlainText(removeHeading: Bool, coder: CitationCoder = .default) -> String {
    var result = ""

    for child in children {
      result += child.extractPlainText(removeHeading: removeHeading, coder: coder)
      result += "\n\n"
    }

    return result.trimmingCharacters(in: .whitespacesAndNewlines)
  }
}

extension Markup {
  /// Recursively extracts plain text from any markdown element
  func extractPlainText(removeHeading: Bool, coder: CitationCoder = .default) -> String {
    // Handle specific markup types
    switch self {
    case let text as Markdown.Text:
      return text.string

    case let heading as Heading:
      return removeHeading ? "" : heading.plainText

    case let paragraph as Paragraph:
      // Extract text from paragraph children to handle attachment citations
      return paragraph.children.map {
        $0.extractPlainText(removeHeading: removeHeading, coder: coder)
      }.joined()

    case let codeBlock as CodeBlock:
      return codeBlock.code

    case let inlineCode as Markdown.InlineCode:
      return inlineCode.code

    case let link as Markdown.Link:
      // Handle attachment citations by extracting title from URL parameters
      if let destination = link.destination,
         let url = URL.fromMixedEncodingString(destination),
         coder.isCitation(linkText: link.plainText, url: url),
         let attachmentData = coder.decode(linkDestination: destination) {
        return attachmentData.title
      }

      // For regular links, extract the link text content, not the URL
      var linkText = ""
      for child in link.children {
        linkText += child.extractPlainText(removeHeading: removeHeading, coder: coder)
      }
      return linkText.isEmpty ? (link.destination ?? "") : linkText

    case let emphasis as Markdown.Emphasis:
      var text = ""
      for child in emphasis.children {
        text += child.extractPlainText(removeHeading: removeHeading, coder: coder)
      }
      return text

    case let strong as Markdown.Strong:
      var text = ""
      for child in strong.children {
        text += child.extractPlainText(removeHeading: removeHeading, coder: coder)
      }
      return text

    case let strikethrough as Markdown.Strikethrough:
      var text = ""
      for child in strikethrough.children {
        text += child.extractPlainText(removeHeading: removeHeading, coder: coder)
      }
      return text

    case let listItem as ListItem:
      var text = ""
      for child in listItem.children {
        text += child.extractPlainText(removeHeading: removeHeading, coder: coder)
      }
      return text

    case let orderedList as OrderedList:
      var text = ""
      for (index, child) in orderedList.children.enumerated() {
        if let listItem = child as? ListItem {
          text += "\(index + 1). \(listItem.extractPlainText(removeHeading: removeHeading, coder: coder))\n"
        }
      }
      return text

    case let unorderedList as UnorderedList:
      var text = ""
      for child in unorderedList.children {
        if let listItem = child as? ListItem {
          text += "• \(listItem.extractPlainText(removeHeading: removeHeading, coder: coder))\n"
        }
      }
      return text

    case let blockQuote as BlockQuote:
      var text = ""
      for child in blockQuote.children {
        text += child.extractPlainText(removeHeading: removeHeading, coder: coder)
      }
      return text

    case let table as Markdown.Table:
      var text = ""
      // Extract table headers
      for cell in table.head.children {
        if let tableCell = cell as? Markdown.Table.Cell {
          text += tableCell.extractPlainText(removeHeading: removeHeading, coder: coder) + "\t"
        }
      }
      text += "\n"

      // Extract table rows
      for row in table.body.children {
        if let tableRow = row as? Markdown.Table.Row {
          for cell in tableRow.children {
            if let tableCell = cell as? Markdown.Table.Cell {
              text += tableCell.extractPlainText(removeHeading: removeHeading, coder: coder) + "\t"
            }
          }
          text += "\n"
        }
      }
      return text

    case let tableCell as Markdown.Table.Cell:
      var text = ""
      for child in tableCell.children {
        text += child.extractPlainText(removeHeading: removeHeading, coder: coder)
      }
      return text

    case is ThematicBreak:
      return "---"

    case is Markdown.LineBreak:
      return "\n"

    case is Markdown.SoftBreak:
      return " "

    default:
      // For any other markup type, recursively process children
      var text = ""
      for child in children {
        text += child.extractPlainText(removeHeading: removeHeading, coder: coder)
      }
      return text
    }
  }
}

extension String {
  /// The readable text of a raw HTML fragment: tags removed, entities decoded.
  /// Used when a markdown block has no dedicated view and would otherwise be
  /// dropped — showing the words is always better than showing nothing.
  var strippingHTMLTags: String {
    let withoutTags = replacingOccurrences(of: "<[^>]+>",
                                           with: " ",
                                           options: .regularExpression)
    let decoded = withoutTags
      .replacingOccurrences(of: "&nbsp;", with: " ")
      .replacingOccurrences(of: "&lt;", with: "<")
      .replacingOccurrences(of: "&gt;", with: ">")
      .replacingOccurrences(of: "&quot;", with: "\"")
      .replacingOccurrences(of: "&#39;", with: "'")
      .replacingOccurrences(of: "&amp;", with: "&")
    return decoded
      .replacingOccurrences(of: "[ \\t]+", with: " ", options: .regularExpression)
      .trimmingCharacters(in: .whitespacesAndNewlines)
  }
}
