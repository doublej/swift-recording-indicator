import Foundation
import AppKit
import Logging

/// Manages single instance enforcement for the TranscriptionIndicator application
final class SingleInstanceManager: NSObject {
    private let logger = Logger(label: "single.instance")
    private let applicationIdentifier = "com.transcriptionindicator.app"
    private let lockFileName = "TranscriptionIndicator.lock"
    private let notificationName = "TranscriptionIndicatorCommand"
    
    private var lockFileHandle: FileHandle?
    private var lockFileURL: URL {
        let tempDir = FileManager.default.temporaryDirectory
        return tempDir.appendingPathComponent(lockFileName)
    }
    
    /// Attempts to acquire single instance lock
    /// - Returns: true if this is the first instance, false if another instance is running
    func acquireSingleInstanceLock() -> Bool {
        logger.info("Attempting to acquire single instance lock")
        
        // Try to create and lock the file
        let fileManager = FileManager.default
        
        // Create the lock file if it doesn't exist
        if !fileManager.fileExists(atPath: lockFileURL.path) {
            fileManager.createFile(atPath: lockFileURL.path, contents: nil)
        }
        
        do {
            let fileHandle = try FileHandle(forWritingTo: lockFileURL)
            
            // Try to acquire an exclusive lock (LOCK_EX with LOCK_NB for non-blocking)
            let lockResult = flock(fileHandle.fileDescriptor, LOCK_EX | LOCK_NB)
            
            if lockResult == 0 {
                // Successfully acquired lock - we are the first instance
                self.lockFileHandle = fileHandle
                
                // Write our process ID to the lock file
                let processInfo = "\(ProcessInfo.processInfo.processIdentifier)\n"
                if let data = processInfo.data(using: .utf8) {
                    fileHandle.write(data)
                    fileHandle.synchronizeFile()
                }
                
                logger.info("Successfully acquired single instance lock")
                setupNotificationListener()
                return true
            } else {
                // Failed to acquire lock - another instance is running
                try fileHandle.close()
                logger.info("Another instance is already running")
                return false
            }
        } catch {
            logger.error("Failed to acquire lock: \(error)")
            return false
        }
    }
    
    /// Releases the single instance lock
    func releaseLock() {
        guard let fileHandle = lockFileHandle else { return }
        
        logger.info("Releasing single instance lock")
        
        // Release the file lock
        flock(fileHandle.fileDescriptor, LOCK_UN)
        
        do {
            try fileHandle.close()
        } catch {
            logger.error("Error closing lock file: \(error)")
        }
        
        // Remove the lock file
        do {
            try FileManager.default.removeItem(at: lockFileURL)
        } catch {
            logger.error("Error removing lock file: \(error)")
        }
        
        lockFileHandle = nil
    }
    
    /// Sends a command to the running instance via distributed notifications
    /// - Parameter arguments: Command line arguments to send
    func sendCommandToRunningInstance(_ arguments: [String]) {
        logger.info("Sending command to running instance: \(arguments)")
        
        let userInfo: [String: Any] = [
            "arguments": arguments,
            "senderPID": ProcessInfo.processInfo.processIdentifier
        ]
        
        let notification = Notification.Name(notificationName)
        DistributedNotificationCenter.default().post(
            name: notification,
            object: applicationIdentifier,
            userInfo: userInfo
        )
        
        // Give the notification time to be delivered
        Thread.sleep(forTimeInterval: 0.1)
    }
    
    /// Sets up listener for distributed notifications from secondary instances
    private func setupNotificationListener() {
        logger.info("Setting up notification listener")
        
        let notification = Notification.Name(notificationName)
        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(handleDistributedNotification(_:)),
            name: notification,
            object: applicationIdentifier
        )
    }
    
    /// Handles distributed notifications from secondary instances
    /// - Parameter notification: The distributed notification received
    @objc private func handleDistributedNotification(_ notification: Notification) {
        handleNotificationFromSecondaryInstance(notification)
    }
    
    /// Handles notifications from secondary instances
    /// - Parameter notification: The distributed notification received  
    private func handleNotificationFromSecondaryInstance(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let arguments = userInfo["arguments"] as? [String],
              let senderPID = userInfo["senderPID"] as? Int32 else {
            logger.warning("Received invalid notification from secondary instance")
            return
        }
        
        logger.info("Received command from secondary instance (PID: \(senderPID)): \(arguments)")
        
        // Process the command line arguments as if they were passed to this instance
        handleSecondaryInstanceArguments(arguments)
    }
    
    /// Processes arguments received from a secondary instance
    /// - Parameter arguments: Command line arguments from secondary instance
    private func handleSecondaryInstanceArguments(_ arguments: [String]) {
        // Handle version and help requests by ignoring them (secondary instance will handle output)
        if arguments.contains("--version") || arguments.contains("--help") || arguments.contains("--check-permissions") {
            logger.info("Ignoring info command from secondary instance")
            return
        }
        
        // For other commands, we could potentially forward them to the command processor
        // but for now, we'll just log them since the stdin handler will process real commands
        logger.info("Secondary instance launched with arguments: \(arguments)")
    }
    
    deinit {
        releaseLock()
        DistributedNotificationCenter.default().removeObserver(self)
    }
}