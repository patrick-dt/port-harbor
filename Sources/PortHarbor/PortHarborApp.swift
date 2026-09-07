import SwiftUI

@main
struct PortHarborApp: App {
    @StateObject private var ignoreStore: IgnoreStore
    @StateObject private var store: PortsStore

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
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "server.rack")
                Text("\(store.listeners.count)")
                    .monospacedDigit()
            }
            .accessibilityLabel("Port Harbor, \(store.listeners.count) local servers")
        }
        .menuBarExtraStyle(.window)
    }
}
