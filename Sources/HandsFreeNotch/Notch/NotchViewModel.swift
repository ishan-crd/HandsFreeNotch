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

    init(pipeline: CommandPipeline) {
        self.pipeline = pipeline
        speechGranted = pipeline.speech.authorized
        onDevice = pipeline.speech.onDevice
        pipeline.onState = { [weak self] state in
            guard let self else { return }
            self.pipelineState = state
            self.history = pipeline.history
            if case .idle = state { self.level = 0 }
            let p = self.pill
            if p.left > 0 {
                pipeline.onLog?("pill: left \(Int(p.left)) | housing \(Int(self.hardwareNotch.width)) | right \(Int(p.right)) | offset \(Int(p.offset)) | “\(p.leftText)” ‖ “\(p.rightText)”")
            }
        }
        pipeline.onLevel = { [weak self] level in
            guard let self, self.pipeline.isListening else { return }
            self.level = level
        }
    }

    /// The pill's text and strips for the current state.
    var pill: PillLayout {
        switch pipelineState {
        case .idle, .agent, .help:
            return PillLayout()
        case let .listening(t):
            let text = t.isEmpty ? (pipeline.continuous ? "Listening · tap to stop" : "Listening…") : t
            return PillLayout.make(text: text, font: .systemFont(ofSize: 12, weight: .medium), keepTail: true, indicator: 24)
        case let .thinking(t):
            return PillLayout.make(text: t, font: .systemFont(ofSize: 12, weight: .medium), keepTail: false, indicator: 18)
        case let .done(title, _, ms):
            let timing = PillLayout.width(of: "\(ms) ms", .monospacedDigitSystemFont(ofSize: 10, weight: .medium))
            return PillLayout.make(text: title, font: .systemFont(ofSize: 12, weight: .medium), keepTail: false, indicator: ceil(timing) + 4)
        case let .failed(m):
            return PillLayout.make(text: m, font: .systemFont(ofSize: 11, weight: .medium), keepTail: false, indicator: 0)
        }
    }

    /// The size of the black shape for the current state.
    var notchSize: CGSize {
        let base = hardwareNotch
        if status == .opened { return CGSize(width: Self.openedSize.width, height: Self.openedSize.height + base.height) }
        let h = max(base.height, 30)
        switch pipelineState {
        case .idle: return CGSize(width: base.width, height: base.height)
        case .listening, .thinking, .done, .failed:
            let p = pill
            return CGSize(width: base.width + p.left + p.right, height: h)
        case .agent: return CGSize(width: 520, height: 140 + base.height)
        case .help: return CGSize(width: 560, height: 170 + base.height)
        }
    }

    /// Horizontal shift that keeps the pill's empty gap on the camera housing.
    var horizontalOffset: CGFloat {
        if status == .opened { return 0 }
        switch pipelineState {
        case .listening, .thinking, .done, .failed: return pill.offset
        default: return 0
        }
    }

    var cornerRadius: CGFloat {
        if status == .opened { return 30 }
        if case .idle = pipelineState { return 8 }
        return 10
    }

    var openedRect: CGRect {
        CGRect(
            x: screenRect.origin.x + (screenRect.width - notchSize.width) / 2 + horizontalOffset,
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
                if case .failed = pipelineState { open(.settings) } else { open() }
            }
        }
    }
}
