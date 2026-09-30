import Foundation
import ServiceManagement

/// "Open at Login" for the packaged app, backed by `SMAppService.mainApp`.
///
/// Only meaningful when running from a `.app` bundle; `swift run` has no bundle
/// to register, so the toggle is hidden there.
@MainActor
final class LoginItem: ObservableObject {
    @Published private(set) var isEnabled = false
    @Published private(set) var lastError: String?

    var isAvailable: Bool {
        Bundle.main.bundleURL.pathExtension == "app"
    }

    init() {
        refresh()
    }

    func refresh() {
        isEnabled = SMAppService.mainApp.status == .enabled
    }

    func toggle() {
        do {
            if isEnabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
        refresh()
    }
}
