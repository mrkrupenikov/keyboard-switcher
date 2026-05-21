import Foundation
import AppKit
import Carbon

/// Monitors global keyboard events and triggers language detection/correction
final class KeyMonitor {

    private let detector: LanguageDetector
    private let rewriter: TextRewriter
    private let inputSourceManager: InputSourceManager

    private var wordBuffer: String = ""
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var isProcessing = false
    private var processingStartTime: CFAbsoluteTime = 0
    private static let maxProcessingTime: CFAbsoluteTime = 1.5

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
        wordBuffer = ""
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

        // Only process keyDown events for detection
        guard type == .keyDown, isEnabled else {
            return Unmanaged.passUnretained(event)
        }

        // Safety timeout: if isProcessing has been stuck for too long, force-reset
        if isProcessing {
            if CFAbsoluteTimeGetCurrent() - processingStartTime > Self.maxProcessingTime {
                NSLog("[KeyboardSwitcher] Safety timeout: resetting isProcessing")
                isProcessing = false
                wordBuffer = ""
            } else {
                return Unmanaged.passUnretained(event)
            }
        }

        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        let flags = event.flags

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
            if !wordBuffer.isEmpty {
                processWord(triggerChar: char)
            }
            lastCorrection = nil // word ended, undo no longer makes sense
            return Unmanaged.passUnretained(event)
        }

        // Backspace: remove last char from buffer
        if keyCode == 0x33 {
            if !wordBuffer.isEmpty {
                wordBuffer.removeLast()
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
            wordBuffer = ""
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

            // Inline detection: check after 2+ characters
            if wordBuffer.count >= 2 {
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

                    isProcessing = true
                    processingStartTime = CFAbsoluteTimeGetCurrent()

                    // Switch layout IMMEDIATELY so keystrokes during rewrite use correct layout
                    inputSourceManager.switchTo(english: switchToEnglish)
                    playSwitchSound()

                    wordBuffer = ""

                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
                        self?.rewriter.rewriteInlineNoSwitch(
                            originalLength: charsOnScreen,
                            correctedText: corrected
                        )
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                            self?.isProcessing = false
                        }
                    }

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

        isProcessing = true
        processingStartTime = CFAbsoluteTimeGetCurrent()
        lastCorrection = nil
        wordBuffer = ""

        // Switch back to original layout
        let restoreToEnglish = !undo.switchedToEnglish
        inputSourceManager.switchTo(english: restoreToEnglish)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            // Delete corrected text + any extra chars typed after
            self?.rewriter.rewriteInlineNoSwitch(
                originalLength: totalToDelete,
                correctedText: undo.originalText
            )
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                self?.isProcessing = false
            }
        }
    }

    // MARK: - Helpers

    private func isWordBoundary(keyCode: Int64, char: Character) -> Bool {
        if keyCode == 0x31 { return true }
        if char == " " || char == "." || char == "," || char == "!" ||
           char == "?" || char == ";" || char == ":" || char == ")" ||
           char == "]" || char == "}" || char == "/" || char == "\t" {
            return true
        }
        return false
    }

    private func processWord(triggerChar: Character) {
        let word = wordBuffer
        wordBuffer = ""

        guard word.count >= 2 else { return }

        let isEnglish = inputSourceManager.isCurrentInputSourceEnglish

        if detector.shouldSwitch(typedWord: word, currentLayoutIsEnglish: isEnglish) {
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

            isProcessing = true
            processingStartTime = CFAbsoluteTimeGetCurrent()
            playSwitchSound()

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
                self?.rewriter.rewrite(
                    originalLength: word.count,
                    correctedText: corrected,
                    switchToEnglish: switchToEnglish
                )
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    self?.isProcessing = false
                }
            }
        }
    }
}
