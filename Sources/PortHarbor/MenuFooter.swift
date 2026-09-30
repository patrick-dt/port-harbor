import AppKit
import SwiftUI

/// Server count, ignore-list toggle, login item, Refresh and Quit.
struct MenuFooter: View {
    @Binding var showIgnoredList: Bool

    @EnvironmentObject private var store: PortsStore
    @EnvironmentObject private var ignoreStore: IgnoreStore
    @EnvironmentObject private var loginItem: LoginItem
    @State private var hoveredButton: String?

    var body: some View {
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

            if loginItem.isAvailable {
                loginItemToggle
            }

            footerButton(
                icon: "arrow.clockwise",
                label: "Refresh",
                tint: .accentColor,
                shortcut: "r",
                hint: "Rescan now (⌘R). Port Harbor also rescans every 3 seconds while this list is open."
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

    private var loginItemToggle: some View {
        let id = "loginItem"
        let hint = loginItem.lastError.map { "Couldn't change login item: \($0)" }
            ?? (loginItem.isEnabled
                ? "Port Harbor opens when you log in. Click to turn off."
                : "Open Port Harbor automatically when you log in.")
        return Button { loginItem.toggle() } label: {
            HStack(spacing: 3) {
                Image(systemName: loginItem.isEnabled ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 10))
                Text("At login")
                    .font(.system(size: 11))
            }
            .foregroundStyle(loginItem.lastError != nil ? AnyShapeStyle(Palette.destructive) : AnyShapeStyle(.secondary))
            .padding(.horizontal, 5)
            .padding(.vertical, 5)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(hoveredButton == id ? Color.primary.opacity(0.08) : .clear)
        )
        .onHover { hoveredButton = $0 ? id : nil }
        .onAppear { loginItem.refresh() }
        .help(hint)
        .accessibilityLabel("Open at login")
        .accessibilityValue(loginItem.isEnabled ? "On" : "Off")
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
}
