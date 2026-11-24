// SPDX-License-Identifier: GPL-3.0-or-later
import OCKeyboardUI

/// The extension's principal class (`NSExtensionPrincipalClass` must be in this
/// module). Everything lives in OCKeyboardUI so the simulator test host can run the
/// same keyboard in-process.
final class KeyboardViewController: OCKeyboardViewController {}
