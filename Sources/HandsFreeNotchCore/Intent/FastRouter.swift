//
//  FastRouter.swift
//  HandsFreeNotch
//
//  Copyright © 2026 Ishan Gupta. MIT License.
//

import Foundation

/// A routed command: what to do, how sure we are, and which tier decided.
public struct Routed: Equatable {
    public enum Tier: String { case fast, llm, agent }
    public let intent: Intent
    public let confidence: Double
    public let tier: Tier

    public init(_ intent: Intent, confidence: Double, tier: Tier) {
        self.intent = intent
        self.confidence = confidence
        self.tier = tier
    }
}

/// Tier 0: no model at all. Pattern matching over the normalized transcript, in well under a
/// millisecond. Handles the commands people say all day, so those never wait on a network.
public final class FastRouter {
    public let apps: AppIndex
    /// Below this the app match is not trusted and the command falls through to the next tier.
    public var appThreshold = 0.72

    public init(apps: AppIndex) {
        self.apps = apps
    }

    public func route(_ raw: String) -> Routed? {
        let text = Normalizer.normalize(raw)
        guard !text.isEmpty else { return nil }
        let words = text.split(separator: " ").map(String.init)

        if let r = exact(text) { return r }
        if let r = open(text, words) { return r }
        if let r = search(text) { return r }
        if let r = typing(text) { return r }
        if let r = press(text, words) { return r }
        if let r = quitOrHide(text) { return r }
        if let r = scroll(text, words) { return r }
        if let r = volume(text, words) { return r }
        if let r = media(text) { return r }
        if let r = switchTo(text) { return r }
        return nil
    }

    // MARK: - Whole-utterance commands

