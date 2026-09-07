import Combine
import Foundation
import SwiftUI

struct ListenerRow: Identifiable, Hashable {
    let port: Int
    let pid: Int
    /// Short process name from `lsof`, e.g. `node` or `Raycast`. This is what
    /// the ignore list matches on.
    let processName: String
    let fullCommand: String
    let cwd: String?
    let framework: Framework
    let projectName: String?

    var id: String { "\(pid)-\(port)" }

    var displayTitle: String {
        projectName ?? "localhost:\(port)"
    }

    var subtitle: String {
        FrameworkDetector.subtitle(framework: framework, fullCommand: fullCommand)
    }

    /// The directory to open in an editor or terminal, or `nil` when there is
    /// nothing meaningful to open. `/` is treated as absent: app bundles report
    /// the root directory, and opening `/` in Cursor is never what was meant.
    var workingDirectory: String? {
        guard let cwd, !cwd.isEmpty, cwd != "/" else { return nil }
        return cwd
    }

    /// Computed once per row, not in SwiftUI `body`. Relaunch checks walk PATH
    /// on disk; doing that during layout is what aborted the popover.
    let canRelaunch: Bool

    /// Stopping is confirmed only when we are not reasonably sure this is a dev
    /// server the user started. The common case stays one click; the ambiguous
    /// case — an app bundle holding a port — asks first.
    var needsStopConfirmation: Bool {
        let looksLikeDevServer = (framework != .unknown && workingDirectory != nil)
            || Actions.isKnownDevBinary(fullCommand: fullCommand)
        return !looksLikeDevServer
    }
}

/// What the app is currently doing to a single row.
enum RowActivity: Equatable {
    case idle
    case stopping
    case stopped
    case restarting
}

/// A failed action, kept until the user dismisses it or retries.
struct ActionFailure: Equatable {
    let action: String
    let message: String
    /// Command the user can run by hand to get past us, if there is one.
    let command: String?
}

/// Whether we could look at all, as distinct from what we found.
enum ScanState: Equatable {
    case scanning
    case loaded
    case failed(message: String, command: String)
}

@MainActor
final class PortsStore: ObservableObject {
    @Published private(set) var listeners: [ListenerRow] = []
    @Published private(set) var scanState: ScanState = .scanning
    @Published private(set) var isScanning = false
    @Published private(set) var activity: [String: RowActivity] = [:]
    @Published private(set) var failures: [String: ActionFailure] = [:]

    /// Rows we stopped that are gone from the scan but still shown so Undo has
    /// somewhere to live.
    @Published private(set) var ghosts: [String: ListenerRow] = [:]

    let ignoreStore: IgnoreStore

    /// Rows visible in the list: live listeners plus not-yet-expired ghosts.
    var displayRows: [ListenerRow] {
        let live = listeners
        let liveIDs = Set(live.map(\.id))
        let orphaned = ghosts.values.filter { !liveIDs.contains($0.id) }
        return (live + orphaned).sorted { a, b in
            if a.port != b.port { return a.port < b.port }
            return a.pid < b.pid
        }
    }

    private var rawRows: [ListenerRow] = []
    private var refreshTimer: Timer?
    private var isRefreshing = false
    /// When a refresh is already in flight, coalesce further requests so ⌘R is
    /// never a silent no-op.
    private var refreshQueued = false
    private var queuedManual = false
    private var cancellables: Set<AnyCancellable> = []
    private var undoTasks: [String: Task<Void, Never>] = [:]

    /// While the pointer is inside the list we hold new scan results back, so a
    /// row can never move out from under a click aimed at Stop.
    private var isPointerInside = false
    private var frozenSince: Date?
    private var pendingRows: [ListenerRow]?

    private let refreshInterval: TimeInterval = 3.0
    private let undoWindow: TimeInterval = 5.0

    /// The popover can close while the pointer is still over the list, and that
    /// produces no hover-exit event, so the freeze needs its own upper bound.
    private let maxFreeze: TimeInterval = 12.0

    /// Pure freeze policy so tests can cover the click-safety window without a UI.
    static func shouldHoldScanUpdate(
        isPointerInside: Bool,
        frozenSince: Date?,
        now: Date,
        maxFreeze: TimeInterval
    ) -> Bool {
        guard isPointerInside, let since = frozenSince else { return false }
        return now.timeIntervalSince(since) < maxFreeze
    }

