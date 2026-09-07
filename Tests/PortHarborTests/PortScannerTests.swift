import XCTest
@testable import PortHarbor

final class PortScannerTests: XCTestCase {
    func testParser_extractsLocalhostListeners_andDedupes() {
        let output = """
        p111
        cnode
        n127.0.0.1:3000
        Ptcp
        p111
        cnode
        n127.0.0.1:3000
        p222
        cnext
        n127.0.0.1:5173
        n192.168.1.10:9999
        p333
        cfoo
        n10.0.0.1:5432
        """

        let listeners = LsofFParser.parse(output: output)
        XCTAssertEqual(listeners.count, 2)
        XCTAssertTrue(listeners.contains { $0.pid == 111 && $0.port == 3000 })
        XCTAssertTrue(listeners.contains { $0.pid == 222 && $0.port == 5173 })
    }

    func testParser_acceptsWildcardAndIPv6Loopback() {
        let output = """
        p111
        cnode
        n*:3000
        p222
        cvite
        n0.0.0.0:5173
        p333
        csanity
        n[::1]:3333
        p444
        cnuxt
        n[::]:8080
        p555
        cnode
        n127.0.0.2:4000
        p555
        cnode
        n[::1]:4000
        """

        let listeners = LsofFParser.parse(output: output)
        XCTAssertEqual(listeners.count, 5)
        XCTAssertTrue(listeners.contains { $0.pid == 111 && $0.port == 3000 })
        XCTAssertTrue(listeners.contains { $0.pid == 222 && $0.port == 5173 })
        XCTAssertTrue(listeners.contains { $0.pid == 333 && $0.port == 3333 })
        XCTAssertTrue(listeners.contains { $0.pid == 444 && $0.port == 8080 })
        XCTAssertTrue(listeners.contains { $0.pid == 555 && $0.port == 4000 })
    }

    func testParser_ignoresNonLocalInterfaces() {
        let output = """
        p111
        cnode
        n192.168.1.10:3000
        p222
        cnode
        n10.0.0.1:80
        """

        let listeners = LsofFParser.parse(output: output)
        XCTAssertEqual(listeners, [])
    }

    func testIsLocalhostReachable() {
        XCTAssertTrue(LsofFParser.isLocalhostReachable(name: "127.0.0.1:3000"))
        XCTAssertTrue(LsofFParser.isLocalhostReachable(name: "[::ffff:127.0.0.1]:3000"))
        XCTAssertTrue(LsofFParser.isLocalhostReachable(name: "localhost:3000"))
        XCTAssertFalse(LsofFParser.isLocalhostReachable(name: "8.8.8.8:53"))
        XCTAssertFalse(LsofFParser.isLocalhostReachable(name: "[fe80::1]:80"))
    }
}
