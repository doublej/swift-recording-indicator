import Foundation
import OSLog
import Logging
import QuartzCore

final class PerformanceMonitor {
    static let shared = PerformanceMonitor()
    
    private let logger = Logger(label: "performance.monitor")
    private let signpostLogger = OSLog(subsystem: "com.transcription.indicator", category: "performance")
    
    private var isEnabled = true
    private var measurements: [String: [TimeInterval]] = [:]
    private let measurementQueue = DispatchQueue(label: "performance.measurements", attributes: .concurrent)
    
    // Memory monitoring
    private var memoryBaseline: UInt64 = 0
    private var peakMemoryUsage: UInt64 = 0
    private let memoryMonitorTimer: DispatchSourceTimer
    
    // Frame timing for animations
    private var lastFrameTime: CFTimeInterval = 0
    private var frameDropCount: Int = 0
    
    // Event coalescing metrics
    private var coalescedEventCount: Int = 0
    private var totalEventCount: Int = 0
    
    private init() {
        self.memoryBaseline = getCurrentMemoryUsage()
        self.peakMemoryUsage = memoryBaseline
        
        // Setup memory monitoring timer
        self.memoryMonitorTimer = DispatchSource.makeTimerSource(queue: measurementQueue)
        memoryMonitorTimer.schedule(deadline: .now(), repeating: .seconds(5))
        memoryMonitorTimer.setEventHandler { [weak self] in
            self?.monitorMemoryUsage()
        }
        memoryMonitorTimer.resume()
    }
    
    func enable() {
        isEnabled = true
        logger.info("Performance monitoring enabled")
    }
    
    func disable() {
        isEnabled = false
        logger.info("Performance monitoring disabled")
    }
    
    func measureTime<T>(_ operation: String, _ block: () throws -> T) rethrows -> T {
        guard isEnabled else {
            return try block()
        }
        
        let signpostID = OSSignpostID(log: signpostLogger)
        os_signpost(.begin, log: signpostLogger, name: "Operation", signpostID: signpostID, 
                   "Operation: %{public}s", operation)
        
        let startTime = CFAbsoluteTimeGetCurrent()
        
        defer {
            let endTime = CFAbsoluteTimeGetCurrent()
            let duration = endTime - startTime
            
            recordMeasurement(operation: operation, duration: duration)
            
            os_signpost(.end, log: signpostLogger, name: "Operation", signpostID: signpostID,
                       "Duration: %.3fms", duration * 1000)
        }
        
        return try block()
    }
    
    func measureTimeAsync<T>(_ operation: String, _ block: () async throws -> T) async rethrows -> T {
        guard isEnabled else {
            return try await block()
        }
        
        let signpostID = OSSignpostID(log: signpostLogger)
        os_signpost(.begin, log: signpostLogger, name: "AsyncOperation", signpostID: signpostID,
                   "Operation: %{public}s", operation)
        
        let startTime = CFAbsoluteTimeGetCurrent()
        
        defer {
            let endTime = CFAbsoluteTimeGetCurrent()
            let duration = endTime - startTime
            
            recordMeasurement(operation: operation, duration: duration)
            
            os_signpost(.end, log: signpostLogger, name: "AsyncOperation", signpostID: signpostID,
                       "Duration: %.3fms", duration * 1000)
        }
        
        return try await block()
    }
    
    func recordMeasurement(operation: String, duration: TimeInterval) {
        measurementQueue.async(flags: .barrier) {
            self.measurements[operation, default: []].append(duration)
            
            // Keep only the last 100 measurements per operation
            if self.measurements[operation]!.count > 100 {
                self.measurements[operation]!.removeFirst()
            }
        }
        
        // Log slow operations
        if duration > 0.1 { // 100ms threshold
            logger.warning("Slow operation detected: \(operation) took \(duration * 1000)ms")
        }
    }
    
    func getStatistics() -> [String: PerformanceStatistics] {
        return measurementQueue.sync {
            var stats: [String: PerformanceStatistics] = [:]
            
            for (operation, durations) in measurements {
                guard !durations.isEmpty else { continue }
                
                let sortedDurations = durations.sorted()
                let count = durations.count
                let sum = durations.reduce(0, +)
                
                stats[operation] = PerformanceStatistics(
                    operation: operation,
                    count: count,
                    totalTime: sum,
                    averageTime: sum / Double(count),
                    minTime: sortedDurations.first!,
                    maxTime: sortedDurations.last!,
                    medianTime: sortedDurations[count / 2],
                    p95Time: sortedDurations[Int(Double(count) * 0.95)],
                    p99Time: sortedDurations[Int(Double(count) * 0.99)]
                )
            }
            
            return stats
        }
    }
    
