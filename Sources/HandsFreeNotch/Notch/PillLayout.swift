//
//  PillLayout.swift
//  HandsFreeNotch
//
//  Copyright © 2026 Ishan Gupta. MIT License.
//

import AppKit
import CoreText

/// One line of text laid out around the camera housing: it starts on the left strip and, when
/// it does not fit there, continues on the right strip. Nothing is drawn under the housing.
struct PillLayout: Equatable {
    var leftText = ""
    var rightText = ""
    var left: CGFloat = 0      // width of the strip left of the housing
    var right: CGFloat = 0     // width of the strip right of the housing
    var font: NSFont = .systemFont(ofSize: 12)

    /// How far the whole pill shifts so the empty gap sits exactly on the housing.
    var offset: CGFloat { (right - left) / 2 }

    static let leftCap: CGFloat = 250
    static let rightCap: CGFloat = 250
    /// leading padding, icon, gap, trailing padding, slack for SwiftUI's metrics
    static let leftChrome: CGFloat = 12 + 14 + 6 + 10 + 8
    static let rightTextChrome: CGFloat = 8 + 8
    static let trailingPadding: CGFloat = 12

    /// - Parameters:
    ///   - keepTail: show the end of the text when it is too long (a live transcript), otherwise the start.
    ///   - indicator: width the right strip must reserve beside the text (bars, spinner, timing).
    static func make(text: String, font: NSFont, keepTail: Bool, indicator: CGFloat) -> PillLayout {
        var layout = PillLayout(font: font)
        var text = text.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return layout }

        let leftRoom = leftCap - leftChrome
        let rightRoom = rightCap - rightTextChrome - indicator - trailingPadding
        // A transcript that outgrows both strips drops its oldest words instead of its newest.
        if keepTail {
            while width(of: text, font) > leftRoom + rightRoom, let cut = text.firstIndex(of: " ") {
                text = "…" + text[text.index(after: cut)...]
                if width(of: text, font) <= leftRoom + rightRoom { break }
                text.removeFirst()  // drop the ellipsis before the next word goes
            }
        }

        let total = width(of: text, font)
        if total <= leftRoom {
            layout.leftText = text
            layout.left = ceil(total) + leftChrome
            layout.right = indicator > 0 ? indicator + trailingPadding + 8 : 0
            return layout
        }
        let (head, tail) = split(text, font: font, width: leftRoom)
        layout.leftText = head
        layout.rightText = tail
        layout.left = leftCap
        let tailWidth = min(ceil(width(of: tail, font)), rightRoom)
        layout.right = tailWidth + rightTextChrome + indicator + trailingPadding
        return layout
    }

    static func width(of text: String, _ font: NSFont) -> CGFloat {
        (text as NSString).size(withAttributes: [.font: font]).width
    }

    /// Breaks at a word boundary so the first part fits in `width`.
    static func split(_ text: String, font: NSFont, width: CGFloat) -> (String, String) {
        let attributed = NSAttributedString(string: text, attributes: [.font: font])
        let typesetter = CTTypesetterCreateWithAttributedString(attributed)
        var count = CTTypesetterSuggestLineBreak(typesetter, 0, Double(width))
        if count <= 0 { count = CTTypesetterSuggestClusterBreak(typesetter, 0, Double(width)) }
        let index = String.Index(utf16Offset: min(count, text.utf16.count), in: text)
        let head = String(text[..<index]).trimmingCharacters(in: .whitespaces)
        let tail = String(text[index...]).trimmingCharacters(in: .whitespaces)
        return (head, tail)
    }
}
