//
//  main.swift
//  HandsFreeNotch
//
//  Copyright © 2026 Ishan Gupta. MIT License.
//

import AppKit

// `HandsFreeNotch --say "open safari"` hands the text to the running app and exits, so commands
// can come from a script, Raycast or Shortcuts as well as the microphone.
if let index = CommandLine.arguments.firstIndex(of: "--say"), index + 1 < CommandLine.arguments.count {
    let text = CommandLine.arguments[(index + 1)...].joined(separator: " ")
    DistributedNotificationCenter.default().postNotificationName(
        sayNotification, object: nil, userInfo: ["text": text], deliverImmediately: true
    )
    exit(0)
}

// `HandsFreeNotch --set-key sk-ant-…` (Anthropic) or `--set-key openrouter sk-or-…` stores the key
// in ~/.config/handsfreenotch/.env and switches the running app to that provider; `--use ollama|anthropic|openrouter|off`
// picks the free-form model. All exit at once.
if let index = CommandLine.arguments.firstIndex(of: "--set-key"), index + 1 < CommandLine.arguments.count {
    var args = Array(CommandLine.arguments[(index + 1)...])
    var provider = LLMProvider.anthropic
    if args.count >= 2, let named = LLMProvider(rawValue: args[0].lowercased()) { provider = named; args.removeFirst() }
    KeyStore.write(args[0], name: provider == .openrouter ? "OPENROUTER_API_KEY" : "ANTHROPIC_API_KEY")
    UserDefaults.standard.set(provider.rawValue, forKey: "provider")
    DistributedNotificationCenter.default().postNotificationName(reloadNotification, object: nil, userInfo: nil, deliverImmediately: true)
    print("key saved to \(KeyStore.path); free-form model: \(provider.title)")
    exit(0)
}
if let index = CommandLine.arguments.firstIndex(of: "--model"), index + 1 < CommandLine.arguments.count {
    let model = CommandLine.arguments[index + 1]
    let key = model.hasSuffix(":free") || model.contains("/") ? "openrouterModel" : (model.hasPrefix("claude") ? "anthropicModel" : "ollamaModel")
    UserDefaults.standard.set(model, forKey: key)
    DistributedNotificationCenter.default().postNotificationName(reloadNotification, object: nil, userInfo: nil, deliverImmediately: true)
    print("\(key.replacingOccurrences(of: "Model", with: "")) model: \(model)")
    exit(0)
}
if let index = CommandLine.arguments.firstIndex(of: "--use"), index + 1 < CommandLine.arguments.count {
    let choice = CommandLine.arguments[index + 1].lowercased()
    guard let provider = LLMProvider(rawValue: choice == "off" ? "none" : choice) else {
        print("usage: --use anthropic | openrouter | ollama | off"); exit(2)
    }
    UserDefaults.standard.set(provider.rawValue, forKey: "provider")
    DistributedNotificationCenter.default().postNotificationName(reloadNotification, object: nil, userInfo: nil, deliverImmediately: true)
    print("free-form model: \(provider.title)")
    exit(0)
}

// One instance at a time: a second launch replaces the first.
if let bundleID = Bundle.main.bundleIdentifier {
    for other in NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
    where other.processIdentifier != ProcessInfo.processInfo.processIdentifier {
        other.terminate()
    }
}

private let delegate = MainActor.assumeIsolated { AppDelegate() }
MainActor.assumeIsolated { NSApplication.shared.delegate = delegate }
_ = NSApplicationMain(CommandLine.argc, CommandLine.unsafeArgv)
