import Foundation
import OSLog

/// Centralized memory management and monitoring
final class MemoryManager {
    static let shared = MemoryManager()
    
    private let logger = Logger(label: "memory.manager")
    private let warningThreshold: UInt64 = 50 * 1024 * 1024 // 50MB
    private let criticalThreshold: UInt64 = 100 * 1024 * 1024 // 100MB
    
    private var cleanupHandlers: [() -> Void] = []
    private let cleanupQueue = DispatchQueue(label: "memory.cleanup", qos: .utility)
    
    private init() {
        setupMemoryWarningHandler()
    }
    
    /// Register a cleanup handler to be called when memory pressure is detected
    func registerCleanupHandler(_ handler: @escaping () -> Void) {
        cleanupQueue.async(flags: .barrier) {
            self.cleanupHandlers.append(handler)
        }
    }
    
    /// Manually trigger memory cleanup
    func performCleanup() {
        logger.info("Performing manual memory cleanup")
        
        cleanupQueue.async(flags: .barrier) {
            for handler in self.cleanupHandlers {
                handler()
            }
        }
        
        // Force garbage collection of autoreleased objects
        autoreleasepool { }
    }
    
    /// Check current memory usage and trigger cleanup if needed
    func checkMemoryPressure() {
        let currentUsage = getCurrentMemoryUsage()
        
        if currentUsage > criticalThreshold {
            logger.error("Critical memory usage: \(formatBytes(currentUsage))")
            performCleanup()
        } else if currentUsage > warningThreshold {
            logger.warning("High memory usage: \(formatBytes(currentUsage))")
            performCleanup()
        }
    }
    
    private func setupMemoryWarningHandler() {
        // Monitor memory warnings
        let source = DispatchSource.makeMemoryPressureSource(
            eventMask: [.warning, .critical],
            queue: cleanupQueue
        )
        
        source.setEventHandler {
            let event = source.data
            
            if event.contains(.critical) {
                self.logger.error("System memory pressure: CRITICAL")
                self.performCleanup()
            } else if event.contains(.warning) {
                self.logger.warning("System memory pressure: WARNING")
                self.performCleanup()
            }
        }
        
        source.resume()
    }
    
    private func getCurrentMemoryUsage() -> UInt64 {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size / MemoryLayout<natural_t>.size)
        
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        
        return result == KERN_SUCCESS ? info.resident_size : 0
    }
    
    private func formatBytes(_ bytes: UInt64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useAll]
        formatter.countStyle = .memory
        return formatter.string(fromByteCount: Int64(bytes))
    }
}

/// Auto-release pool for temporary allocations
struct TemporaryAllocation {
    static func perform<T>(_ block: () throws -> T) rethrows -> T {
        try autoreleasepool {
            try block()
        }
    }
    
    static func performAsync<T>(_ block: () async throws -> T) async rethrows -> T {
        try await Task {
            try autoreleasepool {
                try await block()
            }
        }.value
    }
}