import AppKit
import SwiftUI

// MARK: - Main Menu View

struct PortsMenu: View {
    @EnvironmentObject private var store: PortsStore
    /// Observed directly so the footer's ignore count and the ignore list stay
    /// in sync; changes here don't publish through `PortsStore`.
    @EnvironmentObject private var ignoreStore: IgnoreStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Inline confirmation, keyed by row. Replaces a modal alert: the popover
    /// can dismiss an alert out from under itself, and asking in place keeps
    /// the process the question is about on screen.
    @State private var pendingConfirmation: [String: PendingAction] = [:]
    @State private var hoveredButton: String?
    @State private var showIgnoredList = false

    private enum PendingAction: Equatable {
        case stop
        case restart
    }

    private let maxListHeight: CGFloat = 420

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 10)

            Divider()
                .padding(.horizontal, 12)

            content

            if showIgnoredList, !ignoreStore.ignoredNames.isEmpty {
                Divider()
                    .padding(.horizontal, 12)
                ignoredList
            }

            Divider()
                .padding(.horizontal, 12)

            footer
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
        }
        .frame(width: 380)
        .modifier(SolidWindowBackground())
        .animation(motion, value: showIgnoredList)
    }

    private var motion: Animation? {
        reduceMotion ? nil : .easeOut(duration: 0.18)
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .center, spacing: 8) {
            Image(systemName: "server.rack")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.primary)
            Text("Port Harbor")
                .font(.system(size: 13, weight: .semibold))
            Spacer()
            if store.isScanning {
                ProgressView()
                    .controlSize(.small)
                    .help("Scanning local ports…")
            }
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        switch store.scanState {
        case .failed(let message, let command) where store.displayRows.isEmpty:
            scanFailedState(message: message, command: command)
        case .failed(let message, let command):
            // We still have the last successful scan. Keep showing it rather
            // than replacing real information with an error screen.
            staleScanBanner(message: message, command: command)
            list
        case .scanning where store.displayRows.isEmpty:
            scanningState
        case .scanning, .loaded:
            if store.displayRows.isEmpty {
                emptyState
            } else {
                list
            }
        }
    }

    private func staleScanBanner(message: String, command: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 10))
                .foregroundStyle(Palette.destructive)
            Text("Showing the last successful scan — \(message)")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 4)
            Button("Copy") { copy(command) }
                .buttonStyle(.link)
                .font(.system(size: 10))
                .help(command)
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .accessibilityElement(children: .combine)
    }

    private var list: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(store.displayRows.enumerated()), id: \.element.id) { index, row in
                    listenerCard(row, index: index)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 8)
            .animation(motion, value: store.displayRows.map(\.id))
        }
        .scrollIndicators(.automatic)
        .frame(maxHeight: maxListHeight)
        .fixedSize(horizontal: false, vertical: true)
        .onHover { inside in
            // Hold scan results back while the pointer is in the list, so a row
            // never reorders under a click aimed at Stop.
            store.setPointerInside(inside)
        }
        .onDisappear {
            // Closing the popover with the pointer over the list produces no
            // hover-exit event; release the freeze explicitly.
            store.setPointerInside(false)
            hoveredButton = nil
        }
    }

    // MARK: - Placeholder states

    private var scanningState: some View {
        placeholder(icon: "antenna.radiowaves.left.and.right", title: "Scanning local ports…") {
            ProgressView()
                .controlSize(.small)
                .padding(.top, 2)
        }
    }

    private var emptyState: some View {
        placeholder(
            icon: "antenna.radiowaves.left.and.right.slash",
            title: "No local servers running"
        ) {
            Text("Start a dev server and it appears here within a few seconds.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 260)

            if !ignoreStore.ignoredNames.isEmpty {
                Button("Show \(ignoreStore.ignoredNames.count) ignored") {
                    showIgnoredList = true
                }
                .buttonStyle(.link)
                .font(.system(size: 11))
            }
        }
    }

    private func scanFailedState(message: String, command: String) -> some View {
        placeholder(icon: "exclamationmark.triangle.fill", title: "Couldn't scan ports", tint: Palette.destructive) {
            Text(message)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
                .frame(maxWidth: 300)

            HStack(spacing: 10) {
                Button("Try again") { store.refresh(manual: true) }
                    .controlSize(.small)
                Button("Copy command") { copy(command) }
                    .controlSize(.small)
                    .help(command)
            }
            .padding(.top, 2)
        }
    }

    private func placeholder<Content: View>(
        icon: String,
        title: String,
        tint: Color = .secondary,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 26))
                .foregroundStyle(tint == .secondary ? AnyShapeStyle(.tertiary) : AnyShapeStyle(tint))
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
            content()
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 20)
        .padding(.vertical, 28)
    }

    // MARK: - Listener Card

    private func listenerCard(_ row: ListenerRow, index: Int) -> some View {
        let activity = store.activity(for: row)
        let isGhost = store.isGhost(row)

        return VStack(alignment: .leading, spacing: 8) {
            titleRow(row, activity: activity, isGhost: isGhost)

            if !row.subtitle.isEmpty {
                Text(row.subtitle)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
                    .help(row.fullCommand)
            }

            if let failure = store.failure(for: row) {
                failureBanner(failure, row: row)
            }

            actionZone(row, index: index, activity: activity, isGhost: isGhost)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.06), lineWidth: 0.5)
        )
        .opacity(isGhost ? 0.6 : 1)
        .contextMenu {
            Button("Open in Browser") { store.openURL(for: row) }
            if let cwd = row.workingDirectory {
                Button("Open in Cursor") { store.openCursor(for: row) }
                Button("Open in Terminal") { store.openTerminal(for: row) }
                Divider()
                Button("Copy Path") { copy(cwd) }
            }
            Button("Copy Command") { copy(Actions.pasteableShellCommand(row.fullCommand)) }
            Divider()
            Button("Ignore “\(row.processName)”") { store.ignore(row) }
            Divider()
            Button("Restart") { pendingConfirmation[row.id] = .restart }
            Button("Stop") { requestStop(row) }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(accessibilityLabel(for: row, activity: activity, isGhost: isGhost))
        .animation(motion, value: activity)
        .animation(motion, value: pendingConfirmation[row.id])
    }

    private func titleRow(_ row: ListenerRow, activity: RowActivity, isGhost: Bool) -> some View {
        HStack(alignment: .center, spacing: 6) {
            statusIndicator(row, activity: activity, isGhost: isGhost)

            if row.framework.hasVectorMark
                || row.framework.rasterResourceName != nil
                || row.framework.monogram != nil
            {
                FrameworkBadge(framework: row.framework)
            }

            Text(row.displayTitle)
                .font(.system(size: 13, weight: .semibold))
                .lineLimit(1)
                .truncationMode(.middle)

            // `verbatim` throughout: ports and PIDs are identifiers, and
            // localized number formatting would render 7265 as "7.265".
            Text(verbatim: ":\(row.port)")
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.secondary)
                .layoutPriority(1)

            Spacer(minLength: 6)

            // The PID never truncates: it is the identifier the confirmations
            // and the copyable kill command refer to.
            Text(verbatim: "PID \(row.pid)")
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.tertiary)
                .layoutPriority(1)
                .help(String(format: "Process ID %d", row.pid))

            // Always present rather than hover-revealed: a reserved-but-empty
            // slot would jump on hover, and a hover-only control is invisible
            // to keyboard and VoiceOver users.
            if !isGhost {
                iconOnlyButton(
                    id: "ignore-\(row.id)",
                    icon: "eye.slash",
                    label: "Ignore “\(row.processName)”",
                    hint: "Hides every process named \(row.processName) from this list"
                ) {
                    store.ignore(row)
                }
            }
        }
    }

    private func statusIndicator(_ row: ListenerRow, activity: RowActivity, isGhost: Bool) -> some View {
        // Shape and tooltip carry the meaning as well as the hue, so the state
        // is not color-only, and the indicator reports something the row's mere
        // existence does not: what we are currently doing to it.
        let (icon, tint, text): (String, Color, String) = {
            switch activity {
            case .stopping:
                return ("circle.dotted", Palette.statusBusy, "Stopping…")
            case .restarting:
                return ("arrow.triangle.2.circlepath", Palette.statusBusy, "Restarting…")
            case .stopped:
                return ("circle", .secondary, "Stopped")
            case .idle:
                return isGhost
                    ? ("circle", .secondary, "Stopped")
                    : ("circle.fill", Palette.statusListening, "Listening on port \(row.port)")
            }
        }()

        return Image(systemName: icon)
            .font(.system(size: 9, weight: .bold))
            .foregroundStyle(tint)
            .frame(width: 10)
            .help(text)
            .accessibilityLabel(text)
    }

    // MARK: - Action zone

    @ViewBuilder
    private func actionZone(_ row: ListenerRow, index: Int, activity: RowActivity, isGhost: Bool) -> some View {
        if let pending = pendingConfirmation[row.id] {
            confirmationBar(row, action: pending)
        } else {
            switch activity {
            case .stopping:
                progressBar("Stopping \(row.displayTitle)…")
            case .restarting:
                progressBar("Restarting \(row.displayTitle)…")
            case .stopped:
                stoppedBar(row)
            case .idle:
                if isGhost {
                    stoppedBar(row)
                } else {
                    actionStrip(row, index: index)
                }
            }
        }
    }

    /// Five actions: Open / Cursor / Terminal sit together; Restart and Stop
    /// are set off because they change the process.
    private func actionStrip(_ row: ListenerRow, index: Int) -> some View {
        let hasDirectory = row.workingDirectory != nil

        return HStack(spacing: 4) {
            actionButton(
                id: "open-\(row.id)",
                icon: "arrow.up.right.square",
                label: "Open",
                hint: "Opens http://localhost:\(row.port)",
                accessibilityName: "Open \(row.displayTitle) in browser",
                shortcut: index < 9 ? Character("\(index + 1)") : nil
            ) {
                store.openURL(for: row)
            }

            actionButton(
                id: "cursor-\(row.id)",
                icon: "chevron.left.forwardslash.chevron.right",
                label: "Cursor",
                hint: hasDirectory
                    ? "Opens \(row.workingDirectory ?? "") in Cursor"
                    : "No working directory reported for this process",
                accessibilityName: "Open \(row.displayTitle) in Cursor",
                disabled: !hasDirectory
            ) {
                store.openCursor(for: row)
            }

            actionButton(
                id: "terminal-\(row.id)",
                icon: "terminal",
                label: "Terminal",
                hint: hasDirectory
                    ? "Opens a Terminal tab in \(row.workingDirectory ?? "")"
                    : "No working directory reported for this process",
                accessibilityName: "Open a Terminal tab for \(row.displayTitle)",
                disabled: !hasDirectory
            ) {
                store.openTerminal(for: row)
            }

            Spacer(minLength: 10)

            Divider()
                .frame(height: 26)

            actionButton(
                id: "restart-\(row.id)",
                icon: "arrow.clockwise",
                label: "Restart",
                hint: row.canRelaunch
                    ? "Stops PID \(row.pid) and runs its command again"
                    : "This command can't be relaunched automatically",
                accessibilityName: "Restart \(row.displayTitle)",
                disabled: !row.canRelaunch
            ) {
                pendingConfirmation[row.id] = .restart
            }

            actionButton(
                id: "stop-\(row.id)",
                icon: "stop.circle",
                label: "Stop",
                hint: "Sends SIGTERM to PID \(row.pid) (and its process group when it is the leader), then SIGKILL if it ignores it",
                accessibilityName: "Stop \(row.displayTitle)",
                tint: Palette.destructive
            ) {
                requestStop(row)
            }
        }
    }

    private func confirmationBar(_ row: ListenerRow, action: PendingAction) -> some View {
        let isStop = action == .stop
        let question = isStop
            ? "Stop \(row.displayTitle)? Unsaved in-memory state is lost."
            : "Restart \(row.displayTitle)? It is stopped, then started again."

        return VStack(alignment: .leading, spacing: 6) {
            Text(question)
                .font(.system(size: 11))
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)

            Text(FrameworkDetector.shortCommand(row.fullCommand))
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .help(row.fullCommand)

            HStack(spacing: 8) {
                Spacer()
                Button("Cancel") { pendingConfirmation[row.id] = nil }
                    .controlSize(.small)
                    .keyboardShortcut(.cancelAction)
                Button(isStop ? "Stop" : "Restart") {
                    pendingConfirmation[row.id] = nil
                    if isStop { store.stop(row) } else { store.restart(row) }
                }
                .controlSize(.small)
                .tint(Palette.destructive)
            }
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Palette.destructive.opacity(0.08))
        )
    }

    private func progressBar(_ label: String) -> some View {
        HStack(spacing: 8) {
            ProgressView()
                .controlSize(.small)
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            Spacer()
        }
        .frame(height: 38)
        .accessibilityLabel(label)
    }

    private func stoppedBar(_ row: ListenerRow) -> some View {
        HStack(spacing: 8) {
            Text("Stopped")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
            Spacer()
            if row.canRelaunch {
                Button("Undo") { store.undoStop(row) }
                    .controlSize(.small)
                    .help("Runs the original command again")
            }
            Button("Dismiss") { store.dismiss(row) }
                .controlSize(.small)
                .buttonStyle(.plain)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
        .frame(height: 38)
    }

    private func failureBanner(_ failure: ActionFailure, row: ListenerRow) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 10))
                .foregroundStyle(Palette.destructive)
                .padding(.top, 1)

            VStack(alignment: .leading, spacing: 4) {
                Text("\(failure.action) failed — \(failure.message)")
                    .font(.system(size: 11))
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)

                HStack(spacing: 10) {
                    if let command = failure.command {
                        Button("Copy command") { copy(command) }
                            .buttonStyle(.link)
                            .font(.system(size: 10))
                            .help(command)
                    }
                    Button("Dismiss") { store.dismiss(row) }
                        .buttonStyle(.link)
                        .font(.system(size: 10))
                }
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Palette.destructive.opacity(0.08))
        )
        .accessibilityElement(children: .combine)
    }

    // MARK: - Ignored list

    private var ignoredList: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Ignored processes")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Show all again") { ignoreStore.unignoreAll() }
                    .buttonStyle(.link)
                    .font(.system(size: 10))
            }

            ForEach(ignoreStore.ignoredNames, id: \.self) { name in
                HStack(spacing: 8) {
                    Image(systemName: "eye.slash")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                    Text(name)
                        .font(.system(size: 11, design: .monospaced))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer()
                    Button("Unignore") { store.unignore(name) }
                        .buttonStyle(.link)
                        .font(.system(size: 10))
                        .accessibilityLabel("Stop ignoring \(name)")
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: 12) {
            HStack(spacing: 4) {
                Image(systemName: "network")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                Text("\(store.listeners.count) server\(store.listeners.count == 1 ? "" : "s")")
                    .font(.system(size: 11))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)

            if !ignoreStore.ignoredNames.isEmpty {
                Button {
                    showIgnoredList.toggle()
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: "eye.slash")
                            .font(.system(size: 9))
                        Text("\(ignoreStore.ignoredNames.count) ignored")
                            .font(.system(size: 11))
                            .monospacedDigit()
                    }
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 3)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(showIgnoredList ? "Hide the ignore list" : "Manage ignored processes")
                .accessibilityLabel("\(ignoreStore.ignoredNames.count) ignored processes, manage")
            }

            Spacer()

            footerButton(
                icon: "arrow.clockwise",
                label: "Refresh",
                tint: .accentColor,
                shortcut: "r",
                hint: "Rescan now (⌘R). Port Harbor also rescans every 3 seconds."
            ) {
                store.refresh(manual: true)
            }

            footerButton(
                icon: nil,
                label: "Quit",
                tint: .secondary,
                shortcut: "q",
                hint: "Quit Port Harbor (⌘Q). Running servers are left alone."
            ) {
                NSApp.terminate(nil)
            }
        }
    }

    // MARK: - Buttons

    private func actionButton(
        id: String,
        icon: String,
        label: String,
        hint: String,
        accessibilityName: String,
        disabled: Bool = false,
        tint: Color? = nil,
        shortcut: Character? = nil,
        action: @escaping () -> Void
    ) -> some View {
        let foreground: AnyShapeStyle = disabled
            ? AnyShapeStyle(.tertiary)
            : AnyShapeStyle(tint ?? .primary)

        return Button(action: action) {
            VStack(spacing: 3) {
                Image(systemName: icon)
                    .font(.system(size: 13))
                Text(label)
                    .font(.system(size: 10, weight: .regular))
            }
            .foregroundStyle(foreground)
            .frame(minWidth: 54)
            .padding(.vertical, 7)
            .padding(.horizontal, 2)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(backgroundFill(id: id, disabled: disabled, tint: tint))
        )
        .onHover { hoveredButton = $0 ? id : nil }
        .modifier(OptionalShortcut(key: shortcut))
        .help(hint)
        .accessibilityLabel(accessibilityName)
        .accessibilityHint(hint)
    }

    private func backgroundFill(id: String, disabled: Bool, tint: Color?) -> Color {
        if disabled { return .clear }
        if hoveredButton == id {
            return (tint ?? .accentColor).opacity(0.16)
        }
        return .clear
    }

    private func iconOnlyButton(
        id: String,
        icon: String,
        label: String,
        hint: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 11))
                .foregroundStyle(hoveredButton == id ? AnyShapeStyle(.primary) : AnyShapeStyle(.tertiary))
                .frame(width: 26, height: 26)
                .background(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(hoveredButton == id ? Color.primary.opacity(0.08) : .clear)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hoveredButton = $0 ? id : nil }
        .help(hint)
        .accessibilityLabel(label)
        .accessibilityHint(hint)
    }

    private func footerButton(
        icon: String?,
        label: String,
        tint: Color,
        shortcut: Character,
        hint: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if let icon {
                    Image(systemName: icon)
                        .font(.system(size: 10))
                }
                Text(label)
                    .font(.system(size: 11))
            }
            .foregroundStyle(tint)
            .padding(.horizontal, 7)
            .padding(.vertical, 5)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(hoveredButton == label ? tint.opacity(0.12) : .clear)
        )
        .onHover { hoveredButton = $0 ? label : nil }
        .keyboardShortcut(KeyEquivalent(shortcut), modifiers: .command)
        .help(hint)
        .accessibilityLabel(label)
        .accessibilityHint(hint)
    }

    // MARK: - Helpers

    private func requestStop(_ row: ListenerRow) {
        // Confirm only when we are not confident this is a dev server the user
        // started: the everyday case stays a single click.
        if row.needsStopConfirmation {
            pendingConfirmation[row.id] = .stop
        } else {
            store.stop(row)
        }
    }

    private func accessibilityLabel(for row: ListenerRow, activity: RowActivity, isGhost: Bool) -> String {
        var parts = [row.displayTitle, "port \(row.port)"]
        if let framework = row.framework.label { parts.append(framework) }
        parts.append("PID \(row.pid)")
        switch activity {
        case .stopping: parts.append("stopping")
        case .restarting: parts.append("restarting")
        case .stopped: parts.append("stopped")
        case .idle: parts.append(isGhost ? "stopped" : "listening")
        }
        return parts.joined(separator: ", ")
    }

    private func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}

// MARK: - Support

/// Replaces the MenuBarExtra window's default glass/vibrancy with an opaque
/// system fill. `.containerBackground(..., for: .window)` owns the SwiftUI
/// chrome on macOS 15+; the AppKit hook is there because Tahoe still installs
/// an `NSVisualEffectView` (or `NSGlassEffectView`) behind the hosting view
/// unless the panel itself is marked opaque.
private struct SolidWindowBackground: ViewModifier {
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
private struct OptionalShortcut: ViewModifier {
    let key: Character?

    func body(content: Content) -> some View {
        if let key {
            content.keyboardShortcut(KeyEquivalent(key), modifiers: .command)
        } else {
            content
        }
    }
}

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
