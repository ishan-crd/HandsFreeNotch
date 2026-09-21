//
//  NotchWindow.swift
//  HandsFreeNotch
//
//  Adapted from NotchOS (https://github.com/ishan-crd/NotchOS). MIT License.
//

import Cocoa

/// A transparent strip across the top of the screen that the notch UI draws into. It is a
/// non-activating panel, so the app the user is working in keeps keyboard focus: the keystrokes
/// we synthesise must land there, not here.
final class NotchWindow: NSPanel {
    /// Only the opened panel (settings text fields) may take keyboard focus.
    var allowsKey = false

    init(screen: NSScreen, height: CGFloat) {
        let rect = CGRect(
            x: screen.frame.origin.x,
            y: screen.frame.origin.y + screen.frame.height - height,
            width: screen.frame.width,
            height: height
        )
        super.init(contentRect: rect, styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        isMovable = false
        hasShadow = false
        isFloatingPanel = true
        hidesOnDeactivate = false
        collectionBehavior = [.fullScreenAuxiliary, .stationary, .canJoinAllSpaces, .ignoresCycle]
        level = .statusBar + 8
    }

    override var canBecomeKey: Bool { allowsKey }
    override var canBecomeMain: Bool { false }
}
