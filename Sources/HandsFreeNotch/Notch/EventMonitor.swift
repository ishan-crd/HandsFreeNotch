//
//  EventMonitor.swift
//  HandsFreeNotch
//
//  Adapted from NotchOS (https://github.com/ishan-crd/NotchOS). MIT License.
//

import Cocoa

/// A global and local monitor for one event mask. Clicks are the only mouse events watched;
/// there is no hover-open, so nothing runs on mouse move.
final class EventMonitor {
    private var global: Any?
    private var local: Any?
    private let mask: NSEvent.EventTypeMask
    private let handler: (NSEvent) -> Void

    init(mask: NSEvent.EventTypeMask, handler: @escaping (NSEvent) -> Void) {
        self.mask = mask
        self.handler = handler
    }

    deinit { stop() }

    func start() {
        global = NSEvent.addGlobalMonitorForEvents(matching: mask) { [weak self] event in self?.handler(event) }
        local = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] event in
            self?.handler(event)
            return event
        }
    }

    func stop() {
        if let global { NSEvent.removeMonitor(global) }
        if let local { NSEvent.removeMonitor(local) }
        global = nil
        local = nil
    }
}
