import Foundation
import SwiftUI

/// User-managed list of process names that should never appear in the list.
///
/// Matching is on the short process name reported by `lsof` (its `c` field),
/// not on the port: ports move between runs, the binary does not.
@MainActor
final class IgnoreStore: ObservableObject {
    static let defaultsKey = "ignoredProcessNames"

    /// Names as the user saw them when they hit Ignore, for display.
    @Published private(set) var ignoredNames: [String] = []

    /// Case-folded mirror of `ignoredNames`, for matching.
    private var matchKeys: Set<String> = []

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let stored = (defaults.stringArray(forKey: Self.defaultsKey) ?? [])
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        apply(stored)
    }

    func isIgnored(_ name: String) -> Bool {
        matchKeys.contains(Self.matchKey(name))
    }

    func ignore(_ name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isIgnored(trimmed) else { return }
        apply(ignoredNames + [trimmed])
        persist()
    }

    func unignore(_ name: String) {
        let key = Self.matchKey(name)
        guard matchKeys.contains(key) else { return }
        apply(ignoredNames.filter { Self.matchKey($0) != key })
        persist()
    }

    func unignoreAll() {
        guard !ignoredNames.isEmpty else { return }
        apply([])
        persist()
    }

    private func apply(_ names: [String]) {
        ignoredNames = names.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
        matchKeys = Set(ignoredNames.map(Self.matchKey))
    }

    private func persist() {
        defaults.set(ignoredNames, forKey: Self.defaultsKey)
    }

    private static func matchKey(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}
