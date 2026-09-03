import Foundation

struct Listener: Hashable {
    let port: Int
    let pid: Int
    let lsofCommand: String
}

private struct ListenerKey: Hashable {
    let port: Int
    let pid: Int
}

enum PortScannerError: Error {
    case lsofFailed(exitCode: Int32)
}

struct PortScanner {
    /// Returns all TCP LISTEN sockets that are bound to `127.0.0.1:<port>`.
    static func listLocalhostListeningTCPListeners() async -> [Listener] {
        await Task.detached(priority: .utility) {
            do {
                let output = try runLsof()
                return LsofFParser.parse(output: output)
            } catch {
                return []
            }
        }.value
    }

    private static func runLsof() throws -> String {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/sbin/lsof")
        // -F pcnLP => machine-readable fields: pid/command/name/login/proto
        task.arguments = ["-nP", "-iTCP", "-sTCP:LISTEN", "-F", "pcnLP"]

        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = pipe

        try task.run()
        task.waitUntilExit()

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8) ?? ""

        guard task.terminationStatus == 0 else {
            throw PortScannerError.lsofFailed(exitCode: task.terminationStatus)
        }

        return output
    }
}

/// Parses `lsof -F pcnLP` output.
///
/// Format is one record per line:
/// - `p` => pid
/// - `c` => command (short, may be truncated by lsof)
/// - `n` => socket name, e.g. `127.0.0.1:3000`
struct LsofFParser {
    /// IANA dynamic/ephemeral port range start — these are OS-assigned internal ports.
    private static let ephemeralPortStart = 49152

    /// Known macOS system processes that are not dev servers.
    private static let systemProcessDenylist: Set<String> = [
        "rapportd", "ControlCenter", "ARDAgent", "sharingd",
        "AirPlayXPCHelper", "WiFiAgent", "UserEventAgent",
        "Cursor Helper (Plugin)", "cursorsandbox", "figma_agent",
        "OpenUsage", "Adobe Desktop Service", "Creative Cloud",
        "Google Chrome Helper", "firefox", "Safari",
        "Spotlight", "mDNSResponder", "httpd",
    ]

    static func parse(output: String) -> [Listener] {
        var pid: Int?
        var command: String?

        var listenersByKey: [ListenerKey: Listener] = [:]

        for rawLine in output.split(separator: "\n", omittingEmptySubsequences: true) {
            guard let first = rawLine.first else { continue }
            let value = String(rawLine.dropFirst())

            switch first {
            case "p":
                pid = Int(value)
            case "c":
                command = value
            case "n":
                guard let pid, let command else { continue }
                guard value.hasPrefix("127.0.0.1:") else { continue }
                guard let port = portFromName(value) else { continue }

                // Skip ephemeral/OS-assigned ports
                guard port < ephemeralPortStart else { continue }

                // Skip known system processes
                guard !systemProcessDenylist.contains(command) else { continue }

                let key = ListenerKey(port: port, pid: pid)
                listenersByKey[key] = Listener(port: port, pid: pid, lsofCommand: command)
            default:
                break
            }
        }

        return listenersByKey.values.sorted { a, b in
            if a.port != b.port { return a.port < b.port }
            return a.pid < b.pid
        }
    }

    private static func portFromName(_ name: String) -> Int? {
        guard let idx = name.lastIndex(of: ":") else { return nil }
        let portStr = name[name.index(after: idx)...]
        return Int(portStr)
    }
}

