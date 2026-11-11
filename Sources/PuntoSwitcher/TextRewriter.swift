import Foundation
import AppKit
import Carbon

/// Handles deleting typed text and retyping it with the correct characters
final class TextRewriter {

    /// Marks our synthetic events so the event tap lets them through untouched
    static let syntheticMarker: Int64 = 0x4B535752 // "KSWR"
    /// Marks the final event of a rewrite: once the tap sees it, the rewrite has landed
    static let syntheticEndMarker: Int64 = 0x4B535745 // "KSWE"

    /// Delete `deleteCount` characters, then type `text`.
    /// The caller is responsible for switching the layout beforehand.
    func replace(deleteCount: Int, with text: String) {
        let chars = Array(text)
        let source = CGEventSource(stateID: .hidSystemState)

        for i in 0..<max(deleteCount, 0) {
            postKey(source, virtualKey: 0x33, unicode: nil,
                    isLast: chars.isEmpty && i == deleteCount - 1)
        }
        if deleteCount > 0 && !chars.isEmpty {
            usleep(30_000)
        }
        for (i, char) in chars.enumerated() {
            postKey(source, virtualKey: 0, unicode: Array(String(char).utf16),
                    isLast: i == chars.count - 1)
        }
    }

    // MARK: - Private

    private func postKey(_ source: CGEventSource?, virtualKey: CGKeyCode, unicode: [UniChar]?, isLast: Bool) {
        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: virtualKey, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: virtualKey, keyDown: false) else { return }
        if let unicode = unicode {
            keyDown.keyboardSetUnicodeString(stringLength: unicode.count, unicodeString: unicode)
        }
        keyDown.setIntegerValueField(.eventSourceUserData, value: Self.syntheticMarker)
        keyUp.setIntegerValueField(.eventSourceUserData,
                                   value: isLast ? Self.syntheticEndMarker : Self.syntheticMarker)
        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
        usleep(5_000)
    }
}
