// SPDX-License-Identifier: GPL-3.0-or-later
import CNativeCore
import Foundation
import XCTest
@testable import OCCore

final class NativeCoreTests: XCTestCase {
    func testEncodeRoundTripThroughCApi() throws {
        let wire = try NativeCore.encode(input: "nihao", before: "previous")
        XCTAssertEqual(wire, ["i": "nihao", "b": "previous"])
        let full = try NativeCore.encode(input: "ni hao", before: "你好", after: "再见")
        XCTAssertEqual(full, ["i": "ni hao", "b": "你好", "a": "再见"])
    }

    func testSelfTestPasses() {
        XCTAssertTrue(NativeCore.selfTest())
    }

    func testRawInvokeMatchesTheDocumentedEnvelope() throws {
        let reply = NativeCore.invoke(#"{"op":"encode","args":{"input":"nihao"}}"#)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(reply.utf8)) as? [String: Any])
        XCTAssertEqual(object["ok"] as? String, #"{"i":"nihao"}"#)
    }

    func testErrorsComeBackAsNativeCoreError() {
        XCTAssertThrowsError(try NativeCore.encode(input: "   ")) { error in
            XCTAssertEqual((error as? NativeCoreError)?.message, "invalid")
        }
        XCTAssertThrowsError(try NativeCore.call(op: "does-not-exist")) { error in
            XCTAssertEqual((error as? NativeCoreError)?.message, "invalid")
        }
    }

    func testMalformedAndNullInputAreRejectedWithoutCrashing() throws {
        let broken = NativeCore.invoke("{not json")
        XCTAssertTrue(broken.contains("\"error\""))
        let none = try XCTUnwrap(oc_invoke(nil))
        XCTAssertEqual(String(cString: none), #"{"error":"invalid"}"#)
        oc_free(none)
        oc_free(nil)
    }

    func testDecodeKeepsCompleteCandidatesOfTruncatedOutput() throws {
        // Same cases as shared/native-core/tests/core_test.cpp.
        XCTAssertEqual(try NativeCore.decode(text: "[\"你好\"", truncated: true), ["你好"])
        XCTAssertEqual(try NativeCore.decode(text: "[\"你好\",", truncated: true), ["你好"])
        XCTAssertEqual(try NativeCore.decode(text: "[\"你好\",\"未完成", truncated: true), ["你好"])
        XCTAssertEqual(
            try NativeCore.decode(text: "[\"hello\",\"hello\"]", assistantEnabled: true),
            ["hello", "hello"]
        )
    }

    /// The corpus Android (JNI), the JVM tests and Windows already run: expected candidates
    /// when non-empty, a decode failure when empty. Read from the repository, not copied.
    func testSharedTruncationCorpus() throws {
        var root = URL(fileURLWithPath: #filePath)
        for _ in 0..<6 { root.deleteLastPathComponent() }   // NativeCoreTests.swift -> repository root
        let corpus = root.appendingPathComponent("tests/corpus/truncated-output.jsonl")
        let text = try String(contentsOf: corpus, encoding: .utf8)
        var count = 0
        for line in text.split(separator: "\n") where !line.isEmpty {
            let object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any], String(line))
            let input = try XCTUnwrap(object["text"] as? String)
            let truncated = try XCTUnwrap(object["truncated"] as? Bool)
            let expected = try XCTUnwrap(object["expected"] as? [String])
            if expected.isEmpty {
                XCTAssertThrowsError(try NativeCore.decode(text: input, truncated: truncated), String(line))
            } else {
                XCTAssertEqual(try NativeCore.decode(text: input, truncated: truncated), expected, String(line))
            }
            count += 1
        }
        XCTAssertGreaterThanOrEqual(count, 24, "the corpus shrank or was not found at \(corpus.path)")
    }

    func testReasoningTextIsNotAccepted() {
        XCTAssertThrowsError(
            try NativeCore.decode(text: "I think the answer is [\"hello\",\"hi\"]", assistantEnabled: true)
        )
    }

    func testLargeAndUnicodeInput() throws {
        let long = String(repeating: "你", count: 300)
        XCTAssertEqual(try NativeCore.encode(input: long)["i"], long)
        XCTAssertThrowsError(try NativeCore.encode(input: long + "多"))
    }
}
