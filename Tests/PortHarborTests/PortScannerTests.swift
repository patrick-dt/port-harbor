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
        n*:9999
        p333
        cfoo
        n[::1]:5432
        """

        let listeners = LsofFParser.parse(output: output)
        XCTAssertEqual(listeners.count, 2)
        XCTAssertTrue(listeners.contains { $0.pid == 111 && $0.port == 3000 })
        XCTAssertTrue(listeners.contains { $0.pid == 222 && $0.port == 5173 })
    }

    func testParser_ignoresNonLocalInterfaces() {
        let output = """
        p111
        cnode
        n*:3000
        p222
        cnode
        n127.0.0.2:5173
        """

        let listeners = LsofFParser.parse(output: output)
        XCTAssertEqual(listeners, [])
    }
}

