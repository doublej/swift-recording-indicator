import Foundation
import Logging
import AppKit
import QuartzCore
import ApplicationServices

@MainActor
final class EnhancedCommandProcessor {
    private let logger = Logger(label: "enhanced.command.processor")
    private var window: NSWindow?
    private var isVisible = false
    private var currentShape: ShapeType = .circle
    
    // Caret detection components
    private var accessibilityDetector: AccessibilityTextInputDetector?
    private var caretDetectionTask: Task<Void, Never>?
    private var isCaretMode = false
    private var lastCaretRect: CGRect?
    
    func processCommand(_ line: String) async -> String {
        let command = line.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        
        logger.info("Processing command: '\(command)'")
        
        switch command {
        case "show":
            return await handleShow(shape: .circle, size: 50, enableCaretMode: true)
        case "show circle":
            return await handleShow(shape: .circle, size: 50, enableCaretMode: true)
        case "show ring":
            return await handleShow(shape: .ring, size: 50, enableCaretMode: true)
        case "show orb":
            return await handleShow(shape: .orb, size: 50, enableCaretMode: true)
        case "show center":
            return await handleShow(shape: .circle, size: 50, enableCaretMode: false)
        case "hide":
            return await handleHide()
        case "health":
            return handleHealth()
        case let cmd where cmd.starts(with: "show circle "):
            return await handleShowWithShapeAndSize(cmd, shape: .circle, enableCaretMode: true)
        case let cmd where cmd.starts(with: "show ring "):
            return await handleShowWithShapeAndSize(cmd, shape: .ring, enableCaretMode: true)
        case let cmd where cmd.starts(with: "show orb "):
            return await handleShowWithShapeAndSize(cmd, shape: .orb, enableCaretMode: true)
        case let cmd where cmd.starts(with: "show center "):
            return await handleShowWithSize(cmd, enableCaretMode: false)
        case let cmd where cmd.starts(with: "show "):
            return await handleShowWithSize(cmd, enableCaretMode: true)
        default:
            return "ERROR: Unknown command '\(command)'. Use: show [circle|ring|orb] [size], show center [size], hide, health"
        }
    }
    
    private func handleShow(shape: ShapeType, size: Double, enableCaretMode: Bool = true) async -> String {
        if !isVisible {
            // Try to start caret detection if requested
            if enableCaretMode {
                await startCaretDetection()
            }
            
            createWindow(shape: shape, size: size)
            currentShape = shape
            isVisible = true
            isCaretMode = enableCaretMode
            
            let modeString = isCaretMode ? "at cursor" : "at screen center"
            logger.info("\(shape.rawValue.capitalized) shown with size \(size), mode: \(isCaretMode ? "caret" : "center")")
            return "OK: \(shape.rawValue.capitalized) shown \(modeString) (size \(Int(size)))"
        } else {
            return "OK: Already visible"
        }
    }
    
    private func handleShowWithSize(_ command: String, enableCaretMode: Bool = true) async -> String {
        let parts = command.components(separatedBy: " ")
        let expectedParts = enableCaretMode ? 2 : 3 // "show 50" vs "show center 50"
        let sizeIndex = enableCaretMode ? 1 : 2
        
        guard parts.count == expectedParts, let size = Double(parts[sizeIndex]), size > 0 && size <= 300 else {
            let usage = enableCaretMode ? "'show 50' (size 1-300)" : "'show center 50' (size 1-300)"
            return "ERROR: Invalid size. Use: \(usage)"
        }
        
        if !isVisible {
            // Try to start caret detection if requested
            if enableCaretMode {
                await startCaretDetection()
            }
            
            createWindow(shape: .circle, size: size)
            currentShape = .circle
            isVisible = true
            isCaretMode = enableCaretMode
            
            let modeString = isCaretMode ? "at cursor" : "at screen center"
            logger.info("Circle shown with size \(size), mode: \(isCaretMode ? "caret" : "center")")
            return "OK: Circle shown \(modeString) (size \(Int(size)))"
        } else {
            updateWindowSize(shape: currentShape, size: size)
            logger.info("Updated to size \(size)")
            return "OK: Updated to size \(Int(size))"
        }
    }
    
    private func handleShowWithShapeAndSize(_ command: String, shape: ShapeType, enableCaretMode: Bool = true) async -> String {
        let parts = command.components(separatedBy: " ")
        guard parts.count == 3, let size = Double(parts[2]), size > 0 && size <= 300 else {
            return "ERROR: Invalid size. Use: 'show \(shape.rawValue) 50' (size 1-300)"
        }
        
        if !isVisible {
            // Try to start caret detection if requested
            if enableCaretMode {
                await startCaretDetection()
            }
            
            createWindow(shape: shape, size: size)
            currentShape = shape
            isVisible = true
            isCaretMode = enableCaretMode
            
            let modeString = isCaretMode ? "at cursor" : "at screen center"
            logger.info("\(shape.rawValue.capitalized) shown with size \(size), mode: \(isCaretMode ? "caret" : "center")")
            return "OK: \(shape.rawValue.capitalized) shown \(modeString) (size \(Int(size)))"
        } else {
            updateWindowSize(shape: shape, size: size)
            currentShape = shape
            logger.info("Updated to \(shape.rawValue) size \(size)")
            return "OK: Updated to \(shape.rawValue) size \(Int(size))"
        }
    }
    
