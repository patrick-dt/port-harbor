import Foundation
import SwiftUI

struct ListenerRow: Identifiable, Hashable {
    let port: Int
    let pid: Int
    let fullCommand: String
    let cwd: String?
    let framework: Framework
    let projectName: String?

    var id: String { "\(pid)-\(port)" }

    var displayTitle: String {
        projectName ?? "localhost:\(port)"
    }

    var subtitle: String {
        FrameworkDetector.subtitle(framework: framework, fullCommand: fullCommand, pid: pid)
    }
}

@MainActor
final class PortsStore: ObservableObject {
    @Published private(set) var listeners: [ListenerRow] = []

    private var refreshTimer: Timer?
    private var isRefreshing = false

    private let refreshInterval: TimeInterval = 3.0

    init() {
        refresh()

        refreshTimer = Timer.scheduledTimer(withTimeInterval: refreshInterval, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                self.refresh()
            }
        }
    }

    deinit {
        refreshTimer?.invalidate()
    }

    func refresh() {
        guard !isRefreshing else { return }
        isRefreshing = true

        Task {
            defer { isRefreshing = false }

            let baseListeners = await PortScanner.listLocalhostListeningTCPListeners()
            guard !baseListeners.isEmpty else {
                self.listeners = []
                return
            }

            let pids = baseListeners.map(\.pid)
            let infos = await ProcessInfoFetcher.fetchProcessInfo(for: pids)

            let rows: [ListenerRow] = baseListeners.map { l in
                let info = infos[l.pid]
                let fullCommand = info?.fullCommand.isEmpty == false ? info!.fullCommand : l.lsofCommand
                let framework = FrameworkDetector.detect(from: fullCommand)
                let projectName = FrameworkDetector.projectName(from: info?.cwd)

                return ListenerRow(
                    port: l.port,
                    pid: l.pid,
                    fullCommand: fullCommand,
                    cwd: info?.cwd,
                    framework: framework,
                    projectName: projectName
                )
            }

            self.listeners = rows.sorted { a, b in
                if a.port != b.port { return a.port < b.port }
                return a.pid < b.pid
            }
        }
    }

    func openURL(for row: ListenerRow) {
        Actions.openURL(port: row.port)
    }

    func openCursor(for row: ListenerRow) {
        guard let cwd = row.cwd, !cwd.isEmpty else { return }
        Actions.openCursor(at: cwd)
    }

    func openTerminal(for row: ListenerRow) {
        guard let cwd = row.cwd, !cwd.isEmpty else { return }
        Actions.openTerminal(at: cwd)
    }

    func stop(_ row: ListenerRow) {
        Task.detached(priority: .utility) { [row] in
            Actions.stop(pid: row.pid, signal: SIGTERM)
            try? await Task.sleep(nanoseconds: 500_000_000)
            await MainActor.run {
                self.refresh()
            }
        }
    }

    func restart(_ row: ListenerRow) {
        Task.detached(priority: .utility) { [row] in
            do {
                try Actions.restart(pid: row.pid, fullCommand: row.fullCommand, cwd: row.cwd)
            } catch {
                // Best-effort
            }
            try? await Task.sleep(nanoseconds: 700_000_000)
            await MainActor.run {
                self.refresh()
            }
        }
    }
}
