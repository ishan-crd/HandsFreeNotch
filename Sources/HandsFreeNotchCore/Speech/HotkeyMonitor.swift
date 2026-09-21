//
//  HotkeyMonitor.swift
//  HandsFreeNotch
//
//  Copyright © 2026 Ishan Gupta. MIT License.
//

import AppKit
import Foundation

/// Push-to-talk keys. Modifier keys are used because they never type anything into the app
/// underneath, and holding one is a natural "I am talking to you" gesture.
public enum Hotkey: String, CaseIterable, Identifiable {
    case rightOption, rightCommand, rightControl, fn, leftControl

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .rightOption: return "Right ⌥ Option"
        case .rightCommand: return "Right ⌘ Command"
        case .rightControl: return "Right ⌃ Control"
        case .fn: return "fn / Globe"
        case .leftControl: return "Left ⌃ Control"
        }
    }

    var keyCode: UInt16 {
        switch self {
        case .rightOption: return 61
        case .rightCommand: return 54
        case .rightControl: return 62
        case .fn: return 63
        case .leftControl: return 59
        }
    }

    var flag: NSEvent.ModifierFlags {
        switch self {
        case .rightOption: return .option
        case .rightCommand: return .command
        case .rightControl, .leftControl: return .control
        case .fn: return .function
        }
    }
}

/// Watches one modifier key system-wide and reports press and release. Global key monitoring
/// needs the Accessibility permission the actions need anyway.
public final class HotkeyMonitor {
    public var hotkey: Hotkey {
        didSet { held = false }
    }
    public var onPress: (() -> Void)?
    public var onRelease: (() -> Void)?

    private var global: Any?
    private var local: Any?
    private var held = false

    public init(hotkey: Hotkey) {
        self.hotkey = hotkey
    }

    public func start() {
        stop()
        global = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.handle(event)
        }
        local = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.handle(event)
            return event
        }
    }

    public func stop() {
        if let global { NSEvent.removeMonitor(global) }
        if let local { NSEvent.removeMonitor(local) }
        global = nil
        local = nil
    }

    private func handle(_ event: NSEvent) {
        guard event.keyCode == hotkey.keyCode else { return }
        let down = event.modifierFlags.contains(hotkey.flag)
        if down, !held {
            held = true
            onPress?()
        } else if !down, held {
            held = false
            onRelease?()
        }
    }
}
