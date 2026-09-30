import AppKit
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
    let binds: BindInfo

    var id: String { "\(pid)-\(port)" }

    var displayTitle: String {
        projectName ?? "\(binds.openHost):\(port)"
    }

    /// Port slot in the title row. IPv4-only binds show the literal so a
    /// sibling on `::1` with the same port is visually distinct.
    var portBadge: String {
        if projectName != nil, binds.isIPv4Only {
            return "\(binds.openHost):\(port)"
        }
        return ":\(port)"
    }

    var browserURL: String {
        binds.httpURL(port: port)
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

    var isFailed: Bool {
        if case .failed = self { return true }
        return false
    }
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

    /// Scan often while the list is on screen; when it is closed only the
    /// menu bar count depends on it, and that can lag without harm. Port
    /// Harbor runs all day as a login item, so the closed rate is what the
    /// battery sees.
    static let visibleRefreshInterval: TimeInterval = 3
    static let hiddenRefreshInterval: TimeInterval = 20
    private var isMenuVisible = false

    /// Why nobody can be looking right now. While any reason holds, the timer
    /// is off entirely: no scans with the display asleep, the screen locked,
    /// or another user switched in. (During real system sleep macOS suspends
    /// the process anyway.)
    enum IdleReason: Hashable {
        case screensAsleep
        case screenLocked
        case sessionInactive
    }
    private var idleReasons: Set<IdleReason> = []
    private var systemObservers: [(NotificationCenter, NSObjectProtocol)] = []

    /// Pure polling policy so tests can cover it without timers.
    static func refreshInterval(menuVisible: Bool, idle: Bool) -> TimeInterval? {
        if idle { return nil }
        return menuVisible ? visibleRefreshInterval : hiddenRefreshInterval
    }
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
        scheduleRefreshTimer()
        observeUserPresence()
    }

    deinit {
        refreshTimer?.invalidate()
        for (center, observer) in systemObservers {
            center.removeObserver(observer)
        }
    }

    private func observeUserPresence() {
        let workspace = NSWorkspace.shared.notificationCenter
        // Not in the SDK as constants, but posted by loginwindow since 10.x
        // and what every lock-aware Mac app listens for.
        let distributed = DistributedNotificationCenter.default()

        let transitions: [(NotificationCenter, Notification.Name, IdleReason, Bool)] = [
            (workspace, NSWorkspace.screensDidSleepNotification, .screensAsleep, true),
            (workspace, NSWorkspace.screensDidWakeNotification, .screensAsleep, false),
            (workspace, NSWorkspace.sessionDidResignActiveNotification, .sessionInactive, true),
            (workspace, NSWorkspace.sessionDidBecomeActiveNotification, .sessionInactive, false),
            (distributed, Notification.Name("com.apple.screenIsLocked"), .screenLocked, true),
            (distributed, Notification.Name("com.apple.screenIsUnlocked"), .screenLocked, false),
        ]
        for (center, name, reason, idle) in transitions {
            let observer = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.setIdle(reason, idle) }
            }
            systemObservers.append((center, observer))
        }

        // Servers started or stopped while asleep: don't show the pre-sleep
        // list for another full interval. A dark wake (Power Nap) leaves the
        // screens asleep, so this stays quiet then.
        let wake = workspace.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.idleReasons.isEmpty else { return }
                self.refresh()
            }
        }
        systemObservers.append((workspace, wake))
    }

    private func setIdle(_ reason: IdleReason, _ idle: Bool) {
        let wasIdle = !idleReasons.isEmpty
        if idle {
            idleReasons.insert(reason)
        } else {
            idleReasons.remove(reason)
        }
        let isIdle = !idleReasons.isEmpty
        guard wasIdle != isIdle else { return }
        scheduleRefreshTimer()
        // Back at the desk: the count may be minutes old.
        if !isIdle { refresh() }
    }

    /// Called when the popover opens or closes.
    func setMenuVisible(_ visible: Bool) {
        guard visible != isMenuVisible else { return }
        isMenuVisible = visible
        scheduleRefreshTimer()
        // Opening after up to 20 s of slow polling: show fresh data at once.
        if visible { refresh() }
    }

    private func scheduleRefreshTimer() {
        refreshTimer?.invalidate()
        refreshTimer = nil
        guard let interval = Self.refreshInterval(menuVisible: isMenuVisible, idle: !idleReasons.isEmpty) else {
            return
        }
        let timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                self.refresh()
            }
        }
        // Let macOS batch our wakeups with others; precision doesn't matter here.
        timer.tolerance = interval * 0.2
        refreshTimer = timer
    }

    // MARK: - Scanning

    /// - Parameter manual: user-triggered scans show progress; the background
    ///   poll must not flicker a spinner on every tick.
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
            let infos = await ProcessDetailsFetcher.fetch(for: pids)

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
                    binds: l.binds,
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
            try Actions.openURL(row.browserURL)
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
