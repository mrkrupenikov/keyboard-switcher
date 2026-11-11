import Foundation
import AppKit
import Carbon

/// Monitors global keyboard events and triggers language detection/correction
final class KeyMonitor {

    private let detector: LanguageDetector
    private let rewriter: TextRewriter
    private let inputSourceManager: InputSourceManager

    private var wordBuffer: String = ""
    /// This word was already switched mid-word; leave it alone until it ends.
    private var inlineLocked = false
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    // A rewrite (delete + retype) is in flight. Keys the user presses meanwhile are
    // held and replayed once it has landed, so they can't end up inside the rewrite.
    private var isProcessing = false
    private var processingStartTime: CFAbsoluteTime = 0
    private var rewriteGeneration = 0
    private static let maxProcessingTime: CFAbsoluteTime = 1.5

    private struct HeldKey {
        let keyCode: CGKeyCode
        let keyDown: Bool
        let flags: CGEventFlags
    }
    private var heldKeys: [HeldKey] = []
    private var heldDownKeyCodes: Set<CGKeyCode> = []

    // Undo support: remember the last correction so Ctrl+Z can revert it
    private struct LastCorrection {
        let originalText: String      // what was on screen before correction
        let correctedText: String     // what we replaced it with
        let switchedToEnglish: Bool   // the direction we switched
        let timestamp: CFAbsoluteTime
        var charsTypedAfter: Int = 0  // how many chars user typed since correction
    }
    private var lastCorrection: LastCorrection?
    private static let undoWindow: CFAbsoluteTime = 10.0 // seconds to allow undo

    var isEnabled: Bool = true
    var soundEnabled: Bool = true

    init(detector: LanguageDetector, rewriter: TextRewriter, inputSourceManager: InputSourceManager) {
        self.detector = detector
        self.rewriter = rewriter
        self.inputSourceManager = inputSourceManager
    }

    private func playSwitchSound() {
        guard soundEnabled else { return }
        NSSound(named: "Tink")?.play()
    }

