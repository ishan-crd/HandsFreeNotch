//
//  Keys.swift
//  HandsFreeNotch
//
//  Copyright © 2026 Ishan Gupta. MIT License.
//

import AppKit
import Carbon.HIToolbox
import Foundation

/// Synthetic keyboard, mouse and media-key events. Everything here needs Accessibility, or the
/// system silently drops the event.
public enum Keys {
    public static var accessibilityTrusted: Bool {
        AXIsProcessTrusted()
    }

    /// Ask the system to show the Accessibility prompt for this app.
    public static func requestAccessibility() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }

    public static func press(_ chord: KeyChord) {
        var flags: CGEventFlags = []
        if chord.command { flags.insert(.maskCommand) }
        if chord.shift { flags.insert(.maskShift) }
        if chord.option { flags.insert(.maskAlternate) }
        if chord.control { flags.insert(.maskControl) }
        for down in [true, false] {
            guard let event = CGEvent(keyboardEventSource: nil, virtualKey: chord.key.rawValue, keyDown: down) else { continue }
            event.flags = flags
            event.post(tap: .cghidEventTap)
        }
    }

    /// Types arbitrary text into whatever has focus, a few characters per event.
    public static func type(_ text: String) {
        let units = Array(text.utf16)
        var index = 0
        while index < units.count {
            let end = min(index + 16, units.count)
            var chunk = Array(units[index..<end])
            for down in [true, false] {
                guard let event = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: down) else { continue }
                event.keyboardSetUnicodeString(stringLength: chunk.count, unicodeString: &chunk)
                event.post(tap: .cghidEventTap)
            }
            index = end
        }
    }

    /// Scrolls under the cursor; positive is up, in lines.
    public static func scroll(lines: Int32) {
        // A single big event is jumpy in some apps; a few smaller ones read as a scroll.
        let step: Int32 = lines > 0 ? 5 : -5
        var remaining = lines
        while remaining != 0 {
            let amount = abs(remaining) >= 5 ? step : remaining
            guard let event = CGEvent(scrollWheelEvent2Source: nil, units: .line, wheelCount: 1, wheel1: amount, wheel2: 0, wheel3: 0) else { return }
            event.post(tap: .cghidEventTap)
            remaining -= amount
        }
    }

    /// The special keys on the top row (volume, brightness, play) are "system defined" events, not key codes.
    public enum MediaKey: Int32 {
        case soundUp = 0, soundDown = 1, brightnessUp = 2, brightnessDown = 3, mute = 7, play = 16, next = 17, previous = 18
    }

    public static func press(media key: MediaKey) {
        for down in [true, false] {
            let flags = NSEvent.ModifierFlags(rawValue: down ? 0xA00 : 0xB00)
            let data1 = Int(key.rawValue << 16) | Int((down ? 0xA : 0xB) << 8)
            guard let event = NSEvent.otherEvent(
                with: .systemDefined, location: .zero, modifierFlags: flags, timestamp: 0,
                windowNumber: 0, context: nil, subtype: 8, data1: data1, data2: -1
            ) else { continue }
            event.cgEvent?.post(tap: .cghidEventTap)
        }
    }
}
