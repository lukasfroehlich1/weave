import Carbon.HIToolbox
import KeyboardShortcuts
import SwiftUI

extension KeyboardShortcuts.Name {
    static let newThread = Self("newThread", default: .init(.n, modifiers: .command))
    static let newTab = Self("newTab", default: .init(.t, modifiers: .command))
    static let closeTab = Self("closeTab", default: .init(.w, modifiers: .command))
    static let addRepo = Self("addRepo", default: .init(.o, modifiers: [.command, .shift]))
    static let toggleSidebar = Self("toggleSidebar", default: .init(.b, modifiers: .command))
    static let openInEditor = Self("openInEditor", default: .init(.o, modifiers: .command))
    static let openPR = Self("openPR", default: .init(.p, modifiers: .command))
    static let deleteThread = Self("deleteThread", default: .init(.d, modifiers: .command))
    static let nextThread = Self("nextThread", default: .init(.j, modifiers: .command))
    static let previousThread = Self("previousThread", default: .init(.k, modifiers: .command))
    static let nextActiveThread = Self("nextActiveThread", default: .init(.j, modifiers: [.command, .shift]))
    static let previousActiveThread = Self("previousActiveThread", default: .init(.k, modifiers: [.command, .shift]))

    var swiftUIShortcut: KeyboardShortcut? {
        guard let shortcut = KeyboardShortcuts.getShortcut(for: self) else { return nil }
        guard let character = shortcut.keyCharacter else { return nil }
        let key = KeyEquivalent(character)
        var modifiers: SwiftUI.EventModifiers = []
        if shortcut.modifiers.contains(.command) { modifiers.insert(.command) }
        if shortcut.modifiers.contains(.shift) { modifiers.insert(.shift) }
        if shortcut.modifiers.contains(.option) { modifiers.insert(.option) }
        if shortcut.modifiers.contains(.control) { modifiers.insert(.control) }
        return KeyboardShortcut(key, modifiers: modifiers)
    }
}

extension KeyboardShortcuts.Shortcut {
    var keyCharacter: Character? {
        let keyCode = Int(carbonKeyCode)
        let keyMap: [Int: Character] = [
            kVK_ANSI_A: "a", kVK_ANSI_B: "b", kVK_ANSI_C: "c", kVK_ANSI_D: "d",
            kVK_ANSI_E: "e", kVK_ANSI_F: "f", kVK_ANSI_G: "g", kVK_ANSI_H: "h",
            kVK_ANSI_I: "i", kVK_ANSI_J: "j", kVK_ANSI_K: "k", kVK_ANSI_L: "l",
            kVK_ANSI_M: "m", kVK_ANSI_N: "n", kVK_ANSI_O: "o", kVK_ANSI_P: "p",
            kVK_ANSI_Q: "q", kVK_ANSI_R: "r", kVK_ANSI_S: "s", kVK_ANSI_T: "t",
            kVK_ANSI_U: "u", kVK_ANSI_V: "v", kVK_ANSI_W: "w", kVK_ANSI_X: "x",
            kVK_ANSI_Y: "y", kVK_ANSI_Z: "z",
            kVK_ANSI_0: "0", kVK_ANSI_1: "1", kVK_ANSI_2: "2", kVK_ANSI_3: "3",
            kVK_ANSI_4: "4", kVK_ANSI_5: "5", kVK_ANSI_6: "6", kVK_ANSI_7: "7",
            kVK_ANSI_8: "8", kVK_ANSI_9: "9",
            kVK_ANSI_Backslash: "\\", kVK_ANSI_Slash: "/",
            kVK_ANSI_Comma: ",", kVK_ANSI_Period: ".",
            kVK_ANSI_Semicolon: ";", kVK_ANSI_Quote: "'",
            kVK_ANSI_LeftBracket: "[", kVK_ANSI_RightBracket: "]",
            kVK_ANSI_Minus: "-", kVK_ANSI_Equal: "=",
        ]
        return keyMap[keyCode]
    }
}

extension View {
    func keyboardShortcut(for name: KeyboardShortcuts.Name) -> some View {
        Group {
            if let shortcut = name.swiftUIShortcut {
                self.keyboardShortcut(shortcut.key, modifiers: shortcut.modifiers)
            } else {
                self
            }
        }
    }
}
