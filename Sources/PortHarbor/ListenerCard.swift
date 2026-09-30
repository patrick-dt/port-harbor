import AppKit
import SwiftUI

/// One listening process in the list: title, command, actions, and whatever
/// the app is currently doing to it.
struct ListenerCard: View {
    let row: ListenerRow
    /// Position in the list; the first nine get ⌘1–⌘9 on Open.
    let index: Int

    @EnvironmentObject private var store: PortsStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Inline confirmation instead of a modal alert: the popover can dismiss an
    /// alert out from under itself, and asking in place keeps the process the
    /// question is about on screen.
    @State private var pendingConfirmation: PendingAction?
    @State private var hoveredButton: String?

    private enum PendingAction: Equatable {
        case stop
        case restart
    }

    private var motion: Animation? {
        reduceMotion ? nil : .easeOut(duration: 0.18)
    }

    var body: some View {
        let activity = store.activity(for: row)
        let isGhost = store.isGhost(row)

        return VStack(alignment: .leading, spacing: 8) {
            titleRow(activity: activity, isGhost: isGhost)

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
                failureBanner(failure)
            }

            actionZone(activity: activity, isGhost: isGhost)
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
                Button("Copy Path") { copyToPasteboard(cwd) }
            }
            Button("Copy Command") { copyToPasteboard(Actions.pasteableShellCommand(row.fullCommand)) }
            Divider()
            Button("Ignore “\(row.processName)”") { store.ignore(row) }
            Divider()
            Button("Restart") { pendingConfirmation = .restart }
            Button("Stop") { requestStop() }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(rowAccessibilityLabel(activity: activity, isGhost: isGhost))
        .animation(motion, value: activity)
        .animation(motion, value: pendingConfirmation)
        // Closing the popover mid-hover produces no hover-exit event.
        .onDisappear { hoveredButton = nil }
    }

    private func titleRow(activity: RowActivity, isGhost: Bool) -> some View {
        HStack(alignment: .center, spacing: 6) {
            statusIndicator(activity: activity, isGhost: isGhost)

            if row.framework.hasBundledMark || row.framework.monogram != nil {
                FrameworkBadge(framework: row.framework)
            }

            Text(row.displayTitle)
                .font(.system(size: 13, weight: .semibold))
                .lineLimit(1)
                .truncationMode(.middle)

            // `verbatim` throughout: ports and PIDs are identifiers, and
            // localized number formatting would render 7265 as "7.265".
            Text(verbatim: row.portBadge)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.secondary)
                .layoutPriority(1)
                .help("Opens \(row.browserURL)")

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

    private func statusIndicator(activity: RowActivity, isGhost: Bool) -> some View {
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
                    : ("circle.fill", Palette.statusListening, "Listening on \(row.browserURL)")
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
    private func actionZone(activity: RowActivity, isGhost: Bool) -> some View {
        if let pending = pendingConfirmation {
            confirmationBar(action: pending)
        } else {
            switch activity {
            case .stopping:
                progressBar("Stopping \(row.displayTitle)…")
            case .restarting:
                progressBar("Restarting \(row.displayTitle)…")
            case .stopped:
                stoppedBar()
            case .idle:
                if isGhost {
                    stoppedBar()
                } else {
                    actionStrip()
                }
            }
        }
    }

    /// Five actions: Open / Cursor / Terminal sit together; Restart and Stop
    /// are set off because they change the process.
    private func actionStrip() -> some View {
        let hasDirectory = row.workingDirectory != nil

        return HStack(spacing: 4) {
            actionButton(
                id: "open-\(row.id)",
                icon: "arrow.up.right.square",
                label: "Open",
                hint: "Opens \(row.browserURL)",
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
                pendingConfirmation = .restart
            }

            actionButton(
                id: "stop-\(row.id)",
                icon: "stop.circle",
                label: "Stop",
                hint: "Sends SIGTERM to PID \(row.pid) (and its process group when it is the leader), then SIGKILL if it ignores it",
                accessibilityName: "Stop \(row.displayTitle)",
                tint: Palette.destructive
            ) {
                requestStop()
            }
        }
    }

    private func confirmationBar(action: PendingAction) -> some View {
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
                Button("Cancel") { pendingConfirmation = nil }
                    .controlSize(.small)
                    .keyboardShortcut(.cancelAction)
                Button(isStop ? "Stop" : "Restart") {
                    pendingConfirmation = nil
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

    private func stoppedBar() -> some View {
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

    private func failureBanner(_ failure: ActionFailure) -> some View {
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
                        Button("Copy command") { copyToPasteboard(command) }
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

    // MARK: - Helpers

    private func requestStop() {
        // Confirm only when we are not confident this is a dev server the user
        // started: the everyday case stays a single click.
        if row.needsStopConfirmation {
            pendingConfirmation = .stop
        } else {
            store.stop(row)
        }
    }

    private func rowAccessibilityLabel(activity: RowActivity, isGhost: Bool) -> String {
        var parts = [row.displayTitle, "port \(row.port)"]
        if row.binds.isIPv4Only {
            parts.append("IPv4 \(row.binds.openHost)")
        }
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
}
