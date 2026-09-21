//
//  ActionRunner.swift
//  HandsFreeNotch
//
//  Copyright © 2026 Ishan Gupta. MIT License.
//

import AppKit
import Foundation

public enum ActionError: LocalizedError {
    case needsAccessibility
    case noClipboardLink
    case notRunning(String)
    case notAvailable(String)

    public var errorDescription: String? {
        switch self {
        case .needsAccessibility: return "Allow HandsFreeNotch in System Settings › Privacy & Security › Accessibility"
        case .noClipboardLink: return "No link on the clipboard"
        case let .notRunning(app): return "\(app) is not running"
        case let .notAvailable(what): return what
        }
    }
}

/// Carries out an intent on this Mac. Every case is a direct system call, never a model.
public enum ActionRunner {
    /// Which browser to send searches and sites to; nil means the system default.
    public static var browser: AppEntry?

    public static func run(_ intent: Intent) throws {
        switch intent {
        case let .openApp(app):
            open(app)
        case let .openURL(url):
            open(url)
        case .openClipboardLink:
            guard let url = SystemControl.clipboardURL() else { throw ActionError.noClipboardLink }
            open(url)
        case let .search(query, engine):
            if engine == .spotlight {
                try requireAccessibility()
                Keys.press(KeyChord(.space, command: true))
                usleep(120_000)
                Keys.type(query)
                return
            }
            guard let url = engine.url(for: query) else { return }
            open(url)
        case let .typeText(text):
            try requireAccessibility()
            Keys.type(text)
        case let .pressKey(chord):
            try requireAccessibility()
            Keys.press(chord)
        case let .shortcut(shortcut):
            try requireAccessibility()
            Keys.press(chord(for: shortcut))
        case let .quitApp(app):
            guard let running = runningApp(app) else { throw ActionError.notRunning(app.name) }
            running.terminate()
        case let .hideApp(app):
            guard let running = runningApp(app) else { throw ActionError.notRunning(app.name) }
            running.hide()
        case let .scroll(scroll):
            try requireAccessibility()
            switch scroll {
            case let .down(lines): Keys.scroll(lines: -Int32(lines))
            case let .up(lines): Keys.scroll(lines: Int32(lines))
            case .pageDown: Keys.press(KeyChord(.pageDown))
            case .pageUp: Keys.press(KeyChord(.pageUp))
            case .top: Keys.press(KeyChord(.up, command: true))
            case .bottom: Keys.press(KeyChord(.down, command: true))
            }
        case let .volume(volume):
            switch volume {
            case let .up(steps): for _ in 0..<max(1, steps) { Keys.press(media: .soundUp) }
            case let .down(steps): for _ in 0..<max(1, steps) { Keys.press(media: .soundDown) }
            case .mute: SystemControl.setMuted(true)
            case .unmute: SystemControl.setMuted(false)
            case let .set(percent): SystemControl.setVolume(percent: percent)
            }
        case let .brightness(up):
            for _ in 0..<2 { Keys.press(media: up ? .brightnessUp : .brightnessDown) }
        case let .media(media):
            switch media {
            case .playPause, .play, .pause: Keys.press(media: .play)
            case .next: Keys.press(media: .next)
            case .previous: Keys.press(media: .previous)
            }
        case let .system(command):
            try run(system: command)
        case .help, .cancel:
            break
        case .agent:
            // The pipeline owns the agent; it never reaches here.
            break
        }
    }

    private static func requireAccessibility() throws {
        guard Keys.accessibilityTrusted else {
            Keys.requestAccessibility()
            throw ActionError.needsAccessibility
        }
    }

    private static func runningApp(_ app: AppEntry) -> NSRunningApplication? {
        if let id = app.bundleID, let r = NSRunningApplication.runningApplications(withBundleIdentifier: id).first { return r }
        return AppIndex.running(named: app.name)
    }

    static func open(_ app: AppEntry) {
        // Activating a running app is instant; launching goes through LaunchServices.
        if let running = runningApp(app) {
            running.activate()
            if running.isHidden { running.unhide() }
            return
        }
        let config = NSWorkspace.OpenConfiguration()
        config.activates = true
        NSWorkspace.shared.openApplication(at: app.url, configuration: config)
    }

    static func open(_ url: URL) {
        if let browser {
            NSWorkspace.shared.open([url], withApplicationAt: browser.url, configuration: NSWorkspace.OpenConfiguration())
        } else {
            NSWorkspace.shared.open(url)
        }
    }

    private static func run(system command: SystemCommand) throws {
        switch command {
        case .lockScreen:
            try requireAccessibility()
            Keys.press(KeyChord(.q, command: true, control: true))
        case .sleep:
            SystemControl.sleep()
        case .screenshot:
            try requireAccessibility()
            Keys.press(KeyChord(.three, command: true, shift: true))
        case .screenshotArea:
            try requireAccessibility()
            Keys.press(KeyChord(.four, command: true, shift: true))
        case .showDesktop:
            try requireAccessibility()
            Keys.press(KeyChord(.f11))
        case .missionControl:
            try requireAccessibility()
            Keys.press(KeyChord(.up, control: true))
        case .spotlight:
            try requireAccessibility()
            Keys.press(KeyChord(.space, command: true))
        case .emptyTrash:
            SystemControl.emptyTrash()
        case .doNotDisturb:
            // The Focus toggle has no public API; the Shortcuts app exposes it as a URL scheme when a
            // shortcut named "Toggle Focus" exists, and the Control Center fallback needs a click.
            if let url = URL(string: "shortcuts://run-shortcut?name=Toggle%20Focus") { NSWorkspace.shared.open(url) }
        }
    }

    static func chord(for shortcut: Shortcut) -> KeyChord {
        switch shortcut {
        case .copy: return KeyChord(.c, command: true)
        case .paste: return KeyChord(.v, command: true)
        case .cut: return KeyChord(.x, command: true)
        case .selectAll: return KeyChord(.a, command: true)
        case .undo: return KeyChord(.z, command: true)
        case .redo: return KeyChord(.z, command: true, shift: true)
        case .save: return KeyChord(.s, command: true)
        case .find: return KeyChord(.f, command: true)
        case .newTab: return KeyChord(.t, command: true)
        case .closeTab: return KeyChord(.w, command: true)
        case .reopenTab: return KeyChord(.t, command: true, shift: true)
        case .nextTab: return KeyChord(.rightBracket, command: true, shift: true)
        case .previousTab: return KeyChord(.leftBracket, command: true, shift: true)
        case .back: return KeyChord(.leftBracket, command: true)
        case .forward: return KeyChord(.rightBracket, command: true)
        case .reload: return KeyChord(.r, command: true)
        case .zoomIn: return KeyChord(.equal, command: true)
        case .zoomOut: return KeyChord(.minus, command: true)
        case .zoomReset: return KeyChord(.zero, command: true)
        case .fullScreen: return KeyChord(.f, command: true, control: true)
        case .newWindow: return KeyChord(.n, command: true)
        case .closeWindow: return KeyChord(.w, command: true, shift: true)
        case .minimize: return KeyChord(.m, command: true)
        case .addressBar: return KeyChord(.l, command: true)
        }
    }
}
