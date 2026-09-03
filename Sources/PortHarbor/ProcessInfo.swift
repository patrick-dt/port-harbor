import Foundation

struct ProcessInfo {
    let pid: Int
    let fullCommand: String
    let cwd: String?
}

struct ProcessInfoFetcher {
    static func fetchProcessInfo(for pids: [Int]) async -> [Int: ProcessInfo] {
        await Task.detached(priority: .utility) {
            let uniquePids = Array(Set(pids)).sorted()
            let cwdMap = fetchCwds(for: uniquePids)

            var result: [Int: ProcessInfo] = [:]
            for pid in uniquePids {
                let command = runShell("/bin/ps", args: ["-p", "\(pid)", "-o", "command="])
                let cwd = cwdMap[pid]
                result[pid] = ProcessInfo(pid: pid, fullCommand: command, cwd: cwd)
            }
            return result
        }.value
    }

    /// Use `lsof -a -d cwd -p <pids>` to get the current working directory on macOS.
    /// macOS `ps` does not support the `cwd` keyword.
    private static func fetchCwds(for pids: [Int]) -> [Int: String] {
        guard !pids.isEmpty else { return [:] }
        let pidList = pids.map(String.init).joined(separator: ",")
        let output = runShell("/usr/sbin/lsof", args: ["-a", "-d", "cwd", "-Fn", "-p", pidList])

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

    private static func runShell(_ path: String, args: [String]) -> String {
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
        let output = String(data: data, encoding: .utf8) ?? ""
        return output.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

