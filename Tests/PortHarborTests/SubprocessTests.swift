import XCTest
@testable import PortHarbor

final class SubprocessTests: XCTestCase {
    func testRun_capturesStdoutAndStatus() throws {
        let result = try Subprocess.run("/bin/echo", ["hello"])
        XCTAssertEqual(result.status, 0)
        XCTAssertEqual(result.stdoutString, "hello\n")
    }

    /// Output larger than a pipe buffer used to deadlock when the caller waited
    /// for exit before reading.
    func testRun_drainsOutputLargerThanPipeBuffer() throws {
        let result = try Subprocess.run("/usr/bin/head", ["-c", "300000", "/dev/zero"])
        XCTAssertEqual(result.status, 0)
        XCTAssertEqual(result.stdout.count, 300_000)
    }

    func testRun_timesOutInsteadOfHanging() {
        let start = Date()
        XCTAssertThrowsError(try Subprocess.run("/bin/sleep", ["10"], timeout: 0.3)) { error in
            XCTAssertEqual(error as? Subprocess.Failure, .timedOut(seconds: 0.3))
        }
        XCTAssertLessThan(Date().timeIntervalSince(start), 3)
    }

    func testRun_reportsUnlaunchableExecutable() {
        XCTAssertThrowsError(try Subprocess.run("/nonexistent/tool", [])) { error in
            guard case .unlaunchable = error as? Subprocess.Failure else {
                return XCTFail("expected .unlaunchable, got \(error)")
            }
        }
    }

    func testParsePsCommands_handlesPaddingAndSpacesInCommand() {
        let output = """
          123 /usr/local/bin/node  server.js --port 3000
        45678 /opt/homebrew/bin/python3 -m http.server
          999
        not-a-pid junk
        """
        let commands = ProcessDetailsFetcher.parsePsCommands(output)
        XCTAssertEqual(commands[123], "/usr/local/bin/node  server.js --port 3000")
        XCTAssertEqual(commands[45678], "/opt/homebrew/bin/python3 -m http.server")
        XCTAssertEqual(commands[999], "")
        XCTAssertEqual(commands.count, 3)
    }
}
