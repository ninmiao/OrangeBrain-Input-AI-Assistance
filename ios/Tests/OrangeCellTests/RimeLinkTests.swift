// SPDX-License-Identifier: GPL-3.0-or-later
import OCCore
import OCRime
import XCTest

/// Test results the CI summary needs: printed, and appended to the file named by
/// OC_INFO_FILE (xcodebuild is started with TEST_RUNNER_OC_INFO_FILE).
func ocInfo(_ line: String) {
    print("OCINFO " + line)
    guard let path = ProcessInfo.processInfo.environment["OC_INFO_FILE"], !path.isEmpty else { return }
    let data = Data(("OCINFO " + line + "\n").utf8)
    if let handle = FileHandle(forWritingAtPath: path) {
        handle.seekToEndOfFile()
        handle.write(data)
        try? handle.close()
    } else {
        FileManager.default.createFile(atPath: path, contents: data)
    }
}

/// Checks, inside a simulator process, that the prebuilt librime is linked the
/// way the plan assumes: right version, plugin modules not dead-stripped, and
/// setup / initialize / finalize run.
final class RimeLinkTests: XCTestCase {
    /// One start/stop per process: glog and the module registry are process-global.
    private static let probe: RimeProbeResult = {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("oc-rime-link-\(ProcessInfo.processInfo.processIdentifier)", isDirectory: true)
        return RimeProbe.run(workingDirectory: directory)
    }()

    private func report(_ result: RimeProbeResult) {
        // Picked up by ios/scripts/ci_summary.py from the xcodebuild log.
        ocInfo("librime.version=\(result.version ?? "nil")")
        ocInfo("librime.modules.beforeStart=\(result.modulesBeforeStart.joined(separator: ","))")
        ocInfo("librime.modules.afterStart=\(result.modulesAfterStart.joined(separator: ","))")
        ocInfo("librime.started=\(result.started)")
        ocInfo("librime.missingRequired=\(result.missingRequired.joined(separator: ","))")
    }

    func testVersionMatchesTheLockedBuild() throws {
        let result = Self.probe
        report(result)
        let version = try XCTUnwrap(result.version)
        XCTAssertTrue(version.hasPrefix("1.17"), "unexpected librime \(version)")
    }

    func testRequiredPluginModulesSurviveLinking() {
        let result = Self.probe
        XCTAssertEqual(result.missingRequired, [], "modules dead-stripped: \(result.missingRequired)")
        for name in RimeEngine.requiredModules {
            XCTAssertTrue(RimeEngine.isModuleRegistered(name) || result.modules.contains(name), "\(name) not registered")
        }
    }

    func testSetupInitializeFinalizeRan() {
        let result = Self.probe
        XCTAssertTrue(result.started, "initialize failed: \(result.error ?? "-")")
        XCTAssertNil(result.error)
    }

    func testNativeCoreRoundTripInTheSameProcess() throws {
        XCTAssertTrue(NativeCore.selfTest())
        let wire = try NativeCore.encode(input: "nihao", before: "previous")
        XCTAssertEqual(wire, ["i": "nihao", "b": "previous"])
        ocInfo("oc_core.encode=\(wire)")
    }

    func testAppGroupLocatorWithoutProfileUsesNominalName() {
        let context = AppGroupContext.detect(bundle: .main)
        // A simulator test runner carries no embedded.mobileprovision.
        XCTAssertNil(context.profile)
        XCTAssertEqual(context.resolution.identifier, AppGroupLocator.nominalGroup)
        ocInfo("appgroup.source=\(context.resolution.source.rawValue) container=\(context.containerURL?.path ?? "nil")")
    }

    func testMemoryProbeIsAvailable() throws {
        let megabytes = try XCTUnwrap(MemoryProbe.physFootprintMB())
        ocInfo("test.footprintMB=\(megabytes)")
        XCTAssertGreaterThan(megabytes, 1)
    }
}