    private static let exact: [String: Intent] = {
        var m: [String: Intent] = [:]
        func add(_ intent: Intent, _ phrases: String...) { for p in phrases { m[p] = intent } }
        add(.cancel, "cancel", "never mind", "nevermind", "stop", "forget it", "no", "nothing")
        add(.help, "help", "what can you do", "what can i say", "commands", "show commands")
        add(.shortcut(.copy), "copy", "copy that", "copy this", "copy it")
        add(.shortcut(.paste), "paste", "paste it", "paste that", "paste here")
        add(.shortcut(.cut), "cut", "cut that", "cut it")
        add(.shortcut(.selectAll), "select all", "select everything")
        add(.shortcut(.undo), "undo", "undo that")
        add(.shortcut(.redo), "redo", "redo that")
        add(.shortcut(.save), "save", "save it", "save this", "save file", "save the file")
        add(.shortcut(.find), "find", "find on page", "search on page", "search this page", "search the page", "find in page")
        add(.shortcut(.newTab), "new tab", "open a new tab", "open new tab", "create new tab", "another tab")
        add(.shortcut(.closeTab), "close tab", "close this tab", "close the tab", "close current tab")
        add(.shortcut(.reopenTab), "reopen tab", "reopen closed tab", "reopen last tab", "restore tab", "undo close tab")
        add(.shortcut(.nextTab), "next tab", "switch tab", "go to next tab")
        add(.shortcut(.previousTab), "previous tab", "last tab", "go to previous tab")
        add(.shortcut(.back), "go back", "back", "navigate back", "previous page")
        add(.shortcut(.forward), "go forward", "forward", "navigate forward", "next page")
        add(.shortcut(.reload), "reload", "refresh", "reload page", "refresh page", "reload the page", "refresh the page", "reload this page")
        add(.shortcut(.zoomIn), "zoom in", "bigger", "make it bigger", "increase font size")
        add(.shortcut(.zoomOut), "zoom out", "smaller", "make it smaller", "decrease font size")
        add(.shortcut(.zoomReset), "reset zoom", "actual size", "normal size")
        add(.shortcut(.fullScreen), "full screen", "fullscreen", "enter full screen", "exit full screen", "toggle full screen", "maximize", "maximise")
        add(.shortcut(.newWindow), "new window", "open a new window", "open new window")
        add(.shortcut(.closeWindow), "close window", "close this window", "close the window")
        add(.shortcut(.minimize), "minimize", "minimise", "minimize window", "minimize this", "hide window")
        add(.shortcut(.addressBar), "address bar", "url bar", "go to address bar", "focus address bar", "search bar")
        add(.system(.lockScreen), "lock", "lock screen", "lock the screen", "lock my screen", "lock computer", "lock the computer", "lock my mac", "lock mac")
        add(.system(.sleep), "sleep", "go to sleep", "sleep now", "put the computer to sleep", "sleep the computer", "sleep mac")
        add(.system(.screenshot), "screenshot", "take a screenshot", "take screenshot", "capture screen", "capture the screen", "screen shot")
        add(.system(.screenshotArea), "screenshot area", "screenshot selection", "select screenshot", "take a screenshot of an area", "capture area", "partial screenshot")
        add(.system(.showDesktop), "show desktop", "show the desktop", "desktop", "go to desktop")
        add(.system(.missionControl), "mission control", "show all windows", "show windows", "all windows")
        add(.system(.spotlight), "spotlight", "open spotlight", "spotlight search")
        add(.system(.emptyTrash), "empty trash", "empty the trash", "empty bin", "empty the bin")
        add(.system(.doNotDisturb), "do not disturb", "focus mode", "toggle do not disturb", "turn on do not disturb", "turn off do not disturb", "silence notifications")
        add(.openClipboardLink, "open this link", "open the link", "open link", "open that link", "open copied link", "open the copied link", "open clipboard", "open clipboard link", "open link from clipboard", "open what i copied")
        add(.scroll(.top), "top", "go to top", "go to the top", "scroll to top", "scroll to the top", "jump to top")
        add(.scroll(.bottom), "bottom", "go to bottom", "go to the bottom", "scroll to bottom", "scroll to the bottom", "jump to bottom")
        add(.scroll(.pageDown), "page down", "next screen")
        add(.scroll(.pageUp), "page up", "previous screen")
        add(.pressKey(KeyChord(.return)), "enter", "return", "press enter", "hit enter", "press return", "hit return", "submit", "go", "confirm", "ok")
        add(.pressKey(KeyChord(.escape)), "escape", "press escape", "hit escape", "dismiss", "close popup", "close the popup", "close dialog")
        add(.pressKey(KeyChord(.tab)), "tab", "press tab", "next field")
        add(.pressKey(KeyChord(.tab, shift: true)), "previous field", "shift tab")
        add(.pressKey(KeyChord(.space)), "space", "press space", "spacebar")
        add(.pressKey(KeyChord(.delete)), "delete", "backspace", "press delete", "delete that", "delete last character")
        add(.pressKey(KeyChord(.delete, option: true)), "delete word", "delete last word", "delete the last word")
        add(.pressKey(KeyChord(.delete, command: true)), "delete line", "delete the line", "clear line", "clear the line", "clear field", "clear the field")
        add(.pressKey(KeyChord(.up)), "up", "arrow up", "up arrow", "press up")
        add(.pressKey(KeyChord(.down)), "down", "arrow down", "down arrow", "press down")
        add(.pressKey(KeyChord(.left)), "left", "arrow left", "left arrow", "press left")
        add(.pressKey(KeyChord(.right)), "right", "arrow right", "right arrow", "press right")
        add(.pressKey(KeyChord(.a, command: true)), "select all text")
        add(.pressKey(KeyChord(.tab, command: true)), "switch app", "next app", "switch application", "next application")
        add(.pressKey(KeyChord(.grave, command: true)), "next window", "switch window", "other window")
        add(.pressKey(KeyChord(.q, command: true)), "quit", "quit this", "quit app", "quit this app", "quit the app", "close app", "close this app", "close the app")
        add(.pressKey(KeyChord(.h, command: true)), "hide", "hide this", "hide app", "hide this app")
        add(.pressKey(KeyChord(.w, command: true)), "close", "close this", "close it")
        add(.pressKey(KeyChord(.n, command: true)), "new", "new file", "new document")
        add(.pressKey(KeyChord(.t, command: true)), "open tab")
        add(.pressKey(KeyChord(.l, command: true)), "go to url", "type url", "type a url", "enter url")
        add(.pressKey(KeyChord(.d, command: true)), "bookmark", "bookmark this", "bookmark this page", "add bookmark")
        add(.pressKey(KeyChord(.p, command: true)), "print", "print this", "print page")
        add(.pressKey(KeyChord(.r, command: true, shift: true)), "hard refresh", "hard reload")
        add(.pressKey(KeyChord(.f, command: true, control: true)), "toggle fullscreen")
        add(.pressKey(KeyChord(.space, command: true, shift: true)), "emoji", "emoji picker", "emojis", "insert emoji")
        add(.pressKey(KeyChord(.four, command: true, shift: true)), "screenshot part of screen")
        add(.pressKey(KeyChord(.five, command: true, shift: true)), "screen recording", "record screen", "record the screen", "start screen recording")
        add(.pressKey(KeyChord(.v, command: true, shift: true, option: true)), "paste plain text", "paste without formatting", "paste as plain text")
        add(.pressKey(KeyChord(.z, command: true, shift: true)), "redo last")
        add(.pressKey(KeyChord(.f3)), "app windows", "show app windows")
        add(.media(.playPause), "play pause", "play or pause", "toggle play", "toggle playback", "pause play", "play music", "start music", "resume", "resume music", "resume playback")
        add(.media(.play), "play", "play song", "play the song", "play it", "play the music", "continue playing", "unpause")
        add(.media(.pause), "pause", "pause music", "pause the music", "pause it", "pause song", "pause the song", "pause playback", "stop music", "stop the music", "stop playing", "stop playback", "stop song", "stop the song")
        add(.media(.next), "next", "next song", "next track", "skip", "skip song", "skip track", "skip this", "skip this song", "skip it", "play next", "play the next song", "next music", "skip to next")
        add(.media(.previous), "previous", "previous song", "previous track", "last song", "last track", "go back a song", "play previous", "play the previous song", "back one song", "rewind")
        add(.volume(.mute), "mute", "mute it", "mute volume", "mute the volume", "mute sound", "mute the sound", "silence", "shut up", "quiet", "be quiet", "turn off sound", "turn off the sound", "sound off")
        add(.volume(.unmute), "unmute", "unmute it", "unmute volume", "unmute the volume", "unmute sound", "turn on sound", "turn on the sound", "sound on")
        add(.volume(.set(percent: 100)), "max volume", "maximum volume", "full volume", "volume max", "volume to max", "volume to maximum", "volume all the way up", "turn it all the way up")
        add(.volume(.set(percent: 0)), "volume zero", "volume to zero", "volume off", "no volume", "turn it all the way down")
        add(.volume(.set(percent: 50)), "half volume", "volume half", "medium volume", "volume medium")
        add(.volume(.up(steps: 3)), "volume up", "turn up the volume", "turn the volume up", "turn it up", "louder", "make it louder", "increase volume", "increase the volume", "raise volume", "raise the volume", "more volume", "up the volume", "sound up", "turn volume up", "volume higher")
        add(.volume(.down(steps: 3)), "volume down", "turn down the volume", "turn the volume down", "turn it down", "quieter", "make it quieter", "decrease volume", "decrease the volume", "lower volume", "lower the volume", "less volume", "softer", "sound down", "turn volume down", "volume lower")
        add(.brightness(up: true), "brightness up", "brighter", "increase brightness", "turn up brightness", "turn brightness up", "more brightness", "make it brighter", "screen brighter", "raise brightness")
        add(.brightness(up: false), "brightness down", "dimmer", "darker", "decrease brightness", "turn down brightness", "turn brightness down", "less brightness", "make it darker", "make it dimmer", "screen darker", "lower brightness", "dim the screen", "dim screen")
        return m
    }()

