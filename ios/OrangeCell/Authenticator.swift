// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation
import LocalAuthentication

/// Who is allowed to change or clear a key: the person holding the unlocked phone, checked with Face ID or the
/// lock-screen passcode (Android asks for the device credential the same way). Only the app asks; the keyboard
/// extension reads keys silently, which is the Android behaviour too.
enum Authenticator {
    enum Outcome: Equatable {
        case verified
        /// No passcode is set: nothing to verify against.
        case unavailable
        case failed
    }

    static func verify(reason: String) async -> Outcome {
        #if targetEnvironment(simulator)
        // The CI simulator has no passcode; its tests ask for this explicitly. Never compiled for a device.
        if ProcessInfo.processInfo.arguments.contains("-OCSkipAuthentication") { return .verified }
        #endif
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else { return .unavailable }
        do {
            return try await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason) ? .verified : .failed
        } catch {
            return .failed
        }
    }
}
