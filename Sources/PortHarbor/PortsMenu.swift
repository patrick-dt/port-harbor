import AppKit
import SwiftUI

// MARK: - Main Menu View

struct PortsMenu: View {
    @EnvironmentObject private var store: PortsStore
    /// Observed directly so the footer's ignore count and the ignore list stay
    /// in sync; changes here don't publish through `PortsStore`.
    @EnvironmentObject private var ignoreStore: IgnoreStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showIgnoredList = false

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
                IgnoredProcessesList()
            }

            Divider()
                .padding(.horizontal, 12)

            MenuFooter(showIgnoredList: $showIgnoredList)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
        }
        .frame(width: 380)
        .modifier(SolidWindowBackground())
        .background(PopoverVisibilityReporter { store.setMenuVisible($0) })
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
            Button("Copy") { copyToPasteboard(command) }
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
                    ListenerCard(row: row, index: index)
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
                Button("Copy command") { copyToPasteboard(command) }
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
}
