import SwiftUI

/// Processes hidden via Ignore, with a way to bring each back.
struct IgnoredProcessesList: View {
    @EnvironmentObject private var store: PortsStore
    @EnvironmentObject private var ignoreStore: IgnoreStore

    var body: some View {
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
}
