import Foundation

/// Command line and working directory of a listening process.
///
/// Not called `ProcessInfo`: that would shadow `Foundation.ProcessInfo` across
/// the whole module.
struct ProcessDetails {
    let pid: Int
    let fullCommand: String
    let cwd: String?
}

enum ProcessDetailsFetcher {
    /// Two tool calls per scan regardless of how many servers are running:
    /// one `ps` for all command lines, one `lsof` for all working directories.
    static func fetch(for pids: [Int]) async -> [Int: ProcessDetails] {
        await Task.detached(priority: .utility) {
            let uniquePids = Array(Set(pids)).sorted()
            guard !uniquePids.isEmpty else { return [:] }

            let commands = fetchCommands(for: uniquePids)
            let cwds = fetchCwds(for: uniquePids)

            var result: [Int: ProcessDetails] = [:]
            for pid in uniquePids {
                result[pid] = ProcessDetails(pid: pid, fullCommand: commands[pid] ?? "", cwd: cwds[pid])
            }
            return result
        }.value
    }

    private static func fetchCommands(for pids: [Int]) -> [Int: String] {
        let pidList = pids.map(String.init).joined(separator: ",")
        let output = (try? Subprocess.run("/bin/ps", ["-p", pidList, "-o", "pid=,command="]))?.stdoutString ?? ""
        return parsePsCommands(output)
    }

    /// Parses `ps -o pid=,command=` lines: right-aligned PID, one space, then
    /// the command line verbatim (which may itself contain any spacing).
    static func parsePsCommands(_ output: String) -> [Int: String] {
        var commands: [Int: String] = [:]
        for line in output.split(separator: "\n") {
            let trimmed = line.drop { $0 == " " }
            let pidPart = trimmed.prefix { $0 != " " }
            guard let pid = Int(pidPart) else { continue }
            let command = trimmed.dropFirst(pidPart.count).dropFirst()
            commands[pid] = String(command).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return commands
    }

    /// Use `lsof -a -d cwd -p <pids>` to get the current working directory on macOS.
    /// macOS `ps` does not support the `cwd` keyword.
    private static func fetchCwds(for pids: [Int]) -> [Int: String] {
        let pidList = pids.map(String.init).joined(separator: ",")
        let output = (try? Subprocess.run("/usr/sbin/lsof", ["-a", "-d", "cwd", "-Fn", "-p", pidList]))?
            .stdoutString ?? ""

        var cwdMap: [Int: String] = [:]
        var currentPid: Int?
        for line in output.split(separator: "\n") {
            if line.hasPrefix("p") {
                currentPid = Int(line.dropFirst())
            } else if line.hasPrefix("n"), let pid = currentPid {
                cwdMap[pid] = String(line.dropFirst())
            }
        }
        return cwdMap
    }
}
