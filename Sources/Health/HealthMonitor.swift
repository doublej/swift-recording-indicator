import Foundation
import Logging
import OSLog
import AppKit

actor HealthMonitor: HealthMonitoring {
    private let logger = Logger(label: "health.monitor")
    private let signpostLogger = OSLog(subsystem: "com.transcription.indicator", category: "health")
    
    private var monitoringTask: Task<Void, Never>?
    private var isMonitoring = false
    private var currentInterval: TimeInterval = 30.0
    private var lastHealthCheck = Date()
    
    private let memoryMonitor = MemoryMonitor()
    private let cpuMonitor = CPUMonitor()
    
    func startMonitoring(interval: TimeInterval) async {
        guard !isMonitoring else {
            await updateInterval(interval)
            return
        }
        
        logger.info("Starting health monitoring with interval: \(interval)s")
        
        currentInterval = interval
        isMonitoring = true
        lastHealthCheck = Date()
        
        monitoringTask = Task {
            await monitoringLoop()
        }
        
        await memoryMonitor.startMonitoring()
        await cpuMonitor.startMonitoring()
    }
    
    func stopMonitoring() async {
        guard isMonitoring else { return }
        
        logger.info("Stopping health monitoring")
        
        isMonitoring = false
        monitoringTask?.cancel()
        monitoringTask = nil
        
        await memoryMonitor.stopMonitoring()
        await cpuMonitor.stopMonitoring()
    }
    
    func reportHealth() async -> HealthResponse {
        let signpostID = OSSignpostID(log: signpostLogger)
        os_signpost(.begin, log: signpostLogger, name: "ReportHealth", signpostID: signpostID)
        
        defer {
            os_signpost(.end, log: signpostLogger, name: "ReportHealth", signpostID: signpostID)
        }
        
        lastHealthCheck = Date()
        
        let formatter = ISO8601DateFormatter()
        let memoryUsage = await memoryMonitor.getCurrentUsage()
        let cpuUsage = await cpuMonitor.getCurrentUsage()
        
        let response = HealthResponse(
            status: "alive",
            timestamp: formatter.string(from: Date()),
            pid: Int(ProcessInfo.processInfo.processIdentifier),
            v: 1,
            memoryUsage: memoryUsage,
            cpuUsage: cpuUsage
        )
        
        logger.debug("Health reported: memory=\(memoryUsage ?? 0)MB, cpu=\(cpuUsage ?? 0)%")
        
        return response
    }
    
    private func updateInterval(_ newInterval: TimeInterval) async {
        guard newInterval != currentInterval else { return }
        
        logger.info("Updating health monitoring interval: \(currentInterval)s -> \(newInterval)s")
        
        currentInterval = newInterval
        
        if isMonitoring {
            await stopMonitoring()
            await startMonitoring(interval: newInterval)
        }
    }
    
    private func monitoringLoop() async {
        while isMonitoring {
            let signpostID = OSSignpostID(log: signpostLogger)
            os_signpost(.begin, log: signpostLogger, name: "HealthCheck", signpostID: signpostID)
            
            do {
                try await Task.sleep(nanoseconds: UInt64(currentInterval * 1_000_000_000))
                
                if isMonitoring {
                    await performHealthCheck()
                }
            } catch {
                if !(error is CancellationError) {
                    logger.error("Health monitoring error: \(error.localizedDescription)")
                }
                break
            }
            
            os_signpost(.end, log: signpostLogger, name: "HealthCheck", signpostID: signpostID)
        }
        
        logger.info("Health monitoring loop ended")
    }
    
    private func performHealthCheck() async {
        let now = Date()
        let timeSinceLastCheck = now.timeIntervalSince(lastHealthCheck)
        
        if timeSinceLastCheck > currentInterval * 2 {
            logger.warning("Health check timeout detected: \(timeSinceLastCheck)s since last check")
            await handleHealthTimeout()
        }
        
        await checkSystemResources()
    }
    
    private func checkSystemResources() async {
        let memoryUsage = await memoryMonitor.getCurrentUsage()
        let cpuUsage = await cpuMonitor.getCurrentUsage()
        
        if let memory = memoryUsage, memory > 100 { // 100MB threshold
            logger.warning("High memory usage detected: \(memory)MB")
            await handleHighMemoryUsage()
        }
        
        if let cpu = cpuUsage, cpu > 50 { // 50% CPU threshold
            logger.warning("High CPU usage detected: \(cpu)%")
            await handleHighCPUUsage()
        }
    }
    
    private func handleHealthTimeout() async {
        logger.error("Health timeout - initiating graceful shutdown")
        
        await MainActor.run {
            NSApplication.shared.terminate(nil)
        }
    }
    
    private func handleHighMemoryUsage() async {
        logger.warning("Performing memory cleanup due to high usage")
        
        await memoryMonitor.performCleanup()
        
        DispatchQueue.main.async {
            URLCache.shared.removeAllCachedResponses()
        }
    }
    
    private func handleHighCPUUsage() async {
        logger.warning("High CPU usage detected - monitoring performance")
    }
}

actor MemoryMonitor {
    private let logger = Logger(label: "memory.monitor")
    
    private var isMonitoring = false
    private var monitoringTask: Task<Void, Never>?
    private var currentUsage: UInt64 = 0
    
    func startMonitoring() async {
        guard !isMonitoring else { return }
        
        isMonitoring = true
        
        monitoringTask = Task {
            while isMonitoring {
                currentUsage = getMemoryUsage()
                
                do {
                    try await Task.sleep(nanoseconds: 5_000_000_000) // 5 seconds
                } catch {
                    break
                }
            }
        }
    }
    
    func stopMonitoring() async {
        isMonitoring = false
        monitoringTask?.cancel()
        monitoringTask = nil
    }
    
    func getCurrentUsage() async -> UInt64? {
        return currentUsage > 0 ? currentUsage / (1024 * 1024) : nil // Convert to MB
    }
    
    func performCleanup() async {
        logger.info("Performing memory cleanup")
        
        await MainActor.run {
            if #available(macOS 13.0, *) {
                URLSession.shared.invalidateAndCancel()
            }
        }
    }
    
    private func getMemoryUsage() -> UInt64 {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4
        
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        
        return result == KERN_SUCCESS ? info.resident_size : 0
    }
}

actor CPUMonitor {
    private let logger = Logger(label: "cpu.monitor")
    
    private var isMonitoring = false
    private var monitoringTask: Task<Void, Never>?
    private var currentUsage: Double = 0.0
    
    func startMonitoring() async {
        guard !isMonitoring else { return }
        
        isMonitoring = true
        
        monitoringTask = Task {
            while isMonitoring {
                currentUsage = getCPUUsage()
                
                do {
                    try await Task.sleep(nanoseconds: 5_000_000_000) // 5 seconds
                } catch {
                    break
                }
            }
        }
    }
    
    func stopMonitoring() async {
        isMonitoring = false
        monitoringTask?.cancel()
        monitoringTask = nil
    }
    
    func getCurrentUsage() async -> Double? {
        return currentUsage > 0 ? currentUsage : nil
    }
    
    private func getCPUUsage() -> Double {
        var info = task_thread_times_info()
        var count = mach_msg_type_number_t(MemoryLayout<task_thread_times_info>.size) / 4
        
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(mach_task_self_, task_flavor_t(TASK_THREAD_TIMES_INFO), $0, &count)
            }
        }
        
        guard result == KERN_SUCCESS else { return 0.0 }
        
        let totalTime = info.user_time.seconds + info.system_time.seconds
        return Double(totalTime) * 100.0 / Double(ProcessInfo.processInfo.systemUptime)
    }
}