    func start() -> Bool {
        let eventMask: CGEventMask = (1 << CGEventType.keyDown.rawValue)
            | (1 << CGEventType.keyUp.rawValue)
            | (1 << CGEventType.flagsChanged.rawValue)

        guard let tap = CGEvent.tapCreate(
            tap: .cghidEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: eventMask,
            callback: { (proxy, type, event, refcon) -> Unmanaged<CGEvent>? in
                guard let refcon = refcon else { return Unmanaged.passUnretained(event) }
                let monitor = Unmanaged<KeyMonitor>.fromOpaque(refcon).takeUnretainedValue()
                return monitor.handleEvent(proxy: proxy, type: type, event: event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            NSLog("[KeyboardSwitcher] Failed to create event tap. Check Accessibility permissions.")
            return false
        }

        eventTap = tap
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)

        NSLog("[KeyboardSwitcher] Key monitor started")
        return true
    }

    func stop() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .commonModes)
        }
        eventTap = nil
        runLoopSource = nil
        resetWord()
        isProcessing = false
        heldKeys.removeAll()
        heldDownKeyCodes.removeAll()
        NSLog("[KeyboardSwitcher] Key monitor stopped")
    }

    // MARK: - Event Handling

    private func handleEvent(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        // Re-enable tap if the system disabled it
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap = eventTap {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
            NSLog("[KeyboardSwitcher] Re-enabled event tap (was disabled by %@)",
                  type == .tapDisabledByTimeout ? "timeout" : "user input")
            return Unmanaged.passUnretained(event)
        }

        guard type == .keyDown || type == .keyUp else {
            return Unmanaged.passUnretained(event)
        }

        // Our own synthetic events pass straight through. The last one of a rewrite
        // tells us it has fully landed, so held keys can follow it.
        let marker = event.getIntegerValueField(.eventSourceUserData)
        if marker == TextRewriter.syntheticMarker {
            return Unmanaged.passUnretained(event)
        }
        if marker == TextRewriter.syntheticEndMarker {
            finishRewrite()
            return Unmanaged.passUnretained(event)
        }

        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        let flags = event.flags

        // Rewrite in flight: hold the user's keys instead of letting them land mid-rewrite
        if isProcessing {
            let timedOut = CFAbsoluteTimeGetCurrent() - processingStartTime > Self.maxProcessingTime
            if timedOut {
                NSLog("[KeyboardSwitcher] Safety timeout: releasing held keys")
            }
            let code = CGKeyCode(keyCode)
            if type == .keyDown || heldDownKeyCodes.contains(code) {
                heldKeys.append(HeldKey(keyCode: code, keyDown: type == .keyDown, flags: flags))
                if type == .keyDown {
                    heldDownKeyCodes.insert(code)
                } else {
                    heldDownKeyCodes.remove(code)
                }
                if timedOut { finishRewrite() }
                return nil
            }
            // Key-up of a key that went down before the rewrite began
            if timedOut { finishRewrite() }
            return Unmanaged.passUnretained(event)
        }

        // Only process keyDown events for detection
        guard type == .keyDown, isEnabled else {
            return Unmanaged.passUnretained(event)
        }

        // --- Ctrl+Z: Undo last correction ---
        if keyCode == 0x06 /* z */ && flags.contains(.maskControl) && !flags.contains(.maskCommand) {
            if let undo = lastCorrection,
               CFAbsoluteTimeGetCurrent() - undo.timestamp < Self.undoWindow {
                performUndo(undo)
                return nil // suppress the Ctrl+Z keystroke
            }
            // No undo available — pass through as normal Ctrl+Z
            return Unmanaged.passUnretained(event)
        }

        // Ignore other modifier combos (Cmd, Ctrl, Option)
        if flags.contains(.maskCommand) || flags.contains(.maskControl) ||
           flags.contains(.maskAlternate) {
            return Unmanaged.passUnretained(event)
        }

        // Get the character for this keypress
        var length = 0
        var chars = [UniChar](repeating: 0, count: 4)
        event.keyboardGetUnicodeString(maxStringLength: 4, actualStringLength: &length, unicodeString: &chars)

        guard length > 0 else { return Unmanaged.passUnretained(event) }
        let char = Character(UnicodeScalar(chars[0])!)

        // Check if this is a word boundary
        if isWordBoundary(keyCode: keyCode, char: char) {
            let correcting = !wordBuffer.isEmpty && processWord()
            lastCorrection = nil // word ended, undo no longer makes sense
            if correcting {
                // Hold the boundary key so it is retyped after the corrected word,
                // in the new layout (keeps punctuation instead of forcing a space)
                let code = CGKeyCode(keyCode)
                heldKeys.append(HeldKey(keyCode: code, keyDown: true, flags: flags))
                heldDownKeyCodes.insert(code)
                return nil
            }
            return Unmanaged.passUnretained(event)
        }

        // Backspace: remove last char from buffer
        if keyCode == 0x33 {
            if !wordBuffer.isEmpty {
                wordBuffer.removeLast()
            }
            if wordBuffer.isEmpty {
                inlineLocked = false
            }
            // Track backspace for undo accounting
            if lastCorrection != nil {
                if lastCorrection!.charsTypedAfter > 0 {
                    lastCorrection!.charsTypedAfter -= 1
                } else {
                    // Backspacing into the corrected text — undo no longer safe
                    lastCorrection = nil
                }
            }
            return Unmanaged.passUnretained(event)
        }

        // Escape, arrows, function keys: clear buffer and invalidate undo
        if keyCode == 0x35 || // Escape
           keyCode == 0x7B || keyCode == 0x7C || // Left, Right arrows
           keyCode == 0x7D || keyCode == 0x7E || // Down, Up arrows
           keyCode == 0x24 { // Return/Enter
            resetWord()
            lastCorrection = nil
            return Unmanaged.passUnretained(event)
        }

        // Add character to buffer
        if char.isLetter || char == "'" || char == "-" || char == "\u{2019}" {
            wordBuffer.append(char)

            // Track chars typed after a correction (for undo)
            if lastCorrection != nil {
                lastCorrection!.charsTypedAfter += 1
            }

            // Inline detection: wait for at least 3 typed letters
            if wordBuffer.count >= LanguageDetector.minInlineLength && !inlineLocked {
                let isEnglish = inputSourceManager.isCurrentInputSourceEnglish
                if detector.shouldSwitchInline(buffer: wordBuffer, currentLayoutIsEnglish: isEnglish) {
                    let corrected = detector.convertWord(wordBuffer, currentLayoutIsEnglish: isEnglish)
                    let switchToEnglish = !isEnglish
                    let charsOnScreen = wordBuffer.count - 1

                    NSLog("[KeyboardSwitcher] Inline: '%@' → '%@' (switch to %@)",
                          wordBuffer, corrected, switchToEnglish ? "EN" : "UK")

                    // Save for undo — original is the chars on screen + the suppressed trigger char
                    let originalOnScreen = String(wordBuffer.dropLast()) // chars already on screen
                    lastCorrection = LastCorrection(
                        originalText: originalOnScreen,
                        correctedText: corrected,
                        switchedToEnglish: switchToEnglish,
                        timestamp: CFAbsoluteTimeGetCurrent()
                    )

                    inputSourceManager.switchTo(english: switchToEnglish)
                    playSwitchSound()

                    // Keep tracking the word in its corrected form, so the rest of it is
                    // judged as one word rather than as a fresh fragment
                    wordBuffer = corrected
                    inlineLocked = true

                    beginRewrite(deleteCount: charsOnScreen, text: corrected)

                    return nil // suppress the triggering keystroke
                }
            }
        }

        return Unmanaged.passUnretained(event)
    }

    // MARK: - Undo

    private func performUndo(_ undo: LastCorrection) {
        let totalToDelete = undo.correctedText.count + undo.charsTypedAfter

        NSLog("[KeyboardSwitcher] Undo: '%@' +%d extra chars → '%@' (switch back to %@)",
              undo.correctedText, undo.charsTypedAfter, undo.originalText,
              undo.switchedToEnglish ? "UK" : "EN")

        lastCorrection = nil
        resetWord()

        // Switch back to original layout
        let restoreToEnglish = !undo.switchedToEnglish
        inputSourceManager.switchTo(english: restoreToEnglish)

        // Delete corrected text + any extra chars typed after
        beginRewrite(deleteCount: totalToDelete, text: undo.originalText)
    }

    // MARK: - Rewriting

    /// Delete `deleteCount` characters and type `text`. From now until the rewrite has
    /// landed, the user's keystrokes are held; `finishRewrite` replays them.
    /// The caller switches the layout first.
    private func beginRewrite(deleteCount: Int, text: String) {
        isProcessing = true
        processingStartTime = CFAbsoluteTimeGetCurrent()
        rewriteGeneration += 1
        let generation = rewriteGeneration

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            guard let self = self, self.rewriteGeneration == generation else { return }
            self.rewriter.replace(deleteCount: deleteCount, with: text)

            // Normally the tap sees the rewrite's last event and finishes right away;
            // this only matters if that event never comes back to us.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
                guard let self = self, self.rewriteGeneration == generation else { return }
                self.finishRewrite()
            }
        }
    }

    /// The rewrite has landed: retype whatever the user pressed in the meantime.
    /// The keys are posted as ordinary events, so they come back through the tap and
    /// are tracked like normal typing, in the layout that is now active.
    private func finishRewrite() {
        guard isProcessing else { return }
        isProcessing = false

        let keys = heldKeys
        heldKeys.removeAll()
        heldDownKeyCodes.removeAll()
        guard !keys.isEmpty else { return }

        let source = CGEventSource(stateID: .hidSystemState)
        for key in keys {
            guard let replay = CGEvent(keyboardEventSource: source, virtualKey: key.keyCode, keyDown: key.keyDown) else { continue }
            replay.flags = key.flags
            replay.post(tap: .cghidEventTap)
        }
    }

    // MARK: - Helpers

    private func resetWord() {
        wordBuffer = ""
        inlineLocked = false
    }

    private func isWordBoundary(keyCode: Int64, char: Character) -> Bool {
        if keyCode == 0x31 { return true }
        if char == " " || char == "." || char == "," || char == "!" ||
           char == "?" || char == ";" || char == ":" || char == ")" ||
           char == "]" || char == "}" || char == "/" || char == "\t" {
            return true
        }
        return false
    }

    /// Check the finished word and start a correction if it was typed in the wrong layout.
    /// Returns true if a correction started; the caller then holds the boundary key.
    private func processWord() -> Bool {
        let word = wordBuffer
        resetWord()

        guard word.count >= 2 else { return false }

        let isEnglish = inputSourceManager.isCurrentInputSourceEnglish

        guard detector.shouldSwitch(typedWord: word, currentLayoutIsEnglish: isEnglish) else { return false }

        let corrected = detector.convertWord(word, currentLayoutIsEnglish: isEnglish)
        let switchToEnglish = !isEnglish

        NSLog("[KeyboardSwitcher] Word: '%@' → '%@' (switch to %@)",
              word, corrected, switchToEnglish ? "EN" : "UK")

        // Save for undo
        lastCorrection = LastCorrection(
            originalText: word,
            correctedText: corrected,
            switchedToEnglish: switchToEnglish,
            timestamp: CFAbsoluteTimeGetCurrent()
        )

        inputSourceManager.switchTo(english: switchToEnglish)
        playSwitchSound()

        beginRewrite(deleteCount: word.count, text: corrected)
        return true
    }
}
