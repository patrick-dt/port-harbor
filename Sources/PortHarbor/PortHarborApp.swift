import SwiftUI

@main
struct PortHarborApp: App {
    @StateObject private var store = PortsStore()

    var body: some Scene {
        MenuBarExtra {
            PortsMenu()
                .environmentObject(store)
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "server.rack")
                Text("\(store.listeners.count)")
                    .monospacedDigit()
            }
        }
        .menuBarExtraStyle(.window)
    }
}
