import Carbon
import Foundation

/// Manages macOS input sources (keyboard layouts)
final class InputSourceManager {

    /// Check if the current input source is English
    var isCurrentInputSourceEnglish: Bool {
        guard let source = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue() else {
            return true
        }
        let sourceID = unsafeBitCast(
            TISGetInputSourceProperty(source, kTISPropertyInputSourceID),
            to: CFString.self
        ) as String
        // English layouts typically contain "ABC" or "US" or "English"
        return !sourceID.contains("Ukrainian")
    }

    /// Get the current input source identifier
    var currentInputSourceID: String {
        guard let source = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue() else {
            return "unknown"
        }
        return unsafeBitCast(
            TISGetInputSourceProperty(source, kTISPropertyInputSourceID),
            to: CFString.self
        ) as String
    }

    /// Switch to the other input source (English ↔ Ukrainian)
    func switchInputSource() {
        let isEnglish = isCurrentInputSourceEnglish

        let criteria = [
            kTISPropertyInputSourceCategory!: kTISCategoryKeyboardInputSource!,
            kTISPropertyInputSourceIsSelectCapable!: true,
        ] as CFDictionary

        guard let sourceList = TISCreateInputSourceList(criteria, false)?.takeRetainedValue() as? [TISInputSource] else {
            print("[PuntoSwitcher] Failed to get input source list")
            return
        }

        for source in sourceList {
            let sourceID = unsafeBitCast(
                TISGetInputSourceProperty(source, kTISPropertyInputSourceID),
                to: CFString.self
            ) as String

            let isUkrainianSource = sourceID.contains("Ukrainian")

            if isEnglish && isUkrainianSource {
                TISSelectInputSource(source)
                print("[PuntoSwitcher] Switched to Ukrainian: \(sourceID)")
                return
            } else if !isEnglish && !isUkrainianSource && sourceID.contains(".") {
                // Find English/ABC source
                let isEnglishSource = sourceID.contains("ABC") ||
                    sourceID.contains("US") ||
                    sourceID.contains("English") ||
                    sourceID.contains("DVORAK") ||
                    sourceID.contains("Colemak")
                if isEnglishSource || (!isUkrainianSource && sourceID.contains("com.apple.keylayout")) {
                    TISSelectInputSource(source)
                    print("[PuntoSwitcher] Switched to English: \(sourceID)")
                    return
                }
            }
        }
        print("[PuntoSwitcher] Could not find target input source")
    }

    /// Switch to a specific language
    func switchTo(english: Bool) {
        if english == isCurrentInputSourceEnglish { return }
        switchInputSource()
    }
}
