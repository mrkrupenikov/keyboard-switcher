import AppKit
import Carbon
import ServiceManagement

final class AppDelegate: NSObject, NSApplicationDelegate {

    private var statusItem: NSStatusItem!
    private var keyMonitor: KeyMonitor!
    private var detector: LanguageDetector!
    private var inputSourceManager: InputSourceManager!
    private var rewriter: TextRewriter!

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Initialize components
        detector = LanguageDetector()
        inputSourceManager = InputSourceManager()
        rewriter = TextRewriter(inputSourceManager: inputSourceManager)
        keyMonitor = KeyMonitor(
            detector: detector,
            rewriter: rewriter,
            inputSourceManager: inputSourceManager
        )

        // Setup menu bar
        setupStatusItem()

        // Check accessibility permissions
        if !checkAccessibility() {
            showAccessibilityAlert()
        }

        // Start monitoring
        if keyMonitor.start() {
            NSLog("[KeyboardSwitcher] App started successfully")
        } else {
            NSLog("[KeyboardSwitcher] Failed to start key monitor")
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        keyMonitor.stop()
    }

    // MARK: - Status Bar

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

        if let button = statusItem.button {
            if let img = NSImage(systemSymbolName: "keyboard", accessibilityDescription: "Keyboard Switcher") {
                img.isTemplate = true
                button.image = img
            } else {
                button.title = "KS"
                button.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .medium)
            }
            button.toolTip = "Keyboard Switcher (EN/UK)"
        }

        let menu = NSMenu()

        let headerItem = NSMenuItem(title: "Keyboard Switcher", action: nil, keyEquivalent: "")
        headerItem.isEnabled = false
        menu.addItem(headerItem)

        menu.addItem(NSMenuItem.separator())

        let enableItem = NSMenuItem(title: "Enabled", action: #selector(toggleEnabled(_:)), keyEquivalent: "e")
        enableItem.state = .on
        enableItem.target = self
        menu.addItem(enableItem)

        menu.addItem(NSMenuItem.separator())

        let currentLayout = NSMenuItem(title: "Layout: \(inputSourceManager.isCurrentInputSourceEnglish ? "EN" : "UK")", action: nil, keyEquivalent: "")
        currentLayout.tag = 100
        menu.addItem(currentLayout)

        menu.addItem(NSMenuItem.separator())

        // Launch at Login
        let launchItem = NSMenuItem(title: "Launch at Login", action: #selector(toggleLaunchAtLogin(_:)), keyEquivalent: "")
        launchItem.target = self
        launchItem.state = isLaunchAtLoginEnabled() ? .on : .off
        launchItem.tag = 200
        menu.addItem(launchItem)

        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(title: "Quit", action: #selector(quit(_:)), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu

        // Update layout display periodically
        Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            if let item = self.statusItem.menu?.item(withTag: 100) {
                item.title = "Layout: \(self.inputSourceManager.isCurrentInputSourceEnglish ? "EN" : "UK")"
            }
        }
    }

    @objc private func toggleEnabled(_ sender: NSMenuItem) {
        keyMonitor.isEnabled.toggle()
        sender.state = keyMonitor.isEnabled ? .on : .off

        if let button = statusItem.button {
            if keyMonitor.isEnabled {
                if let img = NSImage(systemSymbolName: "keyboard", accessibilityDescription: "Keyboard Switcher") {
                    img.isTemplate = true
                    button.image = img
                }
            } else {
                if let img = NSImage(systemSymbolName: "keyboard.badge.ellipsis", accessibilityDescription: "Keyboard Switcher (Disabled)") {
                    img.isTemplate = true
                    button.image = img
                }
            }
        }

        NSLog("[KeyboardSwitcher] \(keyMonitor.isEnabled ? "Enabled" : "Disabled")")
    }

    // MARK: - Launch at Login

    @objc private func toggleLaunchAtLogin(_ sender: NSMenuItem) {
        if #available(macOS 13.0, *) {
            let service = SMAppService.mainApp
            do {
                if service.status == .enabled {
                    try service.unregister()
                    sender.state = .off
                    NSLog("[KeyboardSwitcher] Removed from Login Items")
                } else {
                    try service.register()
                    sender.state = .on
                    NSLog("[KeyboardSwitcher] Added to Login Items")
                }
            } catch {
                NSLog("[KeyboardSwitcher] Failed to toggle login item: \(error)")
                // Show alert to user
                let alert = NSAlert()
                alert.messageText = "Could not change Login Item"
                alert.informativeText = "You can manually add Keyboard Switcher in:\nSystem Settings → General → Login Items"
                alert.alertStyle = .informational
                alert.runModal()
            }
        } else {
            let alert = NSAlert()
            alert.messageText = "Launch at Login"
            alert.informativeText = "Please add Keyboard Switcher manually in:\nSystem Settings → General → Login Items"
            alert.alertStyle = .informational
            alert.runModal()
        }
    }

    private func isLaunchAtLoginEnabled() -> Bool {
        if #available(macOS 13.0, *) {
            return SMAppService.mainApp.status == .enabled
        }
        return false
    }

    @objc private func quit(_ sender: NSMenuItem) {
        keyMonitor.stop()
        NSApp.terminate(nil)
    }

    // MARK: - Accessibility

    private func checkAccessibility() -> Bool {
        // Passing true for kAXTrustedCheckOptionPrompt makes macOS show
        // the system prompt automatically if not trusted
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    private func showAccessibilityAlert() {
        let alert = NSAlert()
        alert.messageText = "Accessibility Access Required"
        alert.informativeText = """
        Keyboard Switcher needs Accessibility access to monitor keyboard input and correct typing.

        1. Open System Settings → Privacy & Security → Accessibility
        2. Find "Keyboard Switcher" (or "KeyboardSwitcher") and enable it
        3. If it's already there, toggle it OFF then ON again
        4. Restart the app after granting permission

        Note: If you see "PuntoSwitcher" listed, remove it and re-grant to "Keyboard Switcher".
        """
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "Later")

        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
            NSWorkspace.shared.open(url)
        }
    }
}