    init(ignoreStore: IgnoreStore) {
        self.ignoreStore = ignoreStore

        ignoreStore.$ignoredNames
            .dropFirst()
            .sink { [weak self] _ in
                // Re-filter immediately instead of waiting for the next scan,
                // so Ignore and Unignore both feel instant.
                Task { @MainActor in self?.applyFilter() }
            }
            .store(in: &cancellables)

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

    // MARK: - Scanning

    /// - Parameter manual: user-triggered scans show progress; the 3-second
    ///   background poll must not flicker a spinner every 3 seconds.
    func refresh(manual: Bool = false) {
        if isRefreshing {
            refreshQueued = true
            queuedManual = queuedManual || manual
            return
        }
        isRefreshing = true
        isScanning = manual || scanState == .scanning

        Task {
            defer {
                isRefreshing = false
                isScanning = false
                if refreshQueued {
                    let againManual = queuedManual
                    refreshQueued = false
                    queuedManual = false
                    refresh(manual: againManual)
                }
            }

            let baseListeners: [Listener]
            do {
                baseListeners = try await PortScanner.listLocalhostListeningTCPListeners()
            } catch {
                // A failed scan is not an empty machine. Keep whatever we last
                // knew and say why we can't refresh it.
                scanState = .failed(
                    message: error.localizedDescription,
                    command: PortScanner.commandLine
                )
                return
            }

            guard !baseListeners.isEmpty else {
                scanState = .loaded
                store(rows: [])
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
                    processName: l.lsofCommand,
                    fullCommand: fullCommand,
                    cwd: info?.cwd,
                    framework: framework,
                    projectName: projectName,
                    canRelaunch: Actions.canRelaunch(fullCommand: fullCommand)
                )
            }

            scanState = .loaded
            store(rows: rows.sorted { a, b in
                if a.port != b.port { return a.port < b.port }
                return a.pid < b.pid
            })
        }
    }

    /// Called by the list so scan results never reorder rows mid-click.
    func setPointerInside(_ inside: Bool) {
        isPointerInside = inside
        frozenSince = inside ? (frozenSince ?? Date()) : nil
        guard !inside else { return }

        if let pending = pendingRows {
            pendingRows = nil
            rawRows = pending
            applyFilter()
        }
    }

    private func store(rows: [ListenerRow]) {
        if Self.shouldHoldScanUpdate(
            isPointerInside: isPointerInside,
            frozenSince: frozenSince,
            now: Date(),
            maxFreeze: maxFreeze
        ) {
            pendingRows = rows
            return
        }
        pendingRows = nil
        frozenSince = isPointerInside ? Date() : nil
        rawRows = rows
        applyFilter()
    }

    private func applyFilter() {
        listeners = rawRows.filter { !ignoreStore.isIgnored($0.processName) }
        // Drop stale per-row state for rows that can no longer appear.
        let known = Set(listeners.map(\.id)).union(ghosts.keys)
        activity = activity.filter { known.contains($0.key) }
        failures = failures.filter { known.contains($0.key) }
    }

    // MARK: - Ignore list

    func ignore(_ row: ListenerRow) {
        ignoreStore.ignore(row.processName)
    }

    func unignore(_ name: String) {
        ignoreStore.unignore(name)
    }

    // MARK: - Row actions

    func openURL(for row: ListenerRow) {
        run("Open", on: row, command: nil) {
            try Actions.openURL(port: row.port)
        }
    }

    func openCursor(for row: ListenerRow) {
        guard let cwd = row.workingDirectory else { return }
        let quoted = Actions.shellSingleQuoted(cwd)
        runDetached("Cursor", on: row, command: "open -a Cursor \(quoted)") {
            try Actions.openCursor(at: cwd)
        }
    }

    func openTerminal(for row: ListenerRow) {
        guard let cwd = row.workingDirectory else { return }
        let quoted = Actions.shellSingleQuoted(cwd)
        // NSAppleScript is not thread-safe, so this one stays on the main actor.
        run("Terminal", on: row, command: "cd \(quoted)") {
            try Actions.openTerminal(at: cwd)
        }
    }