    private func exact(_ text: String) -> Routed? {
        if let intent = Self.exact[text] { return Routed(intent, confidence: 1, tier: .fast) }
        // "please" and "now" survive in the middle: "mute now", "copy now".
        let trimmed = text.replacingOccurrences(of: " now", with: "").replacingOccurrences(of: " right now", with: "")
        if trimmed != text, let intent = Self.exact[trimmed] { return Routed(intent, confidence: 0.98, tier: .fast) }
        return nil
    }

    // MARK: - open / launch / go to

    private static let openVerbs = ["open up", "open", "launch", "start", "run", "go to", "goto", "take me to", "bring up", "pull up", "show me", "show", "visit", "navigate to", "load", "fire up", "boot up"]

    private func open(_ text: String, _ words: [String]) -> Routed? {
        guard let (verb, rest) = strip(verbs: Self.openVerbs, from: text) else { return nil }
        guard !rest.isEmpty else { return nil }
        var target = rest
        var forceBrowser = false
        var forceApp = false
        // "open youtube in chrome" / "open github in the browser" / "open spotify app"
        for suffix in [" in the browser", " in browser", " in a browser", " in a new tab", " in new tab", " in safari", " in chrome", " on the web", " website", " site", " web"] where target.hasSuffix(suffix) {
            target = String(target.dropLast(suffix.count))
            forceBrowser = true
        }
        for suffix in [" app", " application", " the app"] where target.hasSuffix(suffix) {
            target = String(target.dropLast(suffix.count))
            forceApp = true
        }
        for prefix in ["the ", "my ", "up "] where target.hasPrefix(prefix) { target = String(target.dropFirst(prefix.count)) }
        guard !target.isEmpty else { return nil }

        if target == "link" || target == "this link" || target == "the link" || target == "clipboard" {
            return Routed(.openClipboardLink, confidence: 1, tier: .fast)
        }

        let app = forceBrowser ? nil : apps.match(target)
        let site = forceApp ? nil : SiteIndex.url(for: target)
        let looksLikeDomain = target.contains(".") || target.contains(" dot ")

        if let site, looksLikeDomain || verb == "go to" || verb == "visit" || verb == "navigate to" || forceBrowser {
            // A web-looking name goes to the web unless an app owns that exact name.
            if let app, app.1 >= 0.97, !forceBrowser, !looksLikeDomain { return Routed(.openApp(app.0), confidence: app.1, tier: .fast) }
            return Routed(.openURL(site), confidence: 1, tier: .fast)
        }
        if let app, app.1 >= appThreshold {
            return Routed(.openApp(app.0), confidence: app.1, tier: .fast)
        }
        if let site {
            return Routed(.openURL(site), confidence: 0.95, tier: .fast)
        }
        // "open settings" when System Settings scored low, and nothing else: let the LLM decide.
        return nil
    }