    private func handleHide() async -> String {
        if isVisible {
            // Stop caret detection
            await stopCaretDetection()
            
            window?.orderOut(nil)
            window = nil
            
            isVisible = false
            isCaretMode = false
            logger.info("Indicator hidden")
            return "OK: Hidden"
        } else {
            return "OK: Already hidden"
        }
    }
    
    private func handleHealth() -> String {
        let pid = ProcessInfo.processInfo.processIdentifier
        let accessibilityStatus = AXIsProcessTrusted() ? "granted" : "denied"
        let caretModeStatus = isCaretMode ? "enabled" : "disabled"
        return "OK: Alive (PID: \(pid), Accessibility: \(accessibilityStatus), Caret mode: \(caretModeStatus))"
    }
    
    // MARK: - Caret Detection Methods
    
    private func startCaretDetection() async {
        // Don't start if already running
        guard accessibilityDetector == nil else { return }
        
        do {
            let detector = AccessibilityTextInputDetector()
            accessibilityDetector = detector
            
            try await detector.startDetection()
            
            // Start listening for caret changes
            caretDetectionTask = Task { @MainActor in
                for await caretRect in detector.caretRectPublisher {
                    await self.handleCaretRectChange(caretRect)
                }
            }
            
            logger.info("Caret detection started successfully")
        } catch {
            logger.warning("Failed to start caret detection: \(error.localizedDescription)")
            logger.info("Falling back to center positioning")
            accessibilityDetector = nil
            isCaretMode = false
        }
    }
    
    private func stopCaretDetection() async {
        caretDetectionTask?.cancel()
        caretDetectionTask = nil
        
        if let detector = accessibilityDetector {
            await detector.stopDetection()
            accessibilityDetector = nil
        }
        
        lastCaretRect = nil
        logger.debug("Caret detection stopped")
    }
    
    private func handleCaretRectChange(_ caretRect: CGRect?) async {
        guard isVisible, isCaretMode, let window = window else { return }
        
        if let rect = caretRect {
            lastCaretRect = rect
            positionWindowAtCaret(window, caretRect: rect)
            logger.debug("Window positioned at caret: \(rect)")
        } else {
            // Fall back to center positioning when caret is lost
            positionWindowAtCenter(window)
            logger.debug("Caret lost, fallback to center positioning")
        }
    }
    
    // MARK: - Window Management
    
    private func createWindow(shape: ShapeType, size: Double) {
        let newWindow = NSWindow(
            contentRect: CGRect(x: 0, y: 0, width: size, height: size),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        
        // Window properties for visibility
        newWindow.level = .floating
        newWindow.isOpaque = false
        newWindow.backgroundColor = .clear
        newWindow.ignoresMouseEvents = true
        newWindow.collectionBehavior = [.canJoinAllSpaces]
        
        // Create shape view using ShapeRenderer
        let view = ShapeRenderer.createShapeView(type: shape, size: size, color: .red)
        newWindow.contentView = view
        
        // Position window based on mode
        positionWindow(newWindow, size: size)
        
        // Make sure window is visible and stays visible
        newWindow.makeKeyAndOrderFront(nil)
        newWindow.orderFrontRegardless()
        window = newWindow
        
        // Force display and debug
        newWindow.display()
        let modeString = isCaretMode ? "caret mode" : "center mode"
        print("DEBUG: \(shape.rawValue.capitalized) window created at frame: \(newWindow.frame) (\(modeString))")
        print("DEBUG: Window is visible: \(newWindow.isVisible)")
        print("DEBUG: Window level: \(newWindow.level.rawValue)")
    }
    
    private func positionWindow(_ window: NSWindow, size: Double) {
        if isCaretMode, let caretRect = lastCaretRect {
            positionWindowAtCaret(window, caretRect: caretRect)
        } else {
            positionWindowAtCenter(window)
        }
    }
    
    private func positionWindowAtCaret(_ window: NSWindow, caretRect: CGRect) {
        let windowSize = window.frame.size
        
        // Position below the caret with a small offset
        let x = caretRect.midX - windowSize.width / 2
        let y = caretRect.minY - windowSize.height - 5 // 5pt below caret
        
        // Ensure the window stays on screen
        guard let screen = NSScreen.main else {
            positionWindowAtCenter(window)
            return
        }
        
        let screenFrame = screen.visibleFrame
        let clampedX = max(screenFrame.minX, min(x, screenFrame.maxX - windowSize.width))
        let clampedY = max(screenFrame.minY, min(y, screenFrame.maxY - windowSize.height))
        
        window.setFrameOrigin(CGPoint(x: clampedX, y: clampedY))
    }
    
    private func positionWindowAtCenter(_ window: NSWindow) {
        guard let screen = NSScreen.main else { return }
        
        let screenFrame = screen.visibleFrame
        let windowSize = window.frame.size
        let x = screenFrame.midX - windowSize.width / 2
        let y = screenFrame.midY - windowSize.height / 2
        
        window.setFrameOrigin(CGPoint(x: x, y: y))
    }
    
    private func updateWindowSize(shape: ShapeType, size: Double) {
        guard let currentWindow = window else { return }
        
        let currentOrigin = currentWindow.frame.origin
        currentWindow.setFrame(CGRect(x: currentOrigin.x, y: currentOrigin.y, width: size, height: size), display: true)
        
        // Update the shape view using ShapeRenderer
        let shapeView = ShapeRenderer.createShapeView(type: shape, size: size, color: .red)
        currentWindow.contentView = shapeView
    }
}