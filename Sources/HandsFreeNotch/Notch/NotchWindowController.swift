//
//  NotchWindowController.swift
//  HandsFreeNotch
//
//  Adapted from NotchOS (https://github.com/ishan-crd/NotchOS). MIT License.
//

import Cocoa
import SwiftUI

private let stripHeight: CGFloat = 340

@MainActor
final class NotchWindowController: NSWindowController {
    let vm: NotchViewModel
    private var clicks: EventMonitor?

    init(screen: NSScreen, vm: NotchViewModel) {
        self.vm = vm
        let window = NotchWindow(screen: screen, height: stripHeight)
        super.init(window: window)

        var notchSize = screen.notchSize
        if notchSize == .zero { notchSize = CGSize(width: 180, height: 32) }
        vm.deviceNotchRect = CGRect(
            x: screen.frame.origin.x + (screen.frame.width - notchSize.width) / 2,
            y: screen.frame.origin.y + screen.frame.height - notchSize.height,
            width: notchSize.width,
            height: notchSize.height
        )
        vm.screenRect = screen.frame

        let host = NSHostingView(rootView: NotchView(vm: vm))
        host.frame = window.contentView?.bounds ?? .zero
        host.autoresizingMask = [.width, .height]
        window.contentView = host
        window.orderFrontRegardless()

        vm.onOpenChanged = { [weak window] opened in
            window?.allowsKey = opened
            if opened {
                window?.makeKey()
            } else {
                window?.resignKey()
            }
        }

        clicks = EventMonitor(mask: .leftMouseDown) { [weak vm] _ in
            vm?.mouseDown(at: NSEvent.mouseLocation)
        }
        clicks?.start()
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) { fatalError() }

    func destroy() {
        clicks?.stop()
        window?.close()
        window = nil
    }
}
