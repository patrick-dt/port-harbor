import SwiftUI

@main
struct PortHarborApp: App {
    @StateObject private var ignoreStore: IgnoreStore
    @StateObject private var store: PortsStore
    @StateObject private var loginItem = LoginItem()

    init() {
        let ignoreStore = IgnoreStore()
        _ignoreStore = StateObject(wrappedValue: ignoreStore)
        _store = StateObject(wrappedValue: PortsStore(ignoreStore: ignoreStore))
    }

    var body: some Scene {
        MenuBarExtra {
            PortsMenu()
                .environmentObject(store)
                .environmentObject(ignoreStore)
                .environmentObject(loginItem)
        } label: {
            // A failed scan swaps the icon, so a stale count is not mistaken
            // for a live one while the popover is closed.
            let failed = store.scanState.isFailed
            HStack(spacing: 4) {
                Image(systemName: failed ? "exclamationmark.triangle" : "server.rack")
                Text("\(store.listeners.count)")
                    .monospacedDigit()
            }
            .accessibilityLabel(
                failed
                    ? "Port Harbor, scan failed, last seen \(store.listeners.count) local servers"
                    : "Port Harbor, \(store.listeners.count) local servers"
            )
        }
        .menuBarExtraStyle(.window)
    }
}