    func printStatistics() {
        let stats = getStatistics()
        
        guard !stats.isEmpty else {
            logger.info("No performance statistics available")
            return
        }
        
        logger.info("Performance Statistics:")
        
        for (_, stat) in stats.sorted(by: { $0.key < $1.key }) {
            logger.info("""
            \(stat.operation):
              Count: \(stat.count)
              Average: \(stat.averageTime * 1000)ms
              Min: \(stat.minTime * 1000)ms
              Max: \(stat.maxTime * 1000)ms
              Median: \(stat.medianTime * 1000)ms
              P95: \(stat.p95Time * 1000)ms
              P99: \(stat.p99Time * 1000)ms
            """)
        }
    }
    
    func exportStatistics() -> String {
        let stats = getStatistics()
        
        var output = "TranscriptionIndicator Performance Statistics\n"
        output += "Generated: \(Date())\n\n"
        
        // Memory statistics
        let currentMemory = getCurrentMemoryUsage()
        let memoryDelta = currentMemory > memoryBaseline ? currentMemory - memoryBaseline : 0
        output += "Memory Usage:\n"
        output += "  Current: \(formatBytes(currentMemory))\n"
        output += "  Baseline: \(formatBytes(memoryBaseline))\n"
        output += "  Delta: \(formatBytes(memoryDelta))\n"
        output += "  Peak: \(formatBytes(peakMemoryUsage))\n\n"
        
        // Event coalescing statistics
        let coalescingRate = totalEventCount > 0 ? Double(coalescedEventCount) / Double(totalEventCount) * 100 : 0
        output += "Event Coalescing:\n"
        output += "  Total Events: \(totalEventCount)\n"
        output += "  Coalesced: \(coalescedEventCount)\n"
        output += "  Coalescing Rate: \(String(format: "%.1f", coalescingRate))%\n\n"
        
        // Frame drops
        output += "Animation Performance:\n"
        output += "  Frame Drops: \(frameDropCount)\n\n"
        
        if stats.isEmpty {
            output += "No timing data available.\n"
            return output
        }
        
        output += "Timing Statistics:\n"
        output += String(format: "%-20s %8s %8s %8s %8s %8s %8s %8s\n",
                        "Operation", "Count", "Avg(ms)", "Min(ms)", "Max(ms)", "Med(ms)", "P95(ms)", "P99(ms)")
        output += String(repeating: "-", count: 88) + "\n"
        
        for (_, stat) in stats.sorted(by: { $0.key < $1.key }) {
            output += String(format: "%-20s %8d %8.1f %8.1f %8.1f %8.1f %8.1f %8.1f\n",
                           stat.operation,
                           stat.count,
                           stat.averageTime * 1000,
                           stat.minTime * 1000,
                           stat.maxTime * 1000,
                           stat.medianTime * 1000,
                           stat.p95Time * 1000,
                           stat.p99Time * 1000)
        }
        
        return output
    }
    
    func clearStatistics() {
        measurementQueue.async(flags: .barrier) {
            self.measurements.removeAll()
        }
        logger.info("Performance statistics cleared")
    }
    
    func startCaretDetectionMeasurement() {
        guard isEnabled else { return }
        os_signpost(.begin, log: signpostLogger, name: "CaretDetection")
    }
    
    func endCaretDetectionMeasurement() {
        guard isEnabled else { return }
        os_signpost(.end, log: signpostLogger, name: "CaretDetection")
    }
    
    func startAnimationMeasurement() {
        guard isEnabled else { return }
        os_signpost(.begin, log: signpostLogger, name: "Animation")
    }
    
    func endAnimationMeasurement() {
        guard isEnabled else { return }
        os_signpost(.end, log: signpostLogger, name: "Animation")
    }
    
    // Memory monitoring helpers
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
    
    private func monitorMemoryUsage() {
        let currentUsage = getCurrentMemoryUsage()
        peakMemoryUsage = max(peakMemoryUsage, currentUsage)
        
        let delta = currentUsage > memoryBaseline ? currentUsage - memoryBaseline : 0
        if delta > 10 * 1024 * 1024 { // 10MB increase
            logger.warning("Memory usage increased by \(formatBytes(delta))")
        }
    }
    
    private func formatBytes(_ bytes: UInt64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useAll]
        formatter.countStyle = .memory
        return formatter.string(fromByteCount: Int64(bytes))
    }
    
    // Frame timing helpers
    func recordFrameTime() {
        let currentTime = CACurrentMediaTime()
        if lastFrameTime > 0 {
            let frameDuration = currentTime - lastFrameTime
            if frameDuration > 0.0167 { // More than 16.7ms (60fps threshold)
                frameDropCount += 1
            }
        }
        lastFrameTime = currentTime
    }
    
    // Event coalescing metrics
    func recordEvent(coalesced: Bool) {
        measurementQueue.async(flags: .barrier) {
            self.totalEventCount += 1
            if coalesced {
                self.coalescedEventCount += 1
            }
        }
    }
    
    deinit {
        memoryMonitorTimer.cancel()
    }
}

struct PerformanceStatistics {
    let operation: String
    let count: Int
    let totalTime: TimeInterval
    let averageTime: TimeInterval
    let minTime: TimeInterval
    let maxTime: TimeInterval
    let medianTime: TimeInterval
    let p95Time: TimeInterval
    let p99Time: TimeInterval
}