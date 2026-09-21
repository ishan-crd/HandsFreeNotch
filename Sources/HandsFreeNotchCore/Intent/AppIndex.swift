//
//  AppIndex.swift
//  HandsFreeNotch
//
//  Copyright © 2026 Ishan Gupta. MIT License.
//

import AppKit
import Foundation

/// An application the Mac can open.
public struct AppEntry: Equatable, Hashable {
    public let name: String
    public let url: URL
    public let bundleID: String?

    public init(name: String, url: URL, bundleID: String?) {
        self.name = name
        self.url = url
        self.bundleID = bundleID
    }
}

/// Every app on this Mac, with the names people actually say for them, so "open chrome" resolves
/// without a network call. Scanning the usual folders takes a few milliseconds; it runs once at
/// launch and again in the background when the index is older than `staleAfter`.
public final class AppIndex {
    public private(set) var entries: [AppEntry] = []
    private var lastScan: Date = .distantPast
    private let staleAfter: TimeInterval = 300
    private let queue = DispatchQueue(label: "handsfreenotch.appindex", qos: .utility)
    private let lock = NSLock()

    /// What people say -> what the bundle is called. Matching also tries the real name, so this
    /// only needs the nicknames.
    public static let aliases: [String: String] = [
        "chrome": "Google Chrome", "google": "Google Chrome",
        "vs code": "Visual Studio Code", "vscode": "Visual Studio Code", "code": "Visual Studio Code",
        "settings": "System Settings", "system preferences": "System Settings", "preferences": "System Settings",
        "terminal": "Terminal", "iterm": "iTerm", "i term": "iTerm",
        "finder": "Finder", "files": "Finder",
        "messages": "Messages", "imessage": "Messages", "text messages": "Messages",
        "mail": "Mail", "email": "Mail",
        "notes": "Notes", "calendar": "Calendar", "reminders": "Reminders", "photos": "Photos",
        "music": "Music", "apple music": "Music", "itunes": "Music",
        "app store": "App Store", "appstore": "App Store",
        "activity monitor": "Activity Monitor", "calculator": "Calculator", "preview": "Preview",
        "safari": "Safari", "facetime": "FaceTime", "face time": "FaceTime",
        "whatsapp": "WhatsApp", "whats app": "WhatsApp",
        "chat gpt": "ChatGPT", "chatgpt": "ChatGPT", "gpt": "ChatGPT",
        "claude": "Claude", "cursor": "Cursor", "x code": "Xcode", "xcode": "Xcode",
        "zoom": "zoom.us", "slack": "Slack", "discord": "Discord", "figma": "Figma", "notion": "Notion",
        "spotify": "Spotify", "telegram": "Telegram", "obsidian": "Obsidian", "arc": "Arc",
        "brave": "Brave Browser", "firefox": "Firefox", "edge": "Microsoft Edge",
        "word": "Microsoft Word", "excel": "Microsoft Excel", "powerpoint": "Microsoft PowerPoint",
        "teams": "Microsoft Teams", "outlook": "Microsoft Outlook",
        "screen sharing": "Screen Sharing", "disk utility": "Disk Utility", "keychain": "Keychain Access",
        "font book": "Font Book", "quicktime": "QuickTime Player", "quick time": "QuickTime Player",
        "text edit": "TextEdit", "textedit": "TextEdit", "stickies": "Stickies", "maps": "Maps",
        "weather": "Weather", "stocks": "Stocks", "clock": "Clock", "home": "Home", "books": "Books",
        "podcasts": "Podcasts", "tv": "TV", "apple tv": "TV", "news": "News", "freeform": "Freeform",
        "shortcuts": "Shortcuts", "automator": "Automator", "contacts": "Contacts",
        "vlc": "VLC", "imovie": "iMovie", "i movie": "iMovie", "garage band": "GarageBand", "garageband": "GarageBand",
        "postman": "Postman", "docker": "Docker", "1password": "1Password", "one password": "1Password",
    ]

