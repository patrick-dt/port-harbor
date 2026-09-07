import Foundation
import AppKit

enum ActionError: LocalizedError {
    case invalidCommand(reason: String)
    case appUnavailable(name: String, reason: String)
    case launchFailed(reason: String)
    case terminalScriptFailed(message: String)
    case notADirectory(path: String)
    case stopFailed(pid: Int, reason: String)
    case processSurvivedKill(pid: Int)

    var errorDescription: String? {
        switch self {
        case .invalidCommand(let reason):
            return "This process can't be relaunched: \(reason)"
        case .appUnavailable(let name, let reason):
            return reason.isEmpty ? "\(name) could not be opened." : "\(name): \(reason)"
        case .launchFailed(let reason):
            return "Relaunch failed: \(reason)"
        case .terminalScriptFailed(let message):
            return "Terminal could not be opened: \(message)"
        case .notADirectory(let path):
            return "No longer a directory: \(path)"
        case .stopFailed(let pid, let reason):
            return "Could not signal PID \(pid): \(reason)"
        case .processSurvivedKill(let pid):
            return "PID \(pid) ignored both SIGTERM and SIGKILL — it may belong to another user."
        }
    }
}

struct Actions {
    /// Runtimes and package managers that plausibly belong to a dev server the
    /// user started themselves. Used both for relaunch validation and to decide
    /// whether stopping a process needs an extra confirmation.
    static let knownDevBinaries: Set<String> = [
        "node", "npm", "npx", "yarn", "pnpm", "bun",
        "python", "python3", "ruby", "bundle",
        "php", "hugo", "next", "nuxt", "vite",
        "uvicorn", "gunicorn", "flask", "rails", "puma",
    ]

    @MainActor
    static func openURL(port: Int) throws {
        guard let url = URL(string: "http://localhost:\(port)") else {
            throw ActionError.invalidCommand(reason: "port \(port) is not a valid URL")
        }
        guard NSWorkspace.shared.open(url) else {
            throw ActionError.appUnavailable(
                name: "Browser",
                reason: "no application accepted http://localhost:\(port)"
            )
        }
    }

    static func openCursor(at cwd: String) throws {
        try openApp(named: "Cursor", withDirectory: cwd)
    }

