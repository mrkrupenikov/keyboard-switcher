import AppKit
import Carbon

// Keep a strong reference to the delegate so it doesn't get deallocated
let delegate = AppDelegate()

let app = NSApplication.shared
app.delegate = delegate
app.setActivationPolicy(.accessory) // No dock icon, menu bar only

// Activate the app so the status item appears
app.activate(ignoringOtherApps: true)

app.run()
