import Foundation
import AppKit
import Carbon

/// Handles deleting typed text and retyping it with the correct characters
final class TextRewriter {

    /// Marker value to identify our synthetic events (so the event tap lets them through)
    static let syntheticMarker: Int64 = 0x4B535752 // "KSWR"

    private let inputSourceManager: InputSourceManager

    init(inputSourceManager: InputSourceManager) {
        self.inputSourceManager = inputSourceManager
    }

    /// Rewrite the last typed word with the corrected version (triggered by word boundary)
    func rewrite(originalLength: Int, correctedText: String, switchToEnglish: Bool) {
        deleteCharacters(count: originalLength + 1)
        usleep(30_000)
        inputSourceManager.switchTo(english: switchToEnglish)
        usleep(50_000)
        typeText(correctedText + " ")
    }

    /// Rewrite mid-word (inline detection, no trigger character to handle)
    func rewriteInline(originalLength: Int, correctedText: String, switchToEnglish: Bool) {
        deleteCharacters(count: originalLength)
        usleep(30_000)
        inputSourceManager.switchTo(english: switchToEnglish)
        usleep(50_000)
        typeText(correctedText)
    }

    /// Rewrite mid-word when layout was already switched by the caller
    func rewriteInlineNoSwitch(originalLength: Int, correctedText: String) {
        deleteCharacters(count: originalLength)
        usleep(30_000)
        typeText(correctedText)
    }

    // MARK: - Private

    private func deleteCharacters(count: Int) {
        let src = CGEventSource(stateID: .hidSystemState)
        for _ in 0..<count {
            let keyDown = CGEvent(keyboardEventSource: src, virtualKey: 0x33, keyDown: true)
            let keyUp = CGEvent(keyboardEventSource: src, virtualKey: 0x33, keyDown: false)
            keyDown?.setIntegerValueField(.eventSourceUserData, value: Self.syntheticMarker)
            keyUp?.setIntegerValueField(.eventSourceUserData, value: Self.syntheticMarker)
            keyDown?.post(tap: .cghidEventTap)
            keyUp?.post(tap: .cghidEventTap)
            usleep(5_000)
        }
    }

    private func typeText(_ text: String) {
        let src = CGEventSource(stateID: .hidSystemState)
        for char in text {
            let utf16 = Array(String(char).utf16)
            let keyDown = CGEvent(keyboardEventSource: src, virtualKey: 0, keyDown: true)
            keyDown?.keyboardSetUnicodeString(stringLength: utf16.count, unicodeString: utf16)
            let keyUp = CGEvent(keyboardEventSource: src, virtualKey: 0, keyDown: false)
            keyDown?.setIntegerValueField(.eventSourceUserData, value: Self.syntheticMarker)
            keyUp?.setIntegerValueField(.eventSourceUserData, value: Self.syntheticMarker)
            keyDown?.post(tap: .cghidEventTap)
            keyUp?.post(tap: .cghidEventTap)
            usleep(5_000)
        }
    }
}