    static func openApp(named app: String, withDirectory cwd: String) throws {
        try requireDirectory(cwd)

        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        task.arguments = ["-a", app, cwd]

        let errPipe = Pipe()
        task.standardOutput = FileHandle.nullDevice
        task.standardError = errPipe

        do {
            try task.run()
        } catch {
            throw ActionError.appUnavailable(name: app, reason: error.localizedDescription)
        }

        let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
        task.waitUntilExit()

        guard task.terminationStatus == 0 else {
            let message = String(data: errData, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            throw ActionError.appUnavailable(
                name: app,
                reason: message.isEmpty ? "open exited with code \(task.terminationStatus)" : message
            )
        }
    }

    static func openTerminal(at cwd: String) throws {
        // Validate that cwd is an existing directory to prevent injection
        // of crafted paths into AppleScript.
        try requireDirectory(cwd)

        // Use POSIX-quoted form via single-quote escaping for the shell command
        // inside AppleScript, and AppleScript-escape the outer string.
        let shellSafe = shellSingleQuoted(cwd)
        let escaped = appleScriptEscape(shellSafe)
        let script = """
        tell application "Terminal"
            activate
            do script "cd \(escaped)"
        end tell
        """

        var error: NSDictionary?
        let appleScript = NSAppleScript(source: script)
        appleScript?.executeAndReturnError(&error)

        if let error {
            let message = (error[NSAppleScript.errorMessage] as? String)
                ?? (error[NSAppleScript.errorBriefMessage] as? String)
                ?? "AppleScript error \(error[NSAppleScript.errorNumber] as? Int ?? -1)"
            throw ActionError.terminalScriptFailed(message: message)
        }
    }

    /// POSIX single-quoted string for paste-ready shell snippets and Terminal.
    static func shellSingleQuoted(_ s: String) -> String {
        "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    /// Rebuild `ps` output as a paste-safe argv line (each argument quoted).
    /// Prefer this over copying raw `ps` text, which a shell would re-expand.
    static func pasteableShellCommand(_ fullCommand: String) -> String {
        let args = splitCommandLine(fullCommand.trimmingCharacters(in: .whitespacesAndNewlines))
        guard !args.isEmpty else { return shellSingleQuoted(fullCommand) }
        return args.map(shellSingleQuoted).joined(separator: " ")
    }

    static func stop(pid: Int, expectedCommand: String? = nil, signal: Int32 = SIGTERM) throws {
        // Re-check identity before signaling so a recycled PID during the list
        // freeze cannot stop an unrelated same-user process.
        if let expectedCommand {
            try verifyProcessIdentity(pid: pid, expectedCommand: expectedCommand)
        }

        let pgid = processGroupID(for: pid)

        // SIGTERM -> grace -> (group SIGTERM if leader) -> SIGKILL fallback.
        try kill(pid: pid, signal: signal)
        Thread.sleep(forTimeInterval: 0.7)

        guard isProcessAlive(pid) else { return }

        // Only escalate to the process group when this PID is the leader, so we
        // tear down npm/yarn wrapper trees without signaling an unrelated shared group.
        if let pgid, pgid == pid {
            try? kill(processGroup: pgid, signal: SIGTERM)
            Thread.sleep(forTimeInterval: 0.25)
            guard isProcessAlive(pid) else { return }
        }

        try kill(pid: pid, signal: SIGKILL)
        Thread.sleep(forTimeInterval: 0.2)

        if isProcessAlive(pid), let pgid, pgid == pid {
            try? kill(processGroup: pgid, signal: SIGKILL)
            Thread.sleep(forTimeInterval: 0.15)
        }

        if isProcessAlive(pid) {
            throw ActionError.processSurvivedKill(pid: pid)
        }
    }

    static func restart(
        pid: Int,
        fullCommand: String,
        cwd: String?
    ) throws {
        // Validate *before* killing, so a command we can't relaunch never
        // turns a restart into a silent stop.
        let args = try relaunchArguments(fullCommand: fullCommand)
        try stop(pid: pid, expectedCommand: fullCommand, signal: SIGTERM)
        try launch(arguments: args, cwd: cwd)
    }

    /// Relaunch a process we previously stopped. Unlike `restart` this never
    /// signals anything, so it is safe to call on a PID that is already gone.
    static func relaunch(fullCommand: String, cwd: String?) throws {
        try launch(arguments: relaunchArguments(fullCommand: fullCommand), cwd: cwd)
    }

    /// Whether `relaunch` has a chance of succeeding. Lets the UI disable Undo
    /// instead of offering a button that always fails.
    static func canRelaunch(fullCommand: String) -> Bool {
        (try? relaunchArguments(fullCommand: fullCommand)) != nil
    }

    /// Whether the command looks like a dev server the user started, as opposed
    /// to an app or system service that merely happens to hold a local port.
    static func isKnownDevBinary(fullCommand: String) -> Bool {
        let firstArg = fullCommand
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: " ")
            .first ?? ""
        return knownDevBinaries.contains(URL(fileURLWithPath: firstArg).lastPathComponent)
    }

    /// Validates the command and resolves it to an argv array without running it.
    private static func relaunchArguments(fullCommand: String) throws -> [String] {
        let command = fullCommand.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !command.isEmpty else {
            throw ActionError.invalidCommand(reason: "no command line was reported by ps")
        }

        // Validate that the command looks like an executable path or known tool,
        // not something with shell metacharacters that could be exploited.
        let dangerousChars = CharacterSet(charactersIn: ";|&$`\\!{}<>")
        let firstArg = command.components(separatedBy: " ").first ?? ""
        let baseName = URL(fileURLWithPath: firstArg).lastPathComponent
        guard !baseName.isEmpty else {
            throw ActionError.invalidCommand(reason: "the command line has no executable")
        }

        // Relaunch always uses Process argv (no shell), so metacharacters in
        // arguments are literals. Still reject them for unknown binaries as
        // defense-in-depth against odd `ps` lines we fail to tokenize cleanly.
        // Known shells may carry `-c '…'` payloads; knownDevBinaries are the
        // everyday npm/node/python cases. Absolute system prefixes alone are
        // not enough to skip the filter.
        let isShell = ["sh", "bash", "zsh", "dash"].contains(baseName)
        let mayContainMetacharacters = knownDevBinaries.contains(baseName) || isShell

        if !mayContainMetacharacters {
            guard command.unicodeScalars.allSatisfy({ !dangerousChars.contains($0) }) else {
                throw ActionError.invalidCommand(
                    reason: "it contains shell metacharacters and \(baseName) is not a known dev binary"
                )
            }
        }

        // Launch the process directly with argument splitting instead of passing
        // through a shell, which avoids shell injection entirely.
        let args = splitCommandLine(command)
        guard !args.isEmpty, args[0].hasPrefix("/") else {
            throw ActionError.invalidCommand(reason: "could not resolve \(baseName) to an absolute path")
        }
        return args
    }

    private static func launch(arguments args: [String], cwd: String?) throws {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: args[0])
        task.arguments = Array(args.dropFirst())

        if let cwd, !cwd.isEmpty, FileManager.default.fileExists(atPath: cwd) {
            task.currentDirectoryURL = URL(fileURLWithPath: cwd)
        }

        do {
            try task.run()
        } catch {
            throw ActionError.launchFailed(reason: error.localizedDescription)
        }
    }