    private func switchTo(_ text: String) -> Routed? {
        guard let (_, rest) = strip(verbs: ["switch to", "go back to", "focus", "focus on", "activate", "jump to", "bring me to"], from: text),
              let app = apps.match(rest), app.1 >= appThreshold else { return nil }
        return Routed(.openApp(app.0), confidence: app.1, tier: .fast)
    }

    // MARK: - search

    private func search(_ text: String) -> Routed? {
        // "search youtube for cats", "youtube cats", "google how tall is everest", "look up X on wikipedia"
        let engineNames: [(String, SearchEngine)] = [
            ("youtube", .youtube), ("you tube", .youtube), ("wikipedia", .wikipedia), ("github", .github),
            ("git hub", .github), ("amazon", .amazon), ("maps", .maps), ("google maps", .maps),
            ("app store", .appStore), ("google", .google),
        ]
        // "find" is left out on purpose: "find me a flight" is a job for the model, not a web search.
        let verbs = ["search for", "search up", "search", "look up", "lookup", "look for", "google for", "google", "what is", "what's", "who is", "who's", "how to", "how do i", "how do you", "where is"]

        var engine: SearchEngine = .google
        var query = text

        // "on youtube search cats", "in google look up cats"
        for prefix in ["on ", "in ", "using "] where query.hasPrefix(prefix) {
            for (name, _) in engineNames where query.hasPrefix(prefix + name + " ") { query = String(query.dropFirst(prefix.count)) }
        }
        // Leading engine: "youtube cats", "youtube search cats"; a bare "youtube" is the site.
        for (name, e) in engineNames where query.hasPrefix(name + " ") || query == name {
            engine = e
            query = query == name ? "" : String(query.dropFirst(name.count + 1))
            for v in ["search for ", "search ", "look up ", "for "] where query.hasPrefix(v) { query = String(query.dropFirst(v.count)) }
            if query.isEmpty { return home(of: engine) }
            return Routed(.search(query: query, engine: engine), confidence: 0.95, tier: .fast)
        }
        guard let (verb, rest) = strip(verbs: verbs, from: query) else { return nil }
        query = rest
        // "search youtube" opens the site; "search youtube for cats" and "search on youtube cats" search it.
        for (name, e) in engineNames {
            if query == name || query == "on " + name || query == "in " + name { return home(of: e) }
            for form in [name + " for ", "on " + name + " for ", "on " + name + " ", "in " + name + " "] where query.hasPrefix(form) {
                engine = e
                query = String(query.dropFirst(form.count))
            }
        }
        // "cats on youtube", "everest in wikipedia"
        for (name, e) in engineNames {
            for joiner in [" on ", " in ", " using ", " with "] where query.hasSuffix(joiner + name) {
                engine = e
                query = String(query.dropLast(joiner.count + name.count))
            }
        }
        if verb == "what is" || verb == "what's" || verb == "who is" || verb == "who's" || verb == "how to" || verb == "how do i" || verb == "how do you" || verb == "where is" {
            query = verb + " " + query
        }
        query = query.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return nil }
        return Routed(.search(query: query, engine: engine), confidence: 0.9, tier: .fast)
    }

    private func home(of engine: SearchEngine) -> Routed? {
        guard let url = engine.url(for: "").flatMap({ URL(string: "https://" + ($0.host ?? "")) }) else { return nil }
        // Below the early-fire bar on purpose: "search youtube" may still become "search youtube for cats".
        return Routed(.openURL(url), confidence: 0.9, tier: .fast)
    }

    // MARK: - type / press

    private func typing(_ text: String) -> Routed? {
        guard let (_, rest) = strip(verbs: ["type out", "type in", "type", "write", "dictate", "enter text", "input", "insert"], from: text), !rest.isEmpty else { return nil }
        // Keep the user's original casing for what they dictated.
        return Routed(.typeText(rest), confidence: 0.9, tier: .fast)
    }

    private func press(_ text: String, _ words: [String]) -> Routed? {
        guard let (_, rest) = strip(verbs: ["press", "hit", "push", "key"], from: text), !rest.isEmpty else { return nil }
        var chord: KeyChord?
        var parts = rest.replacingOccurrences(of: " and ", with: " ").replacingOccurrences(of: " plus ", with: " ").split(separator: " ").map(String.init)
        var command = false, shift = false, option = false, control = false
        parts.removeAll { p in
            switch p {
            case "command", "cmd", "⌘": command = true; return true
            case "shift", "⇧": shift = true; return true
            case "option", "alt", "opt", "⌥": option = true; return true
            case "control", "ctrl", "⌃": control = true; return true
            default: return false
            }
        }
        if let name = parts.last, let key = Self.keyNames[name] {
            chord = KeyChord(key, command: command, shift: shift, option: option, control: control)
        } else if let name = parts.last, name.count == 1, let key = Self.keyNames[name] {
            chord = KeyChord(key, command: command, shift: shift, option: option, control: control)
        }
        guard let chord else { return nil }
        return Routed(.pressKey(chord), confidence: 0.95, tier: .fast)
    }

    static let keyNames: [String: Key] = {
        var m: [String: Key] = [
            "enter": .return, "return": .return, "tab": .tab, "space": .space, "spacebar": .space,
            "delete": .delete, "backspace": .delete, "escape": .escape, "esc": .escape,
            "up": .up, "down": .down, "left": .left, "right": .right, "home": .home, "end": .end,
            "page up": .pageUp, "page down": .pageDown, "pageup": .pageUp, "pagedown": .pageDown,
            "one": .one, "two": .two, "three": .three, "four": .four, "five": .five, "six": .six, "seven": .seven, "eight": .eight, "nine": .nine, "zero": .zero,
            "1": .one, "2": .two, "3": .three, "4": .four, "5": .five, "6": .six, "7": .seven, "8": .eight, "9": .nine, "0": .zero,
            "minus": .minus, "dash": .minus, "equals": .equal, "equal": .equal, "plus": .equal, "comma": .comma, "period": .period, "dot": .period, "slash": .slash,
        ]
        for key in Key.allCases {
            let name = String(describing: key)
            if name.count == 1 { m[name] = key }
        }
        return m
    }()

    // MARK: - quit / hide

    private func quitOrHide(_ text: String) -> Routed? {
        if let (_, rest) = strip(verbs: ["quit", "kill", "force quit", "exit", "close", "shut down", "shut"], from: text), !rest.isEmpty {
            var name = rest
            for s in [" app", " application"] where name.hasSuffix(s) { name = String(name.dropLast(s.count)) }
            for p in ["the ", "my "] where name.hasPrefix(p) { name = String(name.dropFirst(p.count)) }
            if let app = apps.match(name), app.1 >= appThreshold {
                return Routed(.quitApp(app.0), confidence: app.1, tier: .fast)
            }
        }
        if let (_, rest) = strip(verbs: ["hide", "minimize", "minimise"], from: text), !rest.isEmpty {
            if let app = apps.match(rest), app.1 >= appThreshold {
                return Routed(.hideApp(app.0), confidence: app.1, tier: .fast)
            }
        }
        return nil
    }

    // MARK: - scroll

    private func scroll(_ text: String, _ words: [String]) -> Routed? {
        guard words.first == "scroll" || words.first == "scroll" || text.hasPrefix("scroll") || text.hasSuffix("scroll down") || text.hasSuffix("scroll up") else { return nil }
        let down = text.contains("down")
        let up = text.contains("up")
        guard down || up else { return nil }
        var lines = 10
        if text.contains("a lot") || text.contains("a bunch") || text.contains("way") || text.contains("far") || text.contains("more") { lines = 40 }
        if text.contains("a bit") || text.contains("a little") || text.contains("slightly") { lines = 4 }
        if let n = Normalizer.firstNumber(in: text), n > 0 { lines = min(n * 10, 200) }
        return Routed(.scroll(down ? .down(lines: lines) : .up(lines: lines)), confidence: 0.95, tier: .fast)
    }

    // MARK: - volume

    private func volume(_ text: String, _ words: [String]) -> Routed? {
        guard text.contains("volume") || text.contains("sound") else { return nil }
        if let n = Normalizer.firstNumber(in: text), text.contains("to") || text.contains("percent") || text.contains("at") || words.count <= 3 {
            return Routed(.volume(.set(percent: max(0, min(100, n)))), confidence: 0.95, tier: .fast)
        }
        if text.contains("up") || text.contains("louder") || text.contains("increase") || text.contains("raise") || text.contains("higher") {
            return Routed(.volume(.up(steps: 3)), confidence: 0.9, tier: .fast)
        }
        if text.contains("down") || text.contains("quieter") || text.contains("decrease") || text.contains("lower") || text.contains("softer") {
            return Routed(.volume(.down(steps: 3)), confidence: 0.9, tier: .fast)
        }
        if text.contains("mute") { return Routed(.volume(text.contains("unmute") ? .unmute : .mute), confidence: 0.9, tier: .fast) }
        return nil
    }

    // MARK: - media

    private func media(_ text: String) -> Routed? {
        if text.hasPrefix("pause") { return Routed(.media(.pause), confidence: 0.85, tier: .fast) }
        if text.hasPrefix("skip") || text.hasPrefix("next song") || text.hasPrefix("next track") { return Routed(.media(.next), confidence: 0.85, tier: .fast) }
        if text.hasPrefix("previous song") || text.hasPrefix("previous track") { return Routed(.media(.previous), confidence: 0.85, tier: .fast) }
        // "play something" with a subject needs the app, so it goes to the LLM.
        return nil
    }

    // MARK: - helpers

    /// The longest verb the text starts with and the words after it.
    private func strip(verbs: [String], from text: String) -> (String, String)? {
        var best: (String, String)?
        for verb in verbs where text == verb || text.hasPrefix(verb + " ") {
            if best == nil || verb.count > best!.0.count {
                best = (verb, text == verb ? "" : String(text.dropFirst(verb.count + 1)))
            }
        }
        return best
    }
}
