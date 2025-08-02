import Foundation
import OSLog
import Logging

/// Efficient event coalescer that batches rapid events to reduce processing overhead
actor EventCoalescer<Event: Sendable> {
    private let logger = Logger(label: "event.coalescer")
    private let signpostLogger = OSLog(subsystem: "com.transcription.indicator", category: "coalescing")
    
    private var pendingEvent: Event?
    private var coalescingTimer: DispatchSourceTimer?
    private let coalescingDelay: TimeInterval
    private let queue: DispatchQueue
    private let processor: @Sendable (Event) async -> Void
    
    private var eventCount = 0
    private var coalescedCount = 0
    
    init(
        delay: TimeInterval = 0.016, // 16ms default
        queue: DispatchQueue = .init(label: "event.coalescer", qos: .userInteractive),
        processor: @escaping @Sendable (Event) async -> Void
    ) {
        self.coalescingDelay = delay
        self.queue = queue
        self.processor = processor
    }
    
    func submit(_ event: Event) async {
        eventCount += 1
        
        // Cancel existing timer
        coalescingTimer?.cancel()
        
        // Store the latest event
        if pendingEvent != nil {
            coalescedCount += 1
            PerformanceMonitor.shared.recordEvent(coalesced: true)
        } else {
            PerformanceMonitor.shared.recordEvent(coalesced: false)
        }
        
        pendingEvent = event
        
        // Schedule processing
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + coalescingDelay)
        timer.setEventHandler { [weak self] in
            Task {
                await self?.processPendingEvent()
            }
        }
        timer.resume()
        coalescingTimer = timer
    }
    
    func flush() async {
        coalescingTimer?.cancel()
        coalescingTimer = nil
        await processPendingEvent()
    }
    
    private func processPendingEvent() async {
        guard let event = pendingEvent else { return }
        
        let signpostID = OSSignpostID(log: signpostLogger)
        os_signpost(.begin, log: signpostLogger, name: "ProcessCoalescedEvent", signpostID: signpostID)
        
        pendingEvent = nil
        await processor(event)
        
        os_signpost(.end, log: signpostLogger, name: "ProcessCoalescedEvent", signpostID: signpostID)
    }
    
    func getStatistics() -> (total: Int, coalesced: Int, rate: Double) {
        let rate = eventCount > 0 ? Double(coalescedCount) / Double(eventCount) : 0
        return (eventCount, coalescedCount, rate)
    }
    
    deinit {
        coalescingTimer?.cancel()
    }
}

/// Specialized event coalescer for CGRect changes with tolerance
actor RectCoalescer {
    private let coalescer: EventCoalescer<CGRect>
    private var lastRect: CGRect?
    private let tolerance: CGFloat
    
    init(
        delay: TimeInterval = 0.016,
        tolerance: CGFloat = 0.5,
        processor: @escaping @Sendable (CGRect) async -> Void
    ) {
        self.tolerance = tolerance
        self.coalescer = EventCoalescer(delay: delay, processor: processor)
    }
    
    func submit(_ rect: CGRect) async {
        // Only submit if rect changed significantly
        if let last = lastRect {
            let deltaX = abs(rect.origin.x - last.origin.x)
            let deltaY = abs(rect.origin.y - last.origin.y)
            let deltaW = abs(rect.size.width - last.size.width)
            let deltaH = abs(rect.size.height - last.size.height)
            
            if deltaX < tolerance && deltaY < tolerance && 
               deltaW < tolerance && deltaH < tolerance {
                // Rect didn't change significantly, skip
                return
            }
        }
        
        lastRect = rect
        await coalescer.submit(rect)
    }
    
    func flush() async {
        await coalescer.flush()
    }
}