//
//  AppDelegate.swift
//  HandsFreeNotch
//
//  Copyright © 2026 Ishan Gupta. MIT License.
//

import AppKit
import HandsFreeNotchCore
import os

let sayNotification = Notification.Name("com.ishan.HandsFreeNotch.say")

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let log = Logger(subsystem: "com.ishan.HandsFreeNotch", category: "app")
    private var controller: NotchWindowController?
    private var pipeline: CommandPipeline!
    private var hotkey: HotkeyMonitor!
    private var lastScreenSignature: String?

    func applicationDidFinishLaunching(_: Notification) {
        NSApp.setActivationPolicy(.accessory)

        let settings = Settings.shared
        let apps = AppIndex()
        apps.refreshIfNeeded()
        let speech = SpeechListener()
        pipeline = CommandPipeline(speech: speech, apps: apps, llm: settings.makeLLM(), agent: settings.makeAgent())

        // Settings changes take effect on the next command, no restart.
        withObservationTracking { _ = settings.provider; _ = settings.anthropicKey; _ = settings.anthropicModel; _ = settings.ollamaModel; _ = settings.agentPath; _ = settings.hotkey } onChange: { [weak self] in
            DispatchQueue.main.async { self?.applySettings() }
        }

        pipeline.onLog = { [log] line in log.info("\(line, privacy: .public)") }
        DistributedNotificationCenter.default().addObserver(forName: sayNotification, object: nil, queue: .main) { [weak self] note in
            guard let text = note.userInfo?["text"] as? String else { return }
            MainActor.assumeIsolated { self?.pipeline.handle(text) }
        }

        // Hold the key to talk; a quick tap keeps the microphone open until the next tap or "stop".
        var pressedAt: TimeInterval = 0
        var tapStopped = false
        hotkey = HotkeyMonitor(hotkey: settings.hotkey)
        hotkey.onPress = { [weak self] in
            guard let self else { return }
            pressedAt = ProcessInfo.processInfo.systemUptime
            if self.pipeline.continuous {
                tapStopped = true
                self.pipeline.stopContinuous()
            } else {
                tapStopped = false
                self.pipeline.beginListening()
            }
        }
        hotkey.onRelease = { [weak self] in
            guard let self, !tapStopped else { return }
            if ProcessInfo.processInfo.systemUptime - pressedAt < 0.35 {
                self.pipeline.startContinuous()
            } else {
                self.pipeline.endListening()
            }
        }
        hotkey.start()

        NotificationCenter.default.addObserver(self, selector: #selector(rebuildWindow), name: NSApplication.didChangeScreenParametersNotification, object: nil)
        rebuildWindow()

        if !speech.authorized {
            speech.requestAuthorization { [weak self] granted in
                self?.controller?.vm.refreshPermissions()
                if !granted { self?.controller?.vm.open(.settings) }
            }
        }
        if !Keys.accessibilityTrusted {
            Keys.requestAccessibility()
            waitForAccessibility()
        }
        log.info("ready; hotkey \(settings.hotkey.title, privacy: .public); on-device speech \(speech.onDevice); model \(self.pipeline.llm?.label ?? "off", privacy: .public) (key from \(settings.keySource, privacy: .public)); agent \(self.pipeline.agent?.isAvailable == true ? "ready" : "off", privacy: .public)")
    }

    private func applySettings() {
        let settings = Settings.shared
        pipeline.llm = settings.makeLLM()
        pipeline.agent = settings.makeAgent()
        hotkey.hotkey = settings.hotkey
        // Re-arm the observation; withObservationTracking fires once per change.
        withObservationTracking { _ = settings.provider; _ = settings.anthropicKey; _ = settings.anthropicModel; _ = settings.ollamaModel; _ = settings.agentPath; _ = settings.hotkey } onChange: { [weak self] in
            DispatchQueue.main.async { self?.applySettings() }
        }
    }

    /// The global key monitor only starts delivering events once Accessibility is granted, so
    /// re-arm it when that happens instead of asking the user to relaunch.
    private func waitForAccessibility() {
        Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] timer in
            guard Keys.accessibilityTrusted else { return }
            timer.invalidate()
            DispatchQueue.main.async {
                self?.hotkey.start()
                self?.controller?.vm.refreshPermissions()
            }
        }
    }

    @objc private func rebuildWindow() {
        let screen = NSScreen.builtin.flatMap { $0.notchSize != .zero ? $0 : nil } ?? NSScreen.main
        guard let screen else { controller?.destroy(); controller = nil; return }
        let signature = "\(screen.frame)|\(screen.notchSize)"
        if controller != nil, signature == lastScreenSignature { return }
        lastScreenSignature = signature
        controller?.destroy()
        let vm = NotchViewModel(pipeline: pipeline)
        controller = NotchWindowController(screen: screen, vm: vm)
    }

    func applicationShouldHandleReopen(_: NSApplication, hasVisibleWindows _: Bool) -> Bool {
        controller?.vm.open()
        return true
    }
}
