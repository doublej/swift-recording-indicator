import Foundation
import AppKit
import OSLog
import Logging

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let logger = Logger(label: "app.delegate")
    
    // Reference to the single instance manager for cleanup
    private var singleInstanceManager: SingleInstanceManager?
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        logger.info("TranscriptionIndicator starting...")
        
        setupApplication()
        startSimpleApplication()
        
        logger.info("TranscriptionIndicator ready")
    }
    
    func applicationWillTerminate(_ notification: Notification) {
        logger.info("TranscriptionIndicator terminating...")
        singleInstanceManager?.releaseLock()
    }
    
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        logger.info("Termination requested")
        return .terminateNow
    }
    
    private func startSimpleApplication() {
        Task { @MainActor in
            let simpleProcessor = SimpleCommandProcessor()
            let stdinHandler = SimpleStdinHandler(processor: simpleProcessor)
            await stdinHandler.startListening()
        }
    }
    
    /// Sets the single instance manager reference for cleanup
    func setSingleInstanceManager(_ manager: SingleInstanceManager) {
        self.singleInstanceManager = manager
    }
    
    private func setupApplication() {
        // Set activation policy for LSUIElement app
        NSApplication.shared.setActivationPolicy(.prohibited)
        NSApplication.shared.disableRelaunchOnLogin()
        
        // Prevent automatic termination while the app is active
        ProcessInfo.processInfo.disableAutomaticTermination("TranscriptionIndicator is running")
    }
}