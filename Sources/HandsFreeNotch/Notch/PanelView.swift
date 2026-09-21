//
//  PanelView.swift
//  HandsFreeNotch
//
//  Copyright © 2026 Ishan Gupta. MIT License.
//

import HandsFreeNotchCore
import ServiceManagement
import SwiftUI

/// The opened notch: recent commands, the command list, and settings.
struct PanelView: View {
    @Bindable var vm: NotchViewModel
    @State private var typed = ""

    var body: some View {
        VStack(spacing: 10) {
            header
            Group {
                switch vm.page {
                case .commands: commands
                case .help: HelpView(compact: false)
                case .settings: SettingsView(vm: vm)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .padding(.horizontal, 18)
        .padding(.top, 10)
        .padding(.bottom, 14)
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "waveform.circle.fill")
                .font(.system(size: 16))
                .foregroundStyle(.white)
            Text("HandsFreeNotch")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
            Text("hold \(vm.settings.hotkey.title)")
                .font(.system(size: 10.5))
                .foregroundStyle(.white.opacity(0.45))
            Spacer()
            tab("Recent", .commands)
            tab("Commands", .help)
            tab("Settings", .settings)
        }
    }

    private func tab(_ title: String, _ page: NotchViewModel.Page) -> some View {
        Button(title) { vm.page = page }
            .buttonStyle(.plain)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(vm.page == page ? .white : .white.opacity(0.45))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(vm.page == page ? Color.white.opacity(0.12) : .clear, in: Capsule())
    }

    private var commands: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "keyboard")
                    .foregroundStyle(.white.opacity(0.5))
                TextField("Type a command to test it, e.g. open safari", text: $typed)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .foregroundStyle(.white)
                    .onSubmit {
                        guard !typed.isEmpty else { return }
                        vm.pipeline.handle(typed)
                        typed = ""
                    }
                Button {
                    vm.pipeline.isListening ? vm.pipeline.endListening() : vm.pipeline.beginListening()
                } label: {
                    Image(systemName: vm.pipeline.isListening ? "stop.circle.fill" : "mic.circle.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(vm.pipeline.isListening ? .red : .white)
                }
                .buttonStyle(.plain)
                .help(vm.pipeline.isListening ? "Stop listening" : "Tap to talk")
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))

            if !vm.accessibilityGranted || !vm.speechGranted {
                permissionsBanner
            }

            if vm.history.isEmpty {
                Text("Nothing yet. Hold \(vm.settings.hotkey.title), say “open Safari”, let go.")
                    .font(.system(size: 11.5))
                    .foregroundStyle(.white.opacity(0.5))
                    .padding(.top, 8)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(Array(vm.history.prefix(8).enumerated()), id: \.offset) { _, item in
                            HStack(spacing: 8) {
                                Text(item.title)
                                    .font(.system(size: 11.5, weight: .medium))
                                    .foregroundStyle(.white.opacity(0.9))
                                    .lineLimit(1)
                                Text("“\(item.transcript)”")
                                    .font(.system(size: 10.5))
                                    .foregroundStyle(.white.opacity(0.4))
                                    .lineLimit(1)
                                Spacer()
                                Text("\(item.milliseconds) ms")
                                    .font(.system(size: 10, design: .rounded).monospacedDigit())
                                    .foregroundStyle(.white.opacity(0.4))
                                Text(item.tier.rawValue)
                                    .font(.system(size: 9, weight: .semibold))
                                    .foregroundStyle(tierColor(item.tier))
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 1.5)
                                    .background(tierColor(item.tier).opacity(0.15), in: Capsule())
                            }
                        }
                    }
                }
            }
        }
    }

    private var permissionsBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "lock.shield")
                .foregroundStyle(.orange)
            Text(!vm.speechGranted ? "Microphone and Speech Recognition are not allowed yet." : "Accessibility is not allowed yet; keys and scrolling will not work.")
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.8))
            Spacer()
            Button("Fix") { vm.page = .settings }
                .buttonStyle(.plain)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.orange)
        }
        .padding(8)
        .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
    }

    private func tierColor(_ tier: Routed.Tier) -> Color {
        switch tier {
        case .fast: return .green
        case .llm: return .purple
        case .agent: return .orange
        }
    }
}

struct HelpView: View {
    let compact: Bool

