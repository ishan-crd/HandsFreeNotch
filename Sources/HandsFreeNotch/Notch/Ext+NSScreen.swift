//
//  Ext+NSScreen.swift
//  HandsFreeNotch
//
//  Adapted from NotchOS (https://github.com/ishan-crd/NotchOS). MIT License.
//

import Cocoa

extension NSScreen {
    /// The physical notch, or zero on a Mac without one.
    var notchSize: CGSize {
        guard safeAreaInsets.top > 0 else { return .zero }
        let leftPadding = auxiliaryTopLeftArea?.width ?? 0
        let rightPadding = auxiliaryTopRightArea?.width ?? 0
        guard leftPadding > 0, rightPadding > 0 else { return .zero }
        return CGSize(width: frame.width - leftPadding - rightPadding, height: safeAreaInsets.top)
    }

    var isBuiltin: Bool {
        guard let id = deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { return false }
        return CGDisplayIsBuiltin(id.uint32Value) == 1
    }

    static var builtin: NSScreen? {
        screens.first { $0.isBuiltin }
    }
}