    private static func requireDirectory(_ path: String) throws {
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDir), isDir.boolValue else {
            throw ActionError.notADirectory(path: path)
        }
    }

    /// Splits a command string into arguments, respecting single and double quotes.
    static func splitCommandLine(_ command: String) -> [String] {
        var args: [String] = []
        var current = ""
        var inSingle = false
        var inDouble = false
        var escaped = false

        for ch in command {
            if escaped {
                current.append(ch)
                escaped = false
                continue
            }
            if ch == "\\" && !inSingle {
                escaped = true
                continue
            }
            if ch == "'" && !inDouble {
                inSingle.toggle()
                continue
            }
            if ch == "\"" && !inSingle {
                inDouble.toggle()
                continue
            }
            if ch == " " && !inSingle && !inDouble {
                if !current.isEmpty {
                    args.append(current)
                    current = ""
                }
                continue
            }
            current.append(ch)
        }
        if !current.isEmpty {
            args.append(current)
        }

        // Resolve the executable: if it's not an absolute path, try to find it.
        if let first = args.first, !first.hasPrefix("/") {
            if let resolved = resolveExecutable(first) {
                args[0] = resolved
            }
        }

        return args
    }

    /// Look up a command name on disk. Must not spawn a process: `canRelaunch`
    /// is read from SwiftUI layout, and `which` + `waitUntilExit` on the main
    /// thread is an AttributeGraph abort on macOS 26.
    private static let executableCacheLock = NSLock()
    private static var executableCache: [String: String] = [:]

    private static let searchPath: [String] = {
        var dirs: [String] = []
        let env = Foundation.ProcessInfo.processInfo.environment["PATH"] ?? ""
        dirs.append(contentsOf: env.split(separator: ":").map(String.init))
        // Menu-bar apps launched from Finder often have a stripped PATH that
        // omits Homebrew; still look there so `node` / `npm` can relaunch.
        for extra in ["/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/bin"] {
            if !dirs.contains(extra) { dirs.append(extra) }
        }
        return dirs
    }()

    private static func resolveExecutable(_ name: String) -> String? {
        guard !name.isEmpty, !name.contains("/"), name != "." && name != ".." else {
            return nil
        }

        executableCacheLock.lock()
        if let cached = executableCache[name] {
            executableCacheLock.unlock()
            return cached
        }
        executableCacheLock.unlock()

        let fm = FileManager.default
        var resolved: String?
        for dir in searchPath {
            let candidate = (dir as NSString).appendingPathComponent(name)
            if fm.isExecutableFile(atPath: candidate) {
                resolved = candidate
                break
            }
        }

        executableCacheLock.lock()
        if let resolved {
            executableCache[name] = resolved
        }
        executableCacheLock.unlock()
        return resolved
    }

    private static func kill(pid: Int, signal: Int32) throws {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/kill")
        task.arguments = ["-\(signal)", "\(pid)"]

        let errPipe = Pipe()
        task.standardOutput = FileHandle.nullDevice
        task.standardError = errPipe

        do {
            try task.run()
        } catch {
            throw ActionError.stopFailed(pid: pid, reason: error.localizedDescription)
        }

        let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
        task.waitUntilExit()

        // A process that exited between the scan and the signal is a success,
        // not a failure: the user wanted it gone and it is gone.
        guard task.terminationStatus != 0, isProcessAlive(pid) else { return }

        let message = String(data: errData, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        throw ActionError.stopFailed(
            pid: pid,
            reason: message.isEmpty ? "kill exited with code \(task.terminationStatus)" : message
        )
    }

    private static func kill(processGroup pgid: Int, signal: Int32) throws {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/kill")
        // Negative PID form targets the process group.
        task.arguments = ["-\(signal)", "-\(pgid)"]
        task.standardOutput = FileHandle.nullDevice
        task.standardError = FileHandle.nullDevice
        try task.run()
        task.waitUntilExit()
    }

    private static func isProcessAlive(_ pid: Int) -> Bool {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/kill")
        task.arguments = ["-0", "\(pid)"]
        do {
            try task.run()
            task.waitUntilExit()
            return task.terminationStatus == 0
        } catch {
            return false
        }
    }

    private static func processGroupID(for pid: Int) -> Int? {
        let output = runCapture("/bin/ps", args: ["-p", "\(pid)", "-o", "pgid="])
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        return Int(trimmed)
    }

    private static func verifyProcessIdentity(pid: Int, expectedCommand: String) throws {
        let current = runCapture("/bin/ps", args: ["-p", "\(pid)", "-o", "command="])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !current.isEmpty else {
            // Already gone — stop is a success for the caller's purposes.
            return
        }

        let expectedKey = identityKey(for: expectedCommand)
        let currentKey = identityKey(for: current)
        guard expectedKey == currentKey else {
            throw ActionError.stopFailed(
                pid: pid,
                reason: "PID \(pid) now runs “\(shortIdentity(current))”, not “\(shortIdentity(expectedCommand))” — refusing to signal a recycled PID"
            )
        }
    }

    /// Compare executable basename + first meaningful argument so minor ps
    /// truncation differences do not block a legitimate stop.
    static func identityKey(for command: String) -> String {
        let parts = splitCommandLine(command.trimmingCharacters(in: .whitespacesAndNewlines))
        let exe = parts.first.map { URL(fileURLWithPath: $0).lastPathComponent.lowercased() } ?? ""
        let arg1 = parts.dropFirst().first.map { URL(fileURLWithPath: $0).lastPathComponent.lowercased() } ?? ""
        return "\(exe)\0\(arg1)"
    }

    private static func shortIdentity(_ command: String) -> String {
        let parts = splitCommandLine(command)
        let exe = parts.first.map { URL(fileURLWithPath: $0).lastPathComponent } ?? "?"
        if let arg1 = parts.dropFirst().first {
            return "\(exe) \(URL(fileURLWithPath: arg1).lastPathComponent)"
        }
        return exe
    }

    private static func runCapture(_ path: String, args: [String]) -> String {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: path)
        task.arguments = args
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = FileHandle.nullDevice
        do {
            try task.run()
            task.waitUntilExit()
        } catch {
            return ""
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8) ?? ""
    }

    private static func appleScriptEscape(_ s: String) -> String {
        // Escapes for AppleScript string literals inside `do script "..."`.
        s.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }
}

