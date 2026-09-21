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

// `HandsFreeNotch --set-key sk-ant-…` stores the Anthropic key in the keychain and switches the
// running app to Claude; `--use ollama|anthropic|off` picks the free-form model. Both exit at once.
if let index = CommandLine.arguments.firstIndex(of: "--set-key"), index + 1 < CommandLine.arguments.count {
    Keychain.write(CommandLine.arguments[index + 1], account: "anthropic")
    UserDefaults.standard.set(LLMProvider.anthropic.rawValue, forKey: "provider")
    DistributedNotificationCenter.default().postNotificationName(reloadNotification, object: nil, userInfo: nil, deliverImmediately: true)
    print("key saved to the keychain; free-form model: Claude Haiku 4.5")
    exit(0)
}
if let index = CommandLine.arguments.firstIndex(of: "--use"), index + 1 < CommandLine.arguments.count {
    let choice = CommandLine.arguments[index + 1].lowercased()
    guard let provider = LLMProvider(rawValue: choice == "off" ? "none" : choice) else {
        print("usage: --use anthropic | ollama | off"); exit(2)
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
