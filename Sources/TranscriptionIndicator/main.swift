import AppKit
import Foundation

// Initialize single instance manager
let singleInstanceManager = SingleInstanceManager()

// Check for single instance enforcement
if !singleInstanceManager.acquireSingleInstanceLock() {
    // Send the command line arguments to the running instance
    singleInstanceManager.sendCommandToRunningInstance(CommandLine.arguments)
    exit(0)
}

// Create and configure the application
let app = NSApplication.shared
let delegate = AppDelegate()
delegate.setSingleInstanceManager(singleInstanceManager)
app.delegate = delegate

// Ensure we don't show in Dock or Cmd+Tab
app.setActivationPolicy(.prohibited)

// Handle command line arguments
let arguments = CommandLine.arguments
if arguments.contains("--version") {
    print("TranscriptionIndicator v1.0.0")
    exit(0)
}

if arguments.contains("--help") {
    print("""
    TranscriptionIndicator v1.0.0
    
    A simple visual indicator.
    
    Usage: TranscriptionIndicator
    
    Commands (via stdin):
        show    - Show red circle
        hide    - Hide circle
    """)
    exit(0)
}

// Handle termination signals gracefully
signal(SIGTERM) { _ in
    singleInstanceManager.releaseLock()
    DispatchQueue.main.async {
        NSApplication.shared.terminate(nil)
    }
}

signal(SIGINT) { _ in
    singleInstanceManager.releaseLock()
    DispatchQueue.main.async {
        NSApplication.shared.terminate(nil)
    }
}

// Start the application
app.run()