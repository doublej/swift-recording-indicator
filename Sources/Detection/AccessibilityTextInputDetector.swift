import Foundation
import ApplicationServices
import CoreGraphics
import Logging
import OSLog
import QuartzCore

actor AccessibilityTextInputDetector: TextInputDetecting {
    private let logger = Logger(label: "accessibility.detector")
    private let signpostLogger = OSLog(subsystem: "com.transcription.indicator", category: "accessibility")
    
    private var observer: AXObserver?
    private var isDetecting = false
    private var retryCount = 0
    private let maxRetries = 3
    
    private let caretRectContinuation: AsyncStream<CGRect?>.Continuation
    let caretRectPublisher: AsyncStream<CGRect?>
    
    private var lastCaretRect: CGRect?
    private var lastNotificationTime: CFAbsoluteTime = 0
    private let notificationThrottle: CFAbsoluteTime = 0.016 // ~60fps
    
    // Event coalescing with adaptive timing
    private var pendingNotification: (element: AXUIElement, notification: CFString)?
    private var coalescingTimer: DispatchSourceTimer?
    private let coalescingDelay: TimeInterval = 0.016 // 16ms base delay
    private var adaptiveDelay: TimeInterval = 0.016
    private var consecutiveNotifications = 0
    
    // Multi-level cache for performance
    private var elementAttributeCache = [AXUIElement: [String: CFTypeRef]]()
    private var elementRoleCache = [AXUIElement: String]()
    private var secureFieldCache = [AXUIElement: Bool]()
    private var cacheValidUntil: CFAbsoluteTime = 0
    private let cacheLifetime: CFAbsoluteTime = 0.5 // 500ms cache
    
    // Performance monitoring
    private var averageProcessingTime: CFAbsoluteTime = 0
    private var processingTimeCount = 0
    
    private let detectionQueue = DispatchQueue(label: "accessibility.detection", qos: .userInteractive)
    
    init() {
        let (stream, continuation) = AsyncStream<CGRect?>.makeStream()
        self.caretRectPublisher = stream
        self.caretRectContinuation = continuation
    }
    
    func startDetection() async throws {
        guard !isDetecting else { return }
        
        let signpostID = OSSignpostID(log: signpostLogger)
        os_signpost(.begin, log: signpostLogger, name: "StartDetection", signpostID: signpostID)
        
        defer {
            os_signpost(.end, log: signpostLogger, name: "StartDetection", signpostID: signpostID)
        }
        
        logger.info("Starting accessibility detection")
        
        guard await checkPermissions() else {
            throw TranscriptionIndicatorError.permissionDenied(permission: "Accessibility")
        }
        
        do {
            try await setupAccessibilityObserver()
            isDetecting = true
            retryCount = 0
            logger.info("Accessibility detection started successfully")
        } catch {
            guard retryCount < maxRetries else {
                throw TranscriptionIndicatorError.accessibilityError("Failed to start after \(maxRetries) retries")
            }
            
            retryCount += 1
            let delay = UInt64(pow(2.0, Double(retryCount)) * 1_000_000_000) // Exponential backoff
            try await Task.sleep(nanoseconds: delay)
            
            logger.warning("Retrying accessibility detection (\(retryCount)/\(maxRetries))")
            try await startDetection()
        }
    }
    
    func stopDetection() async {
        guard isDetecting else { return }
        
        logger.info("Stopping accessibility detection")
        
        await MainActor.run {
            if let observer = observer {
                CFRunLoopRemoveSource(
                    CFRunLoopGetMain(),
                    AXObserverGetRunLoopSource(observer),
                    .defaultMode
                )
            }
        }
        
        observer = nil
        isDetecting = false
        caretRectContinuation.finish()
        
        logger.info("Accessibility detection stopped")
    }
    
    private func checkPermissions() async -> Bool {
        await MainActor.run {
            // First check if accessibility is enabled system-wide
            let accessibilityEnabled = AXAPIEnabled()
            if !accessibilityEnabled {
                logger.error("Accessibility API is disabled system-wide")
                showSystemAccessibilityGuidance()
                return false
            }
            
            // Check if our process is trusted
            let trusted = AXIsProcessTrusted()
            if !trusted {
                logger.error("Accessibility permission not granted for this application")
                showPermissionGuidance()
                return false
            }
            
            logger.info("Accessibility permissions verified successfully")
            return true
        }
    }
    
    @MainActor
    private func showPermissionGuidance() {
        let alert = NSAlert()
        alert.messageText = "Accessibility Permission Required"
        alert.informativeText = """
        TranscriptionIndicator needs accessibility access to detect text input fields and position the visual indicator accurately.

        Steps to grant permission:
        1. Open System Settings (or System Preferences)
        2. Go to Privacy & Security → Accessibility
        3. Enable TranscriptionIndicator

        No text content is read or stored by this application.
        """
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "Cancel")
        
        if alert.runModal() == .alertFirstButtonReturn {
            // Try modern System Settings first (macOS 13+), fallback to System Preferences
            let modernURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
            let legacyURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
            
            if !NSWorkspace.shared.open(modernURL) {
                NSWorkspace.shared.open(legacyURL)
            }
        }
    }
    
    @MainActor
    private func showSystemAccessibilityGuidance() {
        let alert = NSAlert()
        alert.messageText = "Accessibility API Disabled"
        alert.informativeText = """
        The system-wide Accessibility API is disabled. This is required for TranscriptionIndicator to function.

        To enable:
        1. Open System Settings (or System Preferences)
        2. Go to Privacy & Security → Accessibility
        3. Enable "Enable access for assistive devices"

        You may need administrator privileges to change this setting.
        """
        alert.alertStyle = .critical
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "Cancel")
        
        if alert.runModal() == .alertFirstButtonReturn {
            let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
            NSWorkspace.shared.open(url)
        }
    }
    
    private func setupAccessibilityObserver() async throws {
        return try await withCheckedThrowingContinuation { continuation in
            Task { @MainActor in
                do {
                    let pid = ProcessInfo.processInfo.processIdentifier
                    
                    var observer: AXObserver?
                    let result = AXObserverCreate(pid, { observer, element, notification, userData in
                        guard let userData = userData else { return }
                        
                        let detector = Unmanaged<AccessibilityTextInputDetector>.fromOpaque(userData).takeUnretainedValue()
                        
                        Task {
                            await detector.handleAccessibilityNotification(element: element, notification: notification)
                        }
                    }, &observer)
                    
                    guard result == .success, let axObserver = observer else {
                        throw TranscriptionIndicatorError.accessibilityError("Failed to create observer: \(result)")
                    }
                    
                    self.observer = axObserver
                    
                    CFRunLoopAddSource(
                        CFRunLoopGetMain(),
                        AXObserverGetRunLoopSource(axObserver),
                        .defaultMode
                    )
                    
                    let systemElement = AXUIElementCreateSystemWide()
                    let addResult = AXObserverAddNotification(
                        axObserver,
                        systemElement,
                        kAXFocusedUIElementChangedNotification,
                        Unmanaged.passUnretained(self).toOpaque()
                    )
                    
                    guard addResult == .success else {
                        throw TranscriptionIndicatorError.accessibilityError("Failed to add notification: \(addResult)")
                    }
                    
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    private func handleAccessibilityNotification(element: AXUIElement, notification: CFString) async {
        let signpostID = OSSignpostID(log: signpostLogger)
        os_signpost(.begin, log: signpostLogger, name: "HandleNotification", signpostID: signpostID)
        
        defer {
            os_signpost(.end, log: signpostLogger, name: "HandleNotification", signpostID: signpostID)
        }
        
        // Event coalescing - store the latest notification
        pendingNotification = (element, notification)
        
        // Cancel existing timer
        coalescingTimer?.cancel()
        
        // Create new timer for coalesced processing
        let timer = DispatchSource.makeTimerSource(queue: detectionQueue)
        timer.schedule(deadline: .now() + coalescingDelay)
        timer.setEventHandler { [weak self] in
            guard let self = self else { return }
            Task {
                if let pending = await self.pendingNotification {
                    await self.processNotification(element: pending.element, notification: pending.notification)
                    await self.clearPendingNotification()
                }
            }
        }
        timer.resume()
        coalescingTimer = timer
        
        PerformanceMonitor.shared.recordEvent(coalesced: pendingNotification != nil)
    }
    
    private func processNotification(element: AXUIElement, notification: CFString) async {
        guard isDetecting else { return }
        
        let measureStart = CFAbsoluteTimeGetCurrent()
        
        do {
            // Clear cache if expired using optimized method
            clearCacheIfExpired()
            
            if await isTextInputElement(element) && !(await isSecureField(element)) {
                if let caretRect = await extractCaretRect(from: element) {
                    if caretRect != lastCaretRect {
                        lastCaretRect = caretRect
                        caretRectContinuation.yield(caretRect)
                        
                        logger.debug("Caret rect detected: \(caretRect.debugDescription)")
                    }
                }
            } else {
                if lastCaretRect != nil {
                    lastCaretRect = nil
                    caretRectContinuation.yield(nil)
                    
                    logger.debug("Text input lost")
                }
            }
            
            let processingTime = CFAbsoluteTimeGetCurrent() - measureStart
            updatePerformanceMetrics(processingTime: processingTime)
            
            if processingTime > 0.008 { // 8ms threshold for warnings
                logger.warning("Slow notification processing: \(String(format: "%.2f", processingTime * 1000))ms")
            }
        } catch {
            logger.error("Error processing notification: \(error.localizedDescription)")
        }
    }
    
    private func isTextInputElement(_ element: AXUIElement) async -> Bool {
        // Check cache first
        if let cachedRole = elementRoleCache[element] {
            let textRoles = [
                kAXTextFieldRole,
                kAXTextAreaRole,
                kAXComboBoxRole,
                kAXStaticTextRole
            ]
            return textRoles.contains(cachedRole)
        }
        
        // Get role from accessibility API
        guard let role = await getElementAttribute(element, kAXRoleAttribute) as? String else {
            return false
        }
        
        // Cache the result
        elementRoleCache[element] = role
        
        let textRoles = [
            kAXTextFieldRole,
            kAXTextAreaRole,
            kAXComboBoxRole,
            kAXStaticTextRole
        ]
        
        return textRoles.contains(role)
    }
    
    private func isSecureField(_ element: AXUIElement) async -> Bool {
        // Check cache first
        if let cached = secureFieldCache[element] {
            return cached
        }
        
        // Get subrole from accessibility API
        guard let subrole = await getElementAttribute(element, kAXSubroleAttribute) as? String else {
            secureFieldCache[element] = false
            return false
        }
        
        let isSecure = subrole == kAXSecureTextFieldSubrole
        secureFieldCache[element] = isSecure
        return isSecure
    }
    
    private func extractCaretRect(from element: AXUIElement) async -> CGRect? {
        if let bounds = await getBoundsForSelectedRange(element) {
            return bounds
        }
        
        if let lineRect = await getInsertionPointRect(element) {
            return lineRect
        }
        
        return await getElementFrameWithHeuristics(element)
    }
    
    private func getBoundsForSelectedRange(_ element: AXUIElement) async -> CGRect? {
        guard let range = await getElementAttribute(element, kAXSelectedTextRangeAttribute) as CFTypeRef? else {
            return nil
        }
        
        var bounds: CFTypeRef?
        let result = AXUIElementCopyParameterizedAttributeValue(
            element,
            kAXBoundsForRangeParameterizedAttribute,
            range,
            &bounds
        )
        
        guard result == .success,
              let value = bounds,
              CFGetTypeID(value) == AXValueGetTypeID() else {
            return nil
        }
        
        var rect = CGRect.zero
        guard AXValueGetValue(value as! AXValue, .cgRect, &rect) else {
            return nil
        }
        
        return rect
    }
    
    private func getInsertionPointRect(_ element: AXUIElement) async -> CGRect? {
        guard let lineNumber = await getElementAttribute(element, kAXInsertionPointLineNumberAttribute) as? Int else {
            return nil
        }
        
        return await getElementAttribute(element, kAXFrameAttribute) as? CGRect
    }
    
    private func getElementFrameWithHeuristics(_ element: AXUIElement) async -> CGRect? {
        guard var frame = await getElementAttribute(element, kAXFrameAttribute) as? CGRect else {
            return nil
        }
        
        frame.origin.y += frame.height * 0.8
        frame.size.height = 2
        
        return frame
    }
    
    private func getElementAttribute(_ element: AXUIElement, _ attribute: CFString) async -> CFTypeRef? {
        // Check cache first
        let cacheKey = String(describing: attribute)
        if let cached = elementAttributeCache[element]?[cacheKey],
           CFAbsoluteTimeGetCurrent() < cacheValidUntil {
            return cached
        }
        
        return await withCheckedContinuation { continuation in
            detectionQueue.async { [weak self] in
                var value: CFTypeRef?
                let result = AXUIElementCopyAttributeValue(element, attribute, &value)
                
                if result == .success {
                    // Cache the result
                    if let self = self {
                        if self.elementAttributeCache[element] == nil {
                            self.elementAttributeCache[element] = [:]
                        }
                        self.elementAttributeCache[element]?[cacheKey] = value
                        self.cacheValidUntil = CFAbsoluteTimeGetCurrent() + self.cacheLifetime
                    }
                    continuation.resume(returning: value)
                } else {
                    continuation.resume(returning: nil)
                }
            }
        }
    }
    
    private func clearPendingNotification() async {
        pendingNotification = nil
    }
    
    private func clearCacheIfExpired() {
        let now = CFAbsoluteTimeGetCurrent()
        if now > cacheValidUntil {
            elementAttributeCache.removeAll()
            elementRoleCache.removeAll()
            secureFieldCache.removeAll()
            cacheValidUntil = now + cacheLifetime
            logger.debug("Cleared expired accessibility caches")
        }
    }
    
    private func updatePerformanceMetrics(processingTime: CFAbsoluteTime) {
        processingTimeCount += 1
        averageProcessingTime = ((averageProcessingTime * Double(processingTimeCount - 1)) + processingTime) / Double(processingTimeCount)
        
        // Adaptive delay adjustment based on processing time
        if averageProcessingTime > 0.008 { // 8ms threshold
            adaptiveDelay = min(0.032, adaptiveDelay * 1.1) // Increase delay
        } else if averageProcessingTime < 0.004 { // 4ms threshold
            adaptiveDelay = max(0.008, adaptiveDelay * 0.9) // Decrease delay
        }
        
        // Log performance metrics periodically
        if processingTimeCount % 100 == 0 {
            logger.debug("AX performance: avg \(String(format: "%.2f", averageProcessingTime * 1000))ms, adaptive delay: \(String(format: "%.1f", adaptiveDelay * 1000))ms")
        }
    }
    
    deinit {
        coalescingTimer?.cancel()
        caretRectContinuation.finish()
        logger.info("AccessibilityTextInputDetector deinitialized - processed \(processingTimeCount) notifications")
    }
}