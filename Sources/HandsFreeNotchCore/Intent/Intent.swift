//
//  Intent.swift
//  HandsFreeNotch
//
//  Copyright © 2026 Ishan Gupta. MIT License.
//

import Foundation

/// One thing the user asked the Mac to do. Every tier of the router produces one of these,
/// and `ActionRunner` is the only place that knows how to carry them out.
public enum Intent: Equatable {
    case openApp(AppEntry)
    case openURL(URL)
    case openClipboardLink
    case search(query: String, engine: SearchEngine)
    case typeText(String)
    case pressKey(KeyChord)
    case shortcut(Shortcut)
    case quitApp(AppEntry)
    case hideApp(AppEntry)
    case scroll(Scroll)
    case volume(Volume)
    case brightness(up: Bool)
    case media(Media)
    case system(SystemCommand)
    case help
    case cancel
    /// A goal that needs the full screen-reading agent (tier 2).
    case agent(goal: String)

    /// A short label for the notch: "Open Spotify", "Search YouTube".
    public var title: String {
        switch self {
        case let .openApp(app): return "Open \(app.name)"
        case let .openURL(url): return "Open \(url.host ?? url.absoluteString)"
        case .openClipboardLink: return "Open copied link"
        case let .search(query, engine): return "\(engine.title) “\(query)”"
        case let .typeText(text): return "Type “\(text.prefix(28))\(text.count > 28 ? "…" : "")”"
        case let .pressKey(chord): return "Press \(chord.title)"
        case let .shortcut(shortcut): return shortcut.title
        case let .quitApp(app): return "Quit \(app.name)"
        case let .hideApp(app): return "Hide \(app.name)"
        case let .scroll(scroll): return scroll.title
        case let .volume(volume): return volume.title
        case let .brightness(up): return up ? "Brightness up" : "Brightness down"
        case let .media(media): return media.title
        case let .system(command): return command.title
        case .help: return "Help"
        case .cancel: return "Cancelled"
        case let .agent(goal): return "Agent: \(goal.prefix(40))"
        }
    }

    /// Safe to run the moment the transcript stabilises, before the user releases the key.
    /// Anything that consumes the rest of the sentence (search, type) waits for the final result.
    public var firesEarly: Bool {
        switch self {
        case .openApp, .openURL, .openClipboardLink, .shortcut, .scroll, .volume, .brightness, .media, .pressKey:
            return true
        case .agent:
            return false  // the goal is the whole sentence; wait for all of it
        default:
            return false
        }
    }
}

public enum SearchEngine: String, CaseIterable, Equatable {
    case google, youtube, wikipedia, github, amazon, maps, appStore, spotlight

    public var title: String {
        switch self {
        case .google: return "Google"
        case .youtube: return "YouTube"
        case .wikipedia: return "Wikipedia"
        case .github: return "GitHub"
        case .amazon: return "Amazon"
        case .maps: return "Maps"
        case .appStore: return "App Store"
        case .spotlight: return "Spotlight"
        }
    }

    public func url(for query: String) -> URL? {
        let q = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
        switch self {
        case .google: return URL(string: "https://www.google.com/search?q=\(q)")
        case .youtube: return URL(string: "https://www.youtube.com/results?search_query=\(q)")
        case .wikipedia: return URL(string: "https://en.wikipedia.org/w/index.php?search=\(q)")
        case .github: return URL(string: "https://github.com/search?q=\(q)")
        case .amazon: return URL(string: "https://www.amazon.com/s?k=\(q)")
        case .maps: return URL(string: "https://maps.apple.com/?q=\(q)")
        case .appStore: return URL(string: "macappstore://search.itunes.apple.com/WebObjects/MZSearch.woa/wa/search?q=\(q)")
        case .spotlight: return nil
        }
    }
}

public enum Scroll: Equatable {
    case down(lines: Int)
    case up(lines: Int)
    case pageDown, pageUp, top, bottom

    public var title: String {
        switch self {
        case .down: return "Scroll down"
        case .up: return "Scroll up"
        case .pageDown: return "Page down"
        case .pageUp: return "Page up"
        case .top: return "Scroll to top"
        case .bottom: return "Scroll to bottom"
        }
    }
}

public enum Volume: Equatable {
    case up(steps: Int), down(steps: Int), mute, unmute, set(percent: Int)

    public var title: String {
        switch self {
        case .up: return "Volume up"
        case .down: return "Volume down"
        case .mute: return "Mute"
        case .unmute: return "Unmute"
        case let .set(p): return "Volume \(p)%"
        }
    }
}

public enum Media: String, Equatable {
    case playPause, play, pause, next, previous

