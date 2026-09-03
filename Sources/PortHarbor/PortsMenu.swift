import SwiftUI

// MARK: - Main Menu View

struct PortsMenu: View {
    @EnvironmentObject private var store: PortsStore
    @State private var pendingRestart: ListenerRow?
    @State private var hoveredButton: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 10)

            Divider()
                .padding(.horizontal, 12)

            if store.listeners.isEmpty {
                emptyState
            } else {
                ScrollView(.vertical, showsIndicators: true) {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(store.listeners) { row in
                            listenerCard(row)
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                }
                .frame(
                    minHeight: min(CGFloat(store.listeners.count) * 110, 420),
                    maxHeight: 420
                )
            }

            Divider()
                .padding(.horizontal, 12)

            footer
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
        }
        .frame(width: 380)
        .alert(
            "Restart process?",
            isPresented: Binding(
                get: { pendingRestart != nil },
                set: { if !$0 { pendingRestart = nil } }
            )
        ) {
            if let row = pendingRestart {
                Button("Restart", role: .destructive) {
                    store.restart(row)
                    pendingRestart = nil
                }
                Button("Cancel", role: .cancel) {
                    pendingRestart = nil
                }
            }
        } message: {
            if let row = pendingRestart {
                Text("PID \(row.pid) on port \(row.port)\n\(String(row.fullCommand.prefix(120)))")
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .center, spacing: 8) {
            Image(systemName: "network")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.primary)
            Text("Port Harbor")
                .font(.system(size: 13, weight: .semibold))
            Spacer()
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "antenna.radiowaves.left.and.right.slash")
                .font(.system(size: 28))
                .foregroundStyle(.tertiary)
            Text("No local servers running")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
    }

    // MARK: - Listener Card

    private func listenerCard(_ row: ListenerRow) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            // Title row: status dot + project name + settings icons
            HStack(alignment: .center, spacing: 8) {
                Circle()
                    .fill(.green)
                    .frame(width: 7, height: 7)

                Image(systemName: row.framework.iconName)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.primary)

                Text(row.displayTitle)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)

                Spacer()
            }

            // Subtitle: framework · command · PID
            Text(row.subtitle)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(1)

            // Action buttons
            HStack(spacing: 0) {
                actionButton(
                    id: "open-\(row.id)",
                    icon: "arrow.up.right.square",
                    label: "Open"
                ) {
                    store.openURL(for: row)
                }

                actionButton(
                    id: "cursor-\(row.id)",
                    icon: "cursorarrow",
                    label: "Cursor",
                    disabled: row.cwd == nil || row.cwd?.isEmpty == true
                ) {
                    store.openCursor(for: row)
                }

                actionButton(
                    id: "terminal-\(row.id)",
                    icon: "terminal",
                    label: "Terminal",
                    disabled: row.cwd == nil || row.cwd?.isEmpty == true
                ) {
                    store.openTerminal(for: row)
                }

                actionButton(
                    id: "restart-\(row.id)",
                    icon: "arrow.clockwise",
                    label: "Restart"
                ) {
                    pendingRestart = row
                }

                actionButton(
                    id: "stop-\(row.id)",
                    icon: "stop.circle",
                    label: "Stop",
                    tint: .red
                ) {
                    store.stop(row)
                }
            }
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
    }

    // MARK: - Action Button

    private func actionButton(
        id: String,
        icon: String,
        label: String,
        disabled: Bool = false,
        tint: Color? = nil,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            action()
        } label: {
            VStack(spacing: 3) {
                Image(systemName: icon)
                    .font(.system(size: 13))
                    .foregroundStyle(disabled ? Color.gray.opacity(0.35) : (tint ?? Color.primary))
                Text(label)
                    .font(.system(size: 10))
                    .foregroundStyle(disabled ? Color.gray.opacity(0.35) : (tint ?? Color.secondary))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .onHover { isHovered in
            hoveredButton = isHovered ? id : nil
        }
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(hoveredButton == id ? Color.primary.opacity(0.05) : Color.clear)
        )
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: 12) {
            // Server count
            HStack(spacing: 4) {
                Image(systemName: "server.rack")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                Text("\(store.listeners.count) server\(store.listeners.count == 1 ? "" : "s")")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                store.refresh()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 10))
                    Text("Refresh")
                        .font(.system(size: 11))
                }
                .foregroundStyle(.blue)
            }
            .buttonStyle(.plain)

            Button {
                NSApp.terminate(nil)
            } label: {
                Text("Quit")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
    }
}
