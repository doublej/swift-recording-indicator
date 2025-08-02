import Foundation
import OSLog
import Logging

final class PerformanceMonitor {
    static let shared = PerformanceMonitor()
    
    private let logger = Logger(label: "performance.monitor")
    private let signpostLogger = OSLog(subsystem: "com.transcription.indicator", category: "performance")
    
    private var isEnabled = true
    private var measurements: [String: [TimeInterval]] = [:]
    private let measurementQueue = DispatchQueue(label: "performance.measurements", attributes: .concurrent)
    
    private init() {}
    
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
        
        if stats.isEmpty {
            output += "No performance data available.\n"
            return output
        }
        
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