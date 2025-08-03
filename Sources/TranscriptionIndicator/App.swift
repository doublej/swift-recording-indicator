import Foundation
import AppKit
import OSLog
import Logging

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let logger = Logger(label: "app.delegate")
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        logger.info("TranscriptionIndicator starting...")
        
        setupApplication()
        startSimpleApplication()
        
        logger.info("TranscriptionIndicator ready")
    }
    
    func applicationWillTerminate(_ notification: Notification) {
        logger.info("TranscriptionIndicator terminating...")
    }
    
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        logger.info("Termination requested")
        return .terminateNow
    }
    
    private func startSimpleApplication() {
        Task { @MainActor in
            let enhancedProcessor = EnhancedCommandProcessor()
            let stdinHandler = SimpleStdinHandler(processor: enhancedProcessor)
            await stdinHandler.startListening()
        }
    }
    
    private func setupApplication() {
        // Set activation policy for LSUIElement app
        NSApplication.shared.setActivationPolicy(.prohibited)
        NSApplication.shared.disableRelaunchOnLogin()
        
        // Prevent automatic termination while the app is active
        ProcessInfo.processInfo.disableAutomaticTermination("TranscriptionIndicator is running")
    }
}