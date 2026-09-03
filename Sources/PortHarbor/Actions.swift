import Foundation
import AppKit

enum ActionError: Error {
    case invalidCommand
}

struct Actions {
    @MainActor
    static func openURL(port: Int) {
        guard let url = URL(string: "http://127.0.0.1:\(port)") else { return }
        NSWorkspace.shared.open(url)
    }

    static func openCursor(at cwd: String) {
        // Best-effort: Cursor needs to exist, and it must accept folder args.
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        task.arguments = ["-a", "Cursor", cwd]
        do {
            try task.run()
        } catch {
            // ignore (best-effort)
        }
    }

    static func openTerminal(at cwd: String) {
        // Validate that cwd is an existing directory to prevent injection
        // of crafted paths into AppleScript.
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: cwd, isDirectory: &isDir),
              isDir.boolValue else { return }

        // Use POSIX-quoted form via single-quote escaping for the shell command
        // inside AppleScript, and AppleScript-escape the outer string.
        let shellSafe = singleQuoteShellEscape(cwd)
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
    }

    static func stop(pid: Int, signal: Int32 = SIGTERM) {
        // SIGTERM -> short wait -> SIGKILL fallback.
        kill(pid: pid, signal: signal)
        Thread.sleep(forTimeInterval: 0.4)

        if isProcessAlive(pid) {
            kill(pid: pid, signal: SIGKILL)
        }
    }

    static func restart(
        pid: Int,
        fullCommand: String,
        cwd: String?
    ) throws {
        let command = fullCommand.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !command.isEmpty else { throw ActionError.invalidCommand }

        // Validate that the command looks like an executable path or known tool,
        // not something with shell metacharacters that could be exploited.
        let dangerousChars = CharacterSet(charactersIn: ";|&$`\\!{}<>")
        let firstArg = command.components(separatedBy: " ").first ?? ""
        let baseName = URL(fileURLWithPath: firstArg).lastPathComponent
        guard !baseName.isEmpty else { throw ActionError.invalidCommand }

        // Block commands that contain shell metacharacters outside of known safe patterns.
        // Allow common package managers and runtimes that may appear in ps output.
        let allowedBinaries: Set<String> = [
            "node", "npm", "npx", "yarn", "pnpm", "bun",
            "python", "python3", "ruby", "bundle",
            "php", "hugo", "next", "nuxt", "vite",
            "uvicorn", "gunicorn", "flask", "rails", "puma",
        ]
        let isTrustedBinary = allowedBinaries.contains(baseName)
            || firstArg.hasPrefix("/usr/")
            || firstArg.hasPrefix("/bin/")
            || firstArg.hasPrefix("/opt/homebrew/")

        // If the binary isn't in our allowlist, reject commands with shell metacharacters.
        if !isTrustedBinary {
            guard command.unicodeScalars.allSatisfy({ !dangerousChars.contains($0) }) else {
                throw ActionError.invalidCommand
            }
        }

        stop(pid: pid, signal: SIGTERM)

        // Launch the process directly with argument splitting instead of passing
        // through a shell, which avoids shell injection entirely.
        let args = splitCommandLine(command)
        guard !args.isEmpty else { throw ActionError.invalidCommand }

        let task = Process()
        task.executableURL = URL(fileURLWithPath: args[0])
        task.arguments = Array(args.dropFirst())

        if let cwd, !cwd.isEmpty {
            task.currentDirectoryURL = URL(fileURLWithPath: cwd)
        }

        try task.run()
    }

    /// Splits a command string into arguments, respecting single and double quotes.
    private static func splitCommandLine(_ command: String) -> [String] {
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

    /// Best-effort resolution of a command name to an absolute path via /usr/bin/which.
    private static func resolveExecutable(_ name: String) -> String? {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        task.arguments = [name]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = FileHandle.nullDevice
        do {
            try task.run()
            task.waitUntilExit()
        } catch { return nil }
        guard task.terminationStatus == 0 else { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let path = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return (path?.isEmpty == false) ? path : nil
    }

    private static func kill(pid: Int, signal: Int32) {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/kill")
        task.arguments = ["-\(signal)", "\(pid)"]
        do {
            try task.run()
            task.waitUntilExit()
        } catch {
            // ignore best-effort failures
        }
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

    private static func appleScriptEscape(_ s: String) -> String {
        // Escapes for AppleScript string literals inside `do script "..."`.
        s.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }

    private static func singleQuoteShellEscape(_ s: String) -> String {
        // Escapes for: cd '<cwd>'; ...
        // ' -> '\'' sequence in POSIX shell.
        "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}

