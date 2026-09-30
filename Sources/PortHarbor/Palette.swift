import AppKit
import SwiftUI

/// Colors that must hit a contrast target are defined per appearance, because
/// `.systemRed` on a light popover is around 3.4:1 — below AA for 10pt labels.
enum Palette {
    static let destructive = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            ? NSColor(srgbRed: 1.00, green: 0.45, blue: 0.42, alpha: 1)
            : NSColor(srgbRed: 0.70, green: 0.08, blue: 0.09, alpha: 1)
    })

    static let statusListening = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            ? NSColor(srgbRed: 0.31, green: 0.82, blue: 0.41, alpha: 1)
            : NSColor(srgbRed: 0.12, green: 0.48, blue: 0.20, alpha: 1)
    })

    static let statusBusy = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            ? NSColor(srgbRed: 1.00, green: 0.76, blue: 0.31, alpha: 1)
            : NSColor(srgbRed: 0.65, green: 0.40, blue: 0.00, alpha: 1)
    })
}
