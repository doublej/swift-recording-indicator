import Foundation
import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var singleInstanceManager: SingleInstanceManager?
    private var stdinHandler: SimpleStdinHandler?
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        Task { @MainActor in
            setupApplication()
            startStdinHandler()
        }
    }
    
    func applicationWillTerminate(_ notification: Notification) {
        singleInstanceManager?.releaseLock()
    }
    
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        return .terminateNow
    }
    
    @MainActor private func startStdinHandler() {
        let processor = SimpleCommandProcessor()
        stdinHandler = SimpleStdinHandler(processor: processor)
        stdinHandler?.startListening()
    }
    
    func setSingleInstanceManager(_ manager: SingleInstanceManager) {
        self.singleInstanceManager = manager
    }
    
    @MainActor private func setupApplication() {
        NSApplication.shared.setActivationPolicy(.prohibited)
        NSApplication.shared.disableRelaunchOnLogin()
        ProcessInfo.processInfo.disableAutomaticTermination("TranscriptionIndicator is running")
    }
}