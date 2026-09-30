import AppKit
import SwiftUI

/// Replaces the MenuBarExtra window's default glass/vibrancy with an opaque
/// system fill. `.containerBackground(..., for: .window)` owns the SwiftUI
/// chrome on macOS 15+; the AppKit hook is there because Tahoe still installs
/// an `NSVisualEffectView` (or `NSGlassEffectView`) behind the hosting view
/// unless the panel itself is marked opaque.
struct SolidWindowBackground: ViewModifier {
    func body(content: Content) -> some View {
        // `.window` is macOS 15 SDK only; `#available` does not hide it from Xcode 15.
        #if compiler(>=6.0)
        if #available(macOS 15.0, *) {
            content
                .containerBackground(Color(nsColor: .windowBackgroundColor), for: .window)
                .background(OpaquePopoverWindow())
        } else {
            content
                .background(Color(nsColor: .windowBackgroundColor))
                .background(OpaquePopoverWindow())
        }
        #else
        content
            .background(Color(nsColor: .windowBackgroundColor))
            .background(OpaquePopoverWindow())
        #endif
    }
}

private struct OpaquePopoverWindow: NSViewRepresentable {
    func makeNSView(context: Context) -> OpaquePopoverNSView {
        OpaquePopoverNSView()
    }

    func updateNSView(_ nsView: OpaquePopoverNSView, context: Context) {
        // Chrome is applied when the view joins a window, not on every SwiftUI
        // invalidation — mutating NSWindow from updateNSView can re-enter layout.
    }
}

private final class OpaquePopoverNSView: NSView {
    private var appliedWindow: ObjectIdentifier?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        applySolidChrome()
    }

    override func viewDidMoveToSuperview() {
        super.viewDidMoveToSuperview()
        applySolidChrome()
    }

    func applySolidChrome() {
        guard let window else {
            appliedWindow = nil
            return
        }
        let id = ObjectIdentifier(window)
        guard appliedWindow != id else { return }
        appliedWindow = id

        window.isOpaque = true
        window.backgroundColor = .windowBackgroundColor
        window.invalidateShadow()

        if let contentView = window.contentView {
            contentView.wantsLayer = true
            contentView.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        }

        var cursor: NSView? = superview
        while let view = cursor {
            if let effect = view as? NSVisualEffectView {
                effect.material = .windowBackground
                effect.blendingMode = .behindWindow
                effect.state = .active
            }
            // Tahoe's Liquid Glass chrome (NSGlassEffectView and cousins).
            // Paint over it rather than hiding — hiding clips the rounded mask.
            let typeName = NSStringFromClass(type(of: view))
            if typeName.contains("Glass") || typeName.contains("VisualEffect") {
                view.wantsLayer = true
                view.layer?.isOpaque = true
                view.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
            }
            cursor = view.superview
        }
    }
}

/// `keyboardShortcut` has no optional overload; this keeps the call sites clean.
struct OptionalShortcut: ViewModifier {
    let key: Character?

    func body(content: Content) -> some View {
        if let key {
            content.keyboardShortcut(KeyEquivalent(key), modifiers: .command)
        } else {
            content
        }
    }
}

/// Reports whether the MenuBarExtra popover is on screen, so the store can
/// scan quickly while it is open and slowly while it is not.
///
/// SwiftUI's `onAppear`/`onDisappear` are unreliable here: the popover's view
/// tree is kept alive between openings. The window's occlusion state is not.
struct PopoverVisibilityReporter: NSViewRepresentable {
    let onChange: (Bool) -> Void

    func makeNSView(context: Context) -> PopoverVisibilityNSView {
        let view = PopoverVisibilityNSView()
        view.onChange = onChange
        return view
    }

    func updateNSView(_ nsView: PopoverVisibilityNSView, context: Context) {
        nsView.onChange = onChange
    }
}

final class PopoverVisibilityNSView: NSView {
    var onChange: ((Bool) -> Void)?
    private var observer: NSObjectProtocol?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let observer {
            NotificationCenter.default.removeObserver(observer)
            self.observer = nil
        }
        guard let window else {
            onChange?(false)
            return
        }
        observer = NotificationCenter.default.addObserver(
            forName: NSWindow.didChangeOcclusionStateNotification,
            object: window,
            queue: .main
        ) { [weak self] _ in
            self?.report()
        }
        report()
    }

    private func report() {
        guard let window else { return }
        onChange?(window.isVisible && window.occlusionState.contains(.visible))
    }

    deinit {
        if let observer {
            NotificationCenter.default.removeObserver(observer)
        }
    }
}

func copyToPasteboard(_ text: String) {
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(text, forType: .string)
}