    private static let rows: [(String, String)] = [
        ("open spotify · launch chrome · switch to slack", "apps, instant"),
        ("open youtube · go to github.com · open this link", "sites and the clipboard"),
        ("search for best ramen near me · youtube lo-fi beats", "web search"),
        ("type hello team, on my way · press enter · select all", "typing and keys"),
        ("new tab · close tab · go back · reload · zoom in", "browser"),
        ("volume up · mute · set volume to 30 · brightness down", "system"),
        ("play · pause · next song · previous", "media"),
        ("scroll down · scroll up a lot · top · bottom", "scrolling"),
        ("quit spotify · hide chrome · lock screen · screenshot", "windows and Mac"),
        ("open spotify then play · anything else goes to the model", "sequences and free-form"),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 3 : 5) {
            ForEach(Array((compact ? Array(Self.rows.prefix(6)) : Self.rows).enumerated()), id: \.offset) { _, row in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(row.0)
                        .font(.system(size: compact ? 10.5 : 11.5, weight: .medium))
                        .foregroundStyle(.white.opacity(0.9))
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    Text(row.1)
                        .font(.system(size: compact ? 9.5 : 10.5))
                        .foregroundStyle(.white.opacity(0.4))
                        .lineLimit(1)
                }
            }
        }
    }
}

struct SettingsView: View {
    @Bindable var vm: NotchViewModel
    @State private var keyDraft = Settings.shared.anthropicKey

    var body: some View {
        @Bindable var settings = vm.settings
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                row("Push to talk") {
                    Picker("", selection: $settings.hotkey) {
                        ForEach(Hotkey.allCases) { Text($0.title).tag($0) }
                    }
                    .labelsHidden()
                    .frame(width: 180)
                }
                row("Free-form model") {
                    Picker("", selection: $settings.provider) {
                        ForEach(LLMProvider.allCases) { Text($0.title).tag($0) }
                    }
                    .labelsHidden()
                    .frame(width: 180)
                }
                if settings.provider == .anthropic {
                    row("Anthropic API key") {
                        SecureField("sk-ant-…", text: $keyDraft)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 220)
                            .onSubmit { settings.anthropicKey = keyDraft }
                        Button("Save") { settings.anthropicKey = keyDraft }
                            .controlSize(.small)
                    }
                    row("Model") {
                        TextField(AnthropicRouter.defaultModel, text: $settings.anthropicModel)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 220)
                    }
                }
                if settings.provider == .ollama {
                    row("Ollama model") {
                        TextField(OllamaRouter.defaultModel, text: $settings.ollamaModel)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 220)
                    }
                }
                row("Screen agent path") {
                    TextField("…/typesafe-computer-use", text: $settings.agentPath)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 280)
                }
                row("Launch at login") {
                    Toggle("", isOn: $settings.launchAtLogin)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .controlSize(.small)
                        .onChange(of: settings.launchAtLogin) { _, on in
                            try? on ? SMAppService.mainApp.register() : SMAppService.mainApp.unregister()
                        }
                }
                Divider().overlay(Color.white.opacity(0.1))
                permission("Microphone & Speech", granted: vm.speechGranted, detail: vm.onDevice ? "on-device" : "server") {
                    vm.pipeline.speech.requestAuthorization { _ in vm.refreshPermissions() }
                    openPrivacy("Privacy_SpeechRecognition")
                }
                permission("Accessibility", granted: vm.accessibilityGranted, detail: "keys, scroll, hotkey") {
                    Keys.requestAccessibility()
                    openPrivacy("Privacy_Accessibility")
                }
                HStack {
                    Spacer()
                    Button("Quit HandsFreeNotch") { NSApp.terminate(nil) }
                        .controlSize(.small)
                }
            }
            .padding(.trailing, 4)
        }
    }

    private func row<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: 10) {
            Text(label)
                .font(.system(size: 11.5))
                .foregroundStyle(.white.opacity(0.75))
                .frame(width: 130, alignment: .leading)
            content()
            Spacer()
        }
    }

    private func permission(_ name: String, granted: Bool, detail: String, action: @escaping () -> Void) -> some View {
        HStack(spacing: 8) {
            Circle().fill(granted ? .green : .orange).frame(width: 7, height: 7)
            Text(name).font(.system(size: 11.5)).foregroundStyle(.white.opacity(0.85))
            Text(detail).font(.system(size: 10)).foregroundStyle(.white.opacity(0.4))
            Spacer()
            if !granted {
                Button("Allow…", action: action).controlSize(.small)
            }
        }
    }

    private func openPrivacy(_ pane: String) {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)") {
            NSWorkspace.shared.open(url)
        }
    }
}
