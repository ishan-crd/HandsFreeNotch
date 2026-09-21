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