    private static let searchRoots: [String] = [
        "/Applications",
        "/Applications/Utilities",
        "/System/Applications",
        "/System/Applications/Utilities",
        "/System/Library/CoreServices/Applications",
        NSHomeDirectory() + "/Applications",
        NSHomeDirectory() + "/Applications/Chrome Apps.localized",
    ]

    public init() {}

    /// Blocks only the first time; after that returns the cached list and refreshes in the background.
    public func refreshIfNeeded() {
        lock.lock()
        let stale = Date().timeIntervalSince(lastScan) > staleAfter
        let empty = entries.isEmpty
        lock.unlock()
        guard stale else { return }
        if empty {
            scan()
        } else {
            queue.async { [weak self] in self?.scan() }
        }
    }

    public func scan() {
        var found: [String: AppEntry] = [:]
        let fm = FileManager.default
        for root in Self.searchRoots {
            guard let items = try? fm.contentsOfDirectory(atPath: root) else { continue }
            for item in items where item.hasSuffix(".app") {
                let url = URL(fileURLWithPath: root).appendingPathComponent(item)
                let entry = Self.entry(for: url)
                found[entry.name.lowercased()] = entry
            }
        }
        // Apps launched from anywhere else (DMGs, ~/Downloads, dev builds) still count while they run.
        for app in NSWorkspace.shared.runningApplications where app.activationPolicy == .regular {
            guard let url = app.bundleURL, let name = app.localizedName, found[name.lowercased()] == nil else { continue }
            found[name.lowercased()] = AppEntry(name: name, url: url, bundleID: app.bundleIdentifier)
        }
        lock.lock()
        entries = found.values.sorted { $0.name < $1.name }
        lastScan = Date()
        lock.unlock()
    }

    private static func entry(for url: URL) -> AppEntry {
        let bundle = Bundle(url: url)
        let info = bundle?.infoDictionary ?? [:]
        let name = (info["CFBundleDisplayName"] as? String)
            ?? (info["CFBundleName"] as? String)
            ?? url.deletingPathExtension().lastPathComponent
        return AppEntry(name: name, url: url, bundleID: bundle?.bundleIdentifier)
    }

    /// The best app for a spoken name, with how sure the match is (0...1).
    public func match(_ spoken: String) -> (AppEntry, Double)? {
        lock.lock()
        let list = entries
        lock.unlock()
        let query = spoken.lowercased().trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return nil }

        var best: (AppEntry, Double)?
        func consider(_ entry: AppEntry, _ score: Double) {
            if score > (best?.1 ?? 0) { best = (entry, score) }
        }

        // A nickname wins outright when the app it names is installed.
        if let real = Self.aliases[query], let entry = list.first(where: { $0.name.lowercased() == real.lowercased() }) {
            return (entry, 1)
        }
        // A nickname the user nearly said ("chrom" for chrome).
        for (alias, real) in Self.aliases {
            let s = Fuzzy.score(query, alias)
            guard s >= 0.85, let entry = list.first(where: { $0.name.lowercased() == real.lowercased() }) else { continue }
            consider(entry, s - 0.01)
        }
        for entry in list {
            consider(entry, Fuzzy.score(query, entry.name))
            // "the finder", "finder app"
            let stripped = query.replacingOccurrences(of: " app", with: "").replacingOccurrences(of: "the ", with: "")
            if stripped != query { consider(entry, Fuzzy.score(stripped, entry.name) - 0.02) }
        }
        return best
    }

    /// Replaces the scanned list, so tests do not depend on the apps installed on this Mac.
    public func setEntriesForTesting(_ list: [AppEntry]) {
        lock.lock()
        entries = list
        lastScan = .distantFuture
        lock.unlock()
    }

    /// Names for the LLM prompt, so it never invents an app that is not installed.
    public var names: [String] {
        lock.lock(); defer { lock.unlock() }
        return entries.map(\.name)
    }

    /// Apps that are running and visible in the Dock, for "switch to" style commands.
    public static func running(named name: String) -> NSRunningApplication? {
        NSWorkspace.shared.runningApplications.first {
            $0.activationPolicy == .regular && $0.localizedName?.lowercased() == name.lowercased()
        }
    }
}
