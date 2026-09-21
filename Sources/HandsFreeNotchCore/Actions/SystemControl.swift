//
//  SystemControl.swift
//  HandsFreeNotch
//
//  Copyright © 2026 Ishan Gupta. MIT License.
//

import AppKit
import Foundation

/// Volume, sleep and the other things that are not a keystroke into the frontmost app.
public enum SystemControl {
    @discardableResult
    static func appleScript(_ source: String) -> String? {
        var error: NSDictionary?
        let result = NSAppleScript(source: source)?.executeAndReturnError(&error)
        return error == nil ? result?.stringValue : nil
    }

    public static func outputVolume() -> Int? {
        appleScript("output volume of (get volume settings)").flatMap(Int.init)
    }

    public static func setVolume(percent: Int) {
        appleScript("set volume output volume \(max(0, min(100, percent)))")
    }

    public static func setMuted(_ muted: Bool) {
        appleScript("set volume \(muted ? "with" : "without") output muted")
    }

    public static func sleep() {
        appleScript("tell application \"System Events\" to sleep")
    }

    public static func emptyTrash() {
        appleScript("tell application \"Finder\" to empty trash")
    }

    /// The URL on the clipboard, or the first http(s) URL inside clipboard text.
    public static func clipboardURL() -> URL? {
        let pb = NSPasteboard.general
        if let urls = pb.readObjects(forClasses: [NSURL.self]) as? [URL], let u = urls.first, u.scheme?.hasPrefix("http") == true {
            return u
        }
        guard let text = pb.string(forType: .string) else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let u = URL(string: trimmed), u.scheme?.hasPrefix("http") == true { return u }
        if let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue),
           let match = detector.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) {
            return match.url
        }
        if trimmed.contains("."), !trimmed.contains(" ") { return URL(string: "https://" + trimmed) }
        return nil
    }
}
