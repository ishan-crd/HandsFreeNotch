//
//  NotchViewModel.swift
//  HandsFreeNotch
//
//  Copyright © 2026 Ishan Gupta. MIT License.
//

import AppKit
import HandsFreeNotchCore
import Observation
import SwiftUI

/// Where the notch is, whether it is open, and what the pipeline is doing right now.
@Observable
@MainActor
final class NotchViewModel {
    enum Status { case closed, opened }
    enum Page { case commands, help, settings }

    var status: Status = .closed
    var page: Page = .commands
    var deviceNotchRect: CGRect = .zero
    var screenRect: CGRect = .zero
    var pipelineState: CommandPipeline.State = .idle
    var level: Float = 0
    var history: [(transcript: String, title: String, tier: Routed.Tier, milliseconds: Int)] = []
    var accessibilityGranted = Keys.accessibilityTrusted
    var speechGranted = false
    var onDevice = false

    let pipeline: CommandPipeline
    let settings = Settings.shared
    var onOpenChanged: ((Bool) -> Void)?

    let animation: Animation = .spring(duration: 0.38, bounce: 0.18)
    static let openedSize = CGSize(width: 560, height: 320)

    /// The physical notch hides pixels behind it, so pill content is laid out beside it and
    /// taller cards start below it.
    var hardwareNotch: CGSize {
        deviceNotchRect.size == .zero ? CGSize(width: 180, height: 32) : deviceNotchRect.size
    }

    /// The one line of text the pill shows, and its font.
    var pillText: (text: String, font: NSFont) {
        switch pipelineState {
        case .idle, .agent, .help: return ("", .systemFont(ofSize: 12))
        case let .listening(t): return (t.isEmpty ? (pipeline.continuous ? "Listening · tap to stop" : "Listening…") : t, .systemFont(ofSize: 12, weight: .medium))
        case let .thinking(t): return (t, .systemFont(ofSize: 12, weight: .medium))
        case let .done(title, _, _): return (title, .systemFont(ofSize: 12, weight: .medium))
        case let .failed(m): return (m, .systemFont(ofSize: 11, weight: .medium))
        }
    }

    /// Width of the strip left of the physical notch: icon + one line of text, sized to fit.
    var leftWidth: CGFloat {
        let (text, font) = pillText
        guard !text.isEmpty else { return 0 }
        let measured = (text as NSString).size(withAttributes: [.font: font]).width
        let chrome: CGFloat = 12 + 14 + 6 + 10 + 10  // padding, icon, gap, padding, slack for SwiftUI's text metrics
        let cap: CGFloat
        switch pipelineState {
        case .failed: cap = 420
        case .thinking: cap = 260
        default: cap = 300
        }
        return min(ceil(measured) + chrome, cap)
    }

    /// Width of the strip right of the physical notch: just the indicator.
    var rightWidth: CGFloat {
        switch pipelineState {
        case .idle, .agent, .help: return 0
        case .listening: return 40
        case .thinking: return 36
        case .done: return 60
        case .failed: return 10
        }
    }

    init(pipeline: CommandPipeline) {
        self.pipeline = pipeline
        speechGranted = pipeline.speech.authorized
        onDevice = pipeline.speech.onDevice
        pipeline.onState = { [weak self] state in
            guard let self else { return }
            self.pipelineState = state
            self.history = pipeline.history
            if case .idle = state { self.level = 0 }
        }
        pipeline.onLevel = { [weak self] level in
            guard let self, self.pipeline.isListening else { return }
            self.level = level
        }
    }

    /// The size of the black shape for the current state.
    var notchSize: CGSize {
        let base = hardwareNotch
        if status == .opened { return CGSize(width: Self.openedSize.width, height: Self.openedSize.height + base.height) }
        let h = max(base.height, 30)
        switch pipelineState {
        case .idle: return CGSize(width: base.width, height: base.height)
        case .listening, .thinking, .done, .failed: return CGSize(width: base.width + leftWidth + rightWidth, height: h)
        case .agent: return CGSize(width: 520, height: 140 + base.height)
        case .help: return CGSize(width: 560, height: 170 + base.height)
        }
    }

    var cornerRadius: CGFloat {
        if status == .opened { return 30 }
        if case .idle = pipelineState { return 8 }
        return 10
    }

    var openedRect: CGRect {
        CGRect(
            x: screenRect.origin.x + (screenRect.width - notchSize.width) / 2,
            y: screenRect.origin.y + screenRect.height - notchSize.height,
            width: notchSize.width,
            height: notchSize.height
        )
    }

    func open(_ page: Page = .commands) {
        self.page = page
        status = .opened
        refreshPermissions()
        onOpenChanged?(true)
    }

    func close() {
        status = .closed
        onOpenChanged?(false)
    }

    func toggle() {
        status == .opened ? close() : open()
    }

    func refreshPermissions() {
        accessibilityGranted = Keys.accessibilityTrusted
        speechGranted = pipeline.speech.authorized
        onDevice = pipeline.speech.onDevice
    }

    /// Click handling, from the app-wide mouse-down monitor.
    func mouseDown(at point: NSPoint) {
        switch status {
        case .opened:
            if !openedRect.contains(point) { close() }
        case .closed:
            if deviceNotchRect.insetBy(dx: -6, dy: -2).contains(point) || (pipelineState != .idle && openedRect.contains(point)) {
                open()
            }
        }
    }
}
