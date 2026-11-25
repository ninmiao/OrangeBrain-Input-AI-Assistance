// SPDX-License-Identifier: GPL-3.0-or-later
import OCCore
import UIKit

extension TextTraits {
    /// Reads the traits of a text input (the document proxy, a text view).
    public init(_ traits: UITextInputTraits, hasText: Bool = true) {
        self.init()
        switch traits.keyboardType ?? .default {
        case .numberPad, .asciiCapableNumberPad: layout = .numberPad
        case .phonePad, .namePhonePad: layout = .phonePad
        case .decimalPad: layout = .decimalPad
        case .numbersAndPunctuation: layout = .numbersAndPunctuation
        case .emailAddress: layout = .email
        case .URL, .webSearch: layout = .url
        default: layout = .text
        }
        switch traits.autocapitalizationType ?? .sentences {
        case .none: capitalization = .none
        case .words: capitalization = .words
        case .allCharacters: capitalization = .allCharacters
        default: capitalization = .sentences
        }
        isSecure = traits.isSecureTextEntry ?? false
        if let type = traits.textContentType.flatMap({ $0 }) {
            hasSensitiveContentType = Self.sensitiveContentTypes.contains(type)
        }
        enablesReturnKeyAutomatically = traits.enablesReturnKeyAutomatically ?? false
        self.hasText = hasText
    }

    static let sensitiveContentTypes: Set<UITextContentType> = [
        .password, .newPassword, .oneTimeCode, .creditCardNumber, .creditCardSecurityCode, .creditCardExpiration,
        .creditCardExpirationMonth, .creditCardExpirationYear, .creditCardName, .creditCardGivenName,
        .creditCardMiddleName, .creditCardFamilyName,
    ]
}
