import Foundation

struct Listener: Hashable {
    let port: Int
    let pid: Int
    let lsofCommand: String
    var binds: BindInfo
}

/// Address families a single (pid, port) is listening on, taken from lsof `n`.
///
/// IPv4 `127.0.0.1:4321` and IPv6 `[::1]:4321` are different sockets. Opening
/// `http://localhost:4321` typically hits IPv6, so an IPv4-only listener needs
/// `http://127.0.0.1:4321` or the click lands on a sibling process.
struct BindInfo: Hashable {
    var ipv4Hosts: Set<String>
    var ipv6Hosts: Set<String>

    /// Dual-stack loopback — the usual `localhost` case.
    static let localhost = BindInfo(ipv4Hosts: ["127.0.0.1"], ipv6Hosts: ["::1"])

    var hasIPv4: Bool { !ipv4Hosts.isEmpty }
    var hasIPv6: Bool { !ipv6Hosts.isEmpty }
    var isIPv4Only: Bool { hasIPv4 && !hasIPv6 }
    var isIPv6Only: Bool { hasIPv6 && !hasIPv4 }

    /// Host to put in `http://HOST:port` so the browser hits this socket.
    var openHost: String {
        isIPv4Only ? preferredIPv4Literal : "localhost"
    }

    func httpURL(port: Int) -> String {
        "http://\(openHost):\(port)"
    }

    mutating func merge(_ other: BindInfo) {
        ipv4Hosts.formUnion(other.ipv4Hosts)
        ipv6Hosts.formUnion(other.ipv6Hosts)
    }

    /// Classify the host part of an lsof name (`127.0.0.1:3000`, `[::1]:3333`).
    static func from(lsofName name: String) -> BindInfo {
        guard let host = LsofFParser.hostFromName(name) else { return .localhost }
        return from(host: host)
    }

    static func from(host raw: String) -> BindInfo {
        let host = raw.lowercased()
        if host == "localhost" {
            return .localhost
        }
        if host == "*" || host == "0.0.0.0" {
            return BindInfo(ipv4Hosts: [host], ipv6Hosts: [])
        }

        let unbracketed: String
        if host.hasPrefix("["), host.hasSuffix("]"), host.count >= 2 {
            unbracketed = String(host.dropFirst().dropLast())
        } else {
            unbracketed = host
        }

        if unbracketed == "::" || unbracketed == "::1" {
            return BindInfo(ipv4Hosts: [], ipv6Hosts: [unbracketed])
        }

        if let mapped = LsofFParser.ipv4MappedLoopback(unbracketed),
           LsofFParser.isIPv4Loopback(mapped) {
            return BindInfo(ipv4Hosts: [mapped], ipv6Hosts: [])
        }

        if LsofFParser.isIPv4Loopback(unbracketed) {
            return BindInfo(ipv4Hosts: [unbracketed], ipv6Hosts: [])
        }

        return .localhost
    }

    private var preferredIPv4Literal: String {
        ipv4Hosts.filter { $0.hasPrefix("127.") }.sorted().first ?? "127.0.0.1"
    }
}

private struct ListenerKey: Hashable {
    let port: Int
    let pid: Int
}

enum PortScannerError: LocalizedError {
    case lsofMissing(path: String)
    case lsofFailed(exitCode: Int32, message: String)
    case lsofUnlaunchable(reason: String)

    var errorDescription: String? {
        switch self {
        case .lsofMissing(let path):
            return "\(path) not found — Port Harbor needs lsof to list open ports."
        case .lsofFailed(let code, let message):
            return message.isEmpty
                ? "lsof exited with code \(code)."
                : "lsof failed (exit \(code)): \(message)"
        case .lsofUnlaunchable(let reason):
            return "Could not run lsof: \(reason)"
        }
    }

    /// The command a user can run in a terminal to reproduce the failure.
    var reproductionCommand: String { PortScanner.commandLine }
}

struct PortScanner {
    private static let lsofPath = "/usr/sbin/lsof"

    // -F pcnLP => machine-readable fields: pid/command/name/login/proto
    private static let arguments = ["-nP", "-iTCP", "-sTCP:LISTEN", "-F", "pcnLP"]

    static var commandLine: String {
        ([lsofPath] + arguments).joined(separator: " ")
    }

    /// Returns TCP LISTEN sockets reachable as `localhost:<port>` (IPv4/IPv6
    /// loopback and wildcard binds). LAN-only unicast addresses are excluded.
    ///
    /// Throws when the scan itself could not be performed, so that callers can
    /// tell "nothing is listening" apart from "we were unable to look".
    static func listLocalhostListeningTCPListeners() async throws -> [Listener] {
        try await Task.detached(priority: .utility) {
            try runLsof()
        }.value
    }

