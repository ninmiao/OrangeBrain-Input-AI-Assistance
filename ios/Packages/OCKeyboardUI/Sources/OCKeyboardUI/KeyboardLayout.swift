// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation

public enum InputMode: Equatable {
    case chinese   // 中: letters go to Rime, `ascii_mode` off
    case english   // EN: letters are inserted directly, `ascii_mode` on
}

public enum Panel: Equatable {
    case letters, numbers, symbols
}

public enum ShiftState: Equatable {
    case off, once, locked
}

enum KeyAction: Equatable {
    case character(String)
    case space
    case enter
    case delete
    case shift
    case panel(Panel)
    case language
    case globe
}

enum KeyStyle: Equatable {
    case normal      // white letter key
    case modifier    // grey function key
    case accent      // orange (return key when it triggers an action)
}

struct KeySpec: Equatable {
    let id: String
    let action: KeyAction
    let title: String
    let weight: CGFloat
    let style: KeyStyle
}

enum RowItem {
    case key(KeySpec)
    case spacer(CGFloat)

    var weight: CGFloat {
        switch self {
        case .key(let spec): return spec.weight
        case .spacer(let weight): return weight
        }
    }
}

/// The key rows for a panel. Weights are relative widths like in the Android theme
/// (letters 10, shift / delete 15, a half-width spacer 5), so the layout adapts to any width.
struct KeyboardLayout {
    let panel: Panel
    let mode: InputMode
    let shift: ShiftState
    let returnKind: ReturnKeyKind
    let showGlobe: Bool
    /// The 1-0 row above qwerty (Android has it on by default); only on the letters panel.
    var numberRow = true

    var rows: [[RowItem]] {
        switch panel {
        case .letters: return letterRows
        case .numbers: return numberRows
        case .symbols: return symbolRows
        }
    }

    // MARK: letters

    private var letterRows: [[RowItem]] {
        let uppercase = mode == .english && shift != .off
        func letter(_ c: Character) -> RowItem {
            let text = String(c)
            return .key(KeySpec(id: text, action: .character(uppercase ? text.uppercased() : text),
                                title: uppercase ? text.uppercased() : text, weight: 10, style: .normal))
        }
        let top = "qwertyuiop".map(letter)
        let middle = [RowItem.spacer(5)] + "asdfghjkl".map(letter) + [.spacer(5)]
        let bottom = [shiftKey] + "zxcvbnm".map(letter) + [deleteKey]
        let digits: [[RowItem]] = numberRow
            ? [Array("1234567890").map { RowItem.key(KeySpec(id: "d\($0)", action: .character(String($0)), title: String($0),
                                                              weight: 10, style: .normal)) }]
            : []
        return digits + [top, middle, bottom, bottomRow(panelKey: numbersKey)]
    }

    // MARK: numbers and symbols

    private var chinese: Bool { mode == .chinese }

    private func symbolKeys(_ symbols: [String], weight: CGFloat = 10) -> [RowItem] {
        symbols.map { .key(KeySpec(id: "sym.\($0)", action: .character($0), title: $0, weight: weight, style: .normal)) }
    }

    private var numberRows: [[RowItem]] {
        let digits = symbolKeys(["1", "2", "3", "4", "5", "6", "7", "8", "9", "0"])
        let second = chinese
            ? symbolKeys(["－", "／", "：", "；", "（", "）", "￥", "&", "@", "“"])
            : symbolKeys(["-", "/", ":", ";", "(", ")", "$", "&", "@", "\""])
        let third = chinese
            ? symbolKeys(["。", "，", "、", "？", "！"], weight: 14)
            : symbolKeys([".", ",", "?", "!", "'"], weight: 14)
        return [digits, second, [symbolsKey] + third + [deleteKey], bottomRow(panelKey: lettersKey)]
    }

    private var symbolRows: [[RowItem]] {
        let first = chinese
            ? symbolKeys(["【", "】", "「", "」", "#", "%", "^", "*", "+", "="])
            : symbolKeys(["[", "]", "{", "}", "#", "%", "^", "*", "+", "="])
        let second = chinese
            ? symbolKeys(["_", "＼", "｜", "～", "《", "》", "€", "£", "¥", "•"])
            : symbolKeys(["_", "\\", "|", "~", "<", ">", "€", "£", "¥", "•"])
        let third = chinese
            ? symbolKeys(["。", "，", "、", "？", "！"], weight: 14)
            : symbolKeys([".", ",", "?", "!", "'"], weight: 14)
        return [first, second, [numbersKey15] + third + [deleteKey], bottomRow(panelKey: lettersKey)]
    }

    // MARK: shared keys

    private var shiftKey: RowItem {
        let enabled = mode == .english
        let title: String
        switch shift {
        case .off: title = "sf:shift"
        case .once: title = "sf:shift.fill"
        case .locked: title = "sf:capslock.fill"
        }
        return .key(KeySpec(id: enabled ? "shift" : "shift-disabled", action: .shift, title: title, weight: 15, style: .modifier))
    }

    private var deleteKey: RowItem {
        .key(KeySpec(id: "delete", action: .delete, title: "sf:delete.left", weight: 15, style: .modifier))
    }

    private var numbersKey: RowItem {
        .key(KeySpec(id: "numbers", action: .panel(.numbers), title: "123", weight: 12, style: .modifier))
    }

    private var numbersKey15: RowItem {
        .key(KeySpec(id: "numbers", action: .panel(.numbers), title: "123", weight: 15, style: .modifier))
    }

    private var symbolsKey: RowItem {
        .key(KeySpec(id: "symbols", action: .panel(.symbols), title: "#+=", weight: 15, style: .modifier))
    }

    private var lettersKey: RowItem {
        .key(KeySpec(id: "letters", action: .panel(.letters), title: "ABC", weight: 12, style: .modifier))
    }

    private func bottomRow(panelKey: RowItem) -> [RowItem] {
        var row: [RowItem] = [panelKey]
        if showGlobe {
            row.append(.key(KeySpec(id: "globe", action: .globe, title: "sf:globe", weight: 10, style: .modifier)))
        }
        row.append(.key(KeySpec(id: "language", action: .language, title: chinese ? "中" : "EN", weight: 12, style: .modifier)))
        row.append(.key(KeySpec(id: "space", action: .space, title: chinese ? "空格" : "space", weight: showGlobe ? 36 : 46, style: .normal)))
        let accent = returnKind != .standard
        row.append(.key(KeySpec(id: "return", action: .enter, title: returnKind.title ?? "sf:return.left",
                                weight: 22, style: accent ? .accent : .modifier)))
        return row
    }
}
