import Foundation
import ApplicationServices
import CoreGraphics
import Logging
import OSLog
import AppKit

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
            let trusted = AXIsProcessTrusted()
            if !trusted {
                logger.error("Accessibility permission not granted")
                showPermissionGuidance()
            }
            return trusted
        }
    }
    
    @MainActor
    private func showPermissionGuidance() {
        let alert = NSAlert()
        alert.messageText = "Accessibility Permission Required"
        alert.informativeText = "TranscriptionIndicator needs accessibility access to detect text input fields. Please grant permission in System Preferences > Security & Privacy > Privacy > Accessibility."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Open System Preferences")
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
        
        let now = CFAbsoluteTimeGetCurrent()
        guard now - lastNotificationTime > notificationThrottle else {
            return
        }
        lastNotificationTime = now
        
        await detectionQueue.async { [weak self] in
            guard let self = self else { return }
            
            Task {
                await self.processNotification(element: element, notification: notification)
            }
        }
    }
    
    private func processNotification(element: AXUIElement, notification: CFString) async {
        guard isDetecting else { return }
        
        do {
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
        } catch {
            logger.error("Error processing notification: \(error.localizedDescription)")
        }
    }
    
    private func isTextInputElement(_ element: AXUIElement) async -> Bool {
        guard let role = await getElementAttribute(element, kAXRoleAttribute) as? String else {
            return false
        }
        
        let textRoles = [
            kAXTextFieldRole,
            kAXTextAreaRole,
            kAXComboBoxRole,
            kAXStaticTextRole
        ]
        
        return textRoles.contains(role)
    }
    
    private func isSecureField(_ element: AXUIElement) async -> Bool {
        guard let subrole = await getElementAttribute(element, kAXSubroleAttribute) as? String else {
            return false
        }
        
        return subrole == kAXSecureTextFieldSubrole
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
        return await withCheckedContinuation { continuation in
            detectionQueue.async {
                var value: CFTypeRef?
                let result = AXUIElementCopyAttributeValue(element, attribute, &value)
                
                if result == .success {
                    continuation.resume(returning: value)
                } else {
                    continuation.resume(returning: nil)
                }
            }
        }
    }
    
    deinit {
        caretRectContinuation.finish()
    }
}