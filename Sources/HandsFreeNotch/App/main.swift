//
//  main.swift
//  HandsFreeNotch
//
//  Copyright © 2026 Ishan Gupta. MIT License.
//

import AppKit

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
