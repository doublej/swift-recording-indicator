import AppKit
import Foundation
import Logging

// Configure logging
LoggingSystem.bootstrap { label in
    StreamLogHandler.standardOutput(label: label)
}

let logger = Logger(label: "main")

// Initialize single instance manager
let singleInstanceManager = SingleInstanceManager()

// Check for required permissions early
guard AXIsProcessTrusted() else {
    logger.error("Accessibility permission not granted. Please enable accessibility access in System Preferences.")
    
    let alert = NSAlert()
    alert.messageText = "Accessibility Permission Required"
    alert.informativeText = "TranscriptionIndicator requires accessibility permission to function. Please grant permission in System Preferences > Security & Privacy > Privacy > Accessibility, then restart the application."
    alert.alertStyle = .critical
    alert.addButton(withTitle: "Open System Preferences")
    alert.addButton(withTitle: "Quit")
    
    if alert.runModal() == .alertFirstButtonReturn {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
    }
    
    exit(1)
}

logger.info("TranscriptionIndicator v1.0.0 starting...")

// Check for single instance enforcement
if !singleInstanceManager.acquireSingleInstanceLock() {
    logger.info("Another instance is already running. Sending command and exiting.")
    
    // Send the command line arguments to the running instance
    singleInstanceManager.sendCommandToRunningInstance(CommandLine.arguments)
    
    // Exit gracefully
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
    
    A visual indicator that shows when text input is active.
    
    Usage: TranscriptionIndicator [options]
    
    Options:
        --help              Show this help message
        --version           Show version information
        --check-permissions Check accessibility permissions
    
    Communication:
        Commands are read from stdin as simple text lines.
        Responses are written to stdout as simple text lines.
    
    Example commands:
        show
        hide
        health
        show 100
    """)
    exit(0)
}

if arguments.contains("--check-permissions") {
    let hasPermission = AXIsProcessTrusted()
    print("Accessibility permission: \(hasPermission ? "granted" : "not granted")")
    exit(hasPermission ? 0 : 1)
}

// Handle termination signals gracefully
signal(SIGTERM) { _ in
    logger.info("SIGTERM received, shutting down gracefully")
    singleInstanceManager.releaseLock()
    DispatchQueue.main.async {
        NSApplication.shared.terminate(nil)
    }
}

signal(SIGINT) { _ in
    logger.info("SIGINT received, shutting down gracefully")
    singleInstanceManager.releaseLock()
    DispatchQueue.main.async {
        NSApplication.shared.terminate(nil)
    }
}

// Start the application
logger.info("Starting main run loop")
app.run()