    public var title: String {
        switch self {
        case .playPause: return "Play / Pause"
        case .play: return "Play"
        case .pause: return "Pause"
        case .next: return "Next track"
        case .previous: return "Previous track"
        }
    }
}

public enum SystemCommand: String, Equatable, CaseIterable {
    case lockScreen, sleep, screenshot, screenshotArea, showDesktop, missionControl, spotlight, emptyTrash, doNotDisturb

    public var title: String {
        switch self {
        case .lockScreen: return "Lock screen"
        case .sleep: return "Sleep"
        case .screenshot: return "Screenshot"
        case .screenshotArea: return "Screenshot (select area)"
        case .showDesktop: return "Show desktop"
        case .missionControl: return "Mission Control"
        case .spotlight: return "Spotlight"
        case .emptyTrash: return "Empty Trash"
        case .doNotDisturb: return "Toggle Do Not Disturb"
        }
    }
}

/// App-level shortcuts the frontmost app understands. Each maps to a key chord in `Keys`.
public enum Shortcut: String, Equatable, CaseIterable {
    case copy, paste, cut, selectAll, undo, redo, save, find, newTab, closeTab, reopenTab, nextTab, previousTab
    case back, forward, reload, zoomIn, zoomOut, zoomReset, fullScreen, newWindow, closeWindow, minimize, addressBar

    public var title: String {
        switch self {
        case .copy: return "Copy"
        case .paste: return "Paste"
        case .cut: return "Cut"
        case .selectAll: return "Select all"
        case .undo: return "Undo"
        case .redo: return "Redo"
        case .save: return "Save"
        case .find: return "Find"
        case .newTab: return "New tab"
        case .closeTab: return "Close tab"
        case .reopenTab: return "Reopen closed tab"
        case .nextTab: return "Next tab"
        case .previousTab: return "Previous tab"
        case .back: return "Back"
        case .forward: return "Forward"
        case .reload: return "Reload"
        case .zoomIn: return "Zoom in"
        case .zoomOut: return "Zoom out"
        case .zoomReset: return "Reset zoom"
        case .fullScreen: return "Toggle full screen"
        case .newWindow: return "New window"
        case .closeWindow: return "Close window"
        case .minimize: return "Minimize"
        case .addressBar: return "Address bar"
        }
    }
}

/// A key press with modifiers, e.g. ⌘⇧T.
public struct KeyChord: Equatable {
    public var key: Key
    public var command = false
    public var shift = false
    public var option = false
    public var control = false

    public init(_ key: Key, command: Bool = false, shift: Bool = false, option: Bool = false, control: Bool = false) {
        self.key = key
        self.command = command
        self.shift = shift
        self.option = option
        self.control = control
    }

    public var title: String {
        var s = ""
        if control { s += "⌃" }
        if option { s += "⌥" }
        if shift { s += "⇧" }
        if command { s += "⌘" }
        return s + key.title
    }
}

/// Virtual key codes (ANSI layout), the same ones `CGEvent` takes.
public enum Key: UInt16, Equatable, CaseIterable {
    case a = 0, s = 1, d = 2, f = 3, h = 4, g = 5, z = 6, x = 7, c = 8, v = 9, b = 11, q = 12, w = 13, e = 14
    case r = 15, y = 16, t = 17, one = 18, two = 19, three = 20, four = 21, six = 22, five = 23, equal = 24
    case nine = 25, seven = 26, minus = 27, eight = 28, zero = 29, rightBracket = 30, o = 31, u = 32
    case leftBracket = 33, i = 34, p = 35, l = 37, j = 38, quote = 39, k = 40, semicolon = 41, backslash = 42
    case comma = 43, slash = 44, n = 45, m = 46, period = 47, grave = 50
    case `return` = 36, tab = 48, space = 49, delete = 51, escape = 53
    case forwardDelete = 117, home = 115, end = 119, pageUp = 116, pageDown = 121
    case f11 = 103, f3 = 99
    case left = 123, right = 124, down = 125, up = 126

    public var title: String {
        switch self {
        case .return: return "Return"
        case .tab: return "Tab"
        case .space: return "Space"
        case .delete: return "Delete"
        case .escape: return "Escape"
        case .forwardDelete: return "Forward Delete"
        case .home: return "Home"
        case .end: return "End"
        case .pageUp: return "Page Up"
        case .pageDown: return "Page Down"
        case .left: return "←"
        case .right: return "→"
        case .up: return "↑"
        case .down: return "↓"
        case .f11: return "F11"
        case .f3: return "F3"
        default: return String(describing: self).uppercased()
        }
    }
}
