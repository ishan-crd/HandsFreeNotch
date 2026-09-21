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
        guard error == nil, let result else { return nil }
        return result.stringValue ?? ""
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

    // MARK: - Browsers

    /// A browser we can drive through Apple events. Firefox has no such interface.
    public struct Browser {
        public let name: String
        let tabNoun: String  // Safari says "current tab", the Chromium family says "active tab"
    }

    private static let browsers: [String: Browser] = [
        "com.apple.Safari": Browser(name: "Safari", tabNoun: "current tab"),
        "com.google.Chrome": Browser(name: "Google Chrome", tabNoun: "active tab"),
        "com.google.Chrome.canary": Browser(name: "Google Chrome Canary", tabNoun: "active tab"),
        "com.brave.Browser": Browser(name: "Brave Browser", tabNoun: "active tab"),
        "com.microsoft.edgemac": Browser(name: "Microsoft Edge", tabNoun: "active tab"),
        "company.thebrowser.Browser": Browser(name: "Arc", tabNoun: "active tab"),
        "com.vivaldi.Vivaldi": Browser(name: "Vivaldi", tabNoun: "active tab"),
        "com.operasoftware.Opera": Browser(name: "Opera", tabNoun: "active tab"),
    ]

    /// The browser in front right now, if it is one we can script.
    public static func frontmostBrowser() -> Browser? {
        guard let id = NSWorkspace.shared.frontmostApplication?.bundleIdentifier else { return nil }
        return browsers[id]
    }

    public static func currentTabURL(of browser: Browser) -> URL? {
        appleScript("tell application \"\(browser.name)\" to get URL of \(browser.tabNoun) of front window").flatMap(URL.init(string:))
    }

    /// Navigates the front tab in place. False when the browser refused or has no window.
    @discardableResult
    public static func navigateCurrentTab(of browser: Browser, to url: URL) -> Bool {
        let escaped = url.absoluteString.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        return appleScript("tell application \"\(browser.name)\" to set URL of \(browser.tabNoun) of front window to \"\(escaped)\"") != nil
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