    func stop(_ row: ListenerRow) {
        failures[row.id] = nil
        activity[row.id] = .stopping

        Task.detached(priority: .userInitiated) { [row] in
            do {
                try Actions.stop(pid: row.pid, expectedCommand: row.fullCommand, signal: SIGTERM)
                await MainActor.run { self.didStop(row) }
            } catch {
                await MainActor.run {
                    self.activity[row.id] = .idle
                    self.failures[row.id] = ActionFailure(
                        action: "Stop",
                        message: error.localizedDescription,
                        command: "kill -TERM \(row.pid)"
                    )
                }
            }
            await MainActor.run { self.refresh() }
        }
    }

    func restart(_ row: ListenerRow) {
        failures[row.id] = nil
        activity[row.id] = .restarting

        Task.detached(priority: .userInitiated) { [row] in
            do {
                try Actions.restart(pid: row.pid, fullCommand: row.fullCommand, cwd: row.cwd)
                await MainActor.run { self.activity[row.id] = .idle }
            } catch {
                await MainActor.run {
                    // The kill may already have happened, so this row is very
                    // likely gone. Keep it on screen with the reason attached
                    // and offer the command, rather than letting it vanish.
                    self.activity[row.id] = .stopped
                    self.ghosts[row.id] = row
                    self.failures[row.id] = ActionFailure(
                        action: "Restart",
                        message: error.localizedDescription,
                        command: Actions.pasteableShellCommand(row.fullCommand)
                    )
                }
            }
            try? await Task.sleep(nanoseconds: 700_000_000)
            await MainActor.run { self.refresh() }
        }
    }

    /// Relaunch a row we stopped, within the undo window.
    func undoStop(_ row: ListenerRow) {
        failures[row.id] = nil
        activity[row.id] = .restarting
        undoTasks[row.id]?.cancel()
        undoTasks[row.id] = nil

        Task.detached(priority: .userInitiated) { [row] in
            do {
                try Actions.relaunch(fullCommand: row.fullCommand, cwd: row.cwd)
                await MainActor.run {
                    self.ghosts[row.id] = nil
                    self.activity[row.id] = .idle
                }
            } catch {
                await MainActor.run {
                    self.activity[row.id] = .stopped
                    self.failures[row.id] = ActionFailure(
                        action: "Undo",
                        message: error.localizedDescription,
                        command: Actions.pasteableShellCommand(row.fullCommand)
                    )
                }
            }
            try? await Task.sleep(nanoseconds: 700_000_000)
            await MainActor.run { self.refresh() }
        }
    }

    func dismiss(_ row: ListenerRow) {
        failures[row.id] = nil
        expireGhost(row.id)
    }

    func activity(for row: ListenerRow) -> RowActivity {
        activity[row.id] ?? .idle
    }

    func failure(for row: ListenerRow) -> ActionFailure? {
        failures[row.id]
    }

    /// Whether the row is a stopped remnant rather than a live listener.
    func isGhost(_ row: ListenerRow) -> Bool {
        ghosts[row.id] != nil && !listeners.contains { $0.id == row.id }
    }

    private func didStop(_ row: ListenerRow) {
        activity[row.id] = .stopped
        ghosts[row.id] = row

        let window = undoWindow
        undoTasks[row.id]?.cancel()
        undoTasks[row.id] = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(window * 1_000_000_000))
            guard !Task.isCancelled else { return }
            self?.expireGhost(row.id)
        }
    }

    private func expireGhost(_ id: String) {
        undoTasks[id]?.cancel()
        undoTasks[id] = nil
        ghosts[id] = nil
        if activity[id] == .stopped {
            activity[id] = nil
        }
    }

    // MARK: - Action plumbing

    private func run(
        _ action: String,
        on row: ListenerRow,
        command: String?,
        _ work: () throws -> Void
    ) {
        failures[row.id] = nil
        do {
            try work()
        } catch {
            failures[row.id] = ActionFailure(
                action: action,
                message: error.localizedDescription,
                command: command
            )
        }
    }

    private func runDetached(
        _ action: String,
        on row: ListenerRow,
        command: String?,
        _ work: @escaping @Sendable () throws -> Void
    ) {
        failures[row.id] = nil
        Task.detached(priority: .userInitiated) { [row] in
            do {
                try work()
            } catch {
                await MainActor.run {
                    self.failures[row.id] = ActionFailure(
                        action: action,
                        message: error.localizedDescription,
                        command: command
                    )
                }
            }
        }
    }
}