    private static func runLsof() throws -> [Listener] {
        guard FileManager.default.isExecutableFile(atPath: lsofPath) else {
            throw PortScannerError.lsofMissing(path: lsofPath)
        }

        let task = Process()
        task.executableURL = URL(fileURLWithPath: lsofPath)
        task.arguments = arguments

        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = pipe

        do {
            try task.run()
        } catch {
            throw PortScannerError.lsofUnlaunchable(reason: error.localizedDescription)
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        task.waitUntilExit()

        let output = String(data: data, encoding: .utf8) ?? ""
        let listeners = LsofFParser.parse(output: output)

        // lsof exits non-zero both when it finds nothing and when it hits a real
        // problem, and it keeps emitting records while warning about individual
        // processes it may not inspect. Only treat it as a failure when we got
        // no usable records *and* it had something to say.
        if task.terminationStatus != 0, listeners.isEmpty, !output.isEmpty {
            throw PortScannerError.lsofFailed(
                exitCode: task.terminationStatus,
                message: firstDiagnosticLine(in: output)
            )
        }

        return listeners
    }

    /// lsof's field output is one record per line prefixed by a field letter;
    /// anything else is human-readable diagnostics we can show the user.
    private static func firstDiagnosticLine(in output: String) -> String {
        let fieldPrefixes: Set<Character> = ["p", "c", "n", "L", "P", "f", "t"]
        for line in output.split(separator: "\n") {
            guard let first = line.first else { continue }
            if fieldPrefixes.contains(first), line.count > 1 { continue }
            return String(line).trimmingCharacters(in: .whitespaces)
        }
        return output
            .split(separator: "\n")
            .first
            .map { String($0).trimmingCharacters(in: .whitespaces) } ?? ""
    }
}

/// Parses `lsof -F pcnLP` output.
///
/// Format is one record per line:
/// - `p` => pid
/// - `c` => command (short, may be truncated by lsof)
/// - `n` => socket name, e.g. `127.0.0.1:3000`, `[::1]:3333`, `*:3000`
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
                guard isLocalhostReachable(name: value) else { continue }
                guard let port = portFromName(value) else { continue }

                // Skip ephemeral/OS-assigned ports
                guard port < ephemeralPortStart else { continue }

                // Skip known system processes
                guard !systemProcessDenylist.contains(command) else { continue }

                let key = ListenerKey(port: port, pid: pid)
                let binds = BindInfo.from(lsofName: value)
                if var existing = listenersByKey[key] {
                    existing.binds.merge(binds)
                    listenersByKey[key] = existing
                } else {
                    listenersByKey[key] = Listener(
                        port: port,
                        pid: pid,
                        lsofCommand: command,
                        binds: binds
                    )
                }
            default:
                break
            }
        }

        return listenersByKey.values.sorted { a, b in
            if a.port != b.port { return a.port < b.port }
            return a.pid < b.pid
        }
    }

    static func hostFromName(_ name: String) -> String? {
        guard let idx = name.lastIndex(of: ":") else { return nil }
        return String(name[..<idx])
    }

    private static func portFromName(_ name: String) -> Int? {
        guard let idx = name.lastIndex(of: ":") else { return nil }
        let portStr = name[name.index(after: idx)...]
        return Int(portStr)
    }

    /// True when the socket is loopback or wildcard — listed even if Open must
    /// use `127.0.0.1` rather than `localhost` to hit it.
    static func isLocalhostReachable(name: String) -> Bool {
        guard let host = hostFromName(name) else { return false }
        return isLocalhostHost(host)
    }

    private static func isLocalhostHost(_ raw: String) -> Bool {
        let host = raw.lowercased()
        if host == "*" || host == "0.0.0.0" || host == "localhost" { return true }

        let unbracketed: String
        if host.hasPrefix("["), host.hasSuffix("]"), host.count >= 2 {
            unbracketed = String(host.dropFirst().dropLast())
        } else {
            unbracketed = host
        }

        if unbracketed == "::" || unbracketed == "::1" { return true }

        if let mapped = ipv4MappedLoopback(unbracketed) {
            return isIPv4Loopback(mapped)
        }

        return isIPv4Loopback(unbracketed)
    }

    /// `127.0.0.0/8`
    static func isIPv4Loopback(_ host: String) -> Bool {
        let parts = host.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 4, let first = Int(parts[0]), first == 127 else { return false }
        return parts.dropFirst().allSatisfy { octet in
            guard let n = Int(octet) else { return false }
            return (0...255).contains(n)
        }
    }

    /// Returns the embedded IPv4 address for `::ffff:127.0.0.1`, else nil.
    static func ipv4MappedLoopback(_ host: String) -> String? {
        let prefix = "::ffff:"
        guard host.hasPrefix(prefix) else { return nil }
        return String(host.dropFirst(prefix.count))
    }
}

