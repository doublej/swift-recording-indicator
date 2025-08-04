import Foundation
import AppKit

@MainActor final class SimpleCommandProcessor {
    private var window: NSWindow?
    private var isVisible = false
    private var currentShape: IndicatorConfig.Shape = .circle
    private var currentColor: NSColor = .red
    private var currentSize: CGFloat = 50
    private var countdownTimer: Timer?
    private var keepaliveTimer: Timer?
    private var countdownDuration: TimeInterval = 30.0 // Default 30 seconds
    private var keepaliveInterval: TimeInterval = 10.0 // Default 10 seconds
    private var lastKeepaliveTime: Date = Date()
    private var autoCloseEnabled = true // Countdown enabled by default
    
    func processCommand(_ line: String) -> String {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = trimmed.split(separator: " ").map { String($0).lowercased() }
        
        guard !parts.isEmpty else {
            return "ERROR: Empty command"
        }
        
        let command = parts[0]
        
        switch command {
        case "show":
            return handleShow(parts: parts)
        case "hide":
            return handleHide()
        case "shape":
            return handleShape(parts: parts)
        case "color":
            return handleColor(parts: parts)
        case "size":
            return handleSize(parts: parts)
        case "countdown":
            return handleCountdown(parts: parts)
        case "keepalive":
            return handleKeepalive()
        default:
            return "ERROR: Unknown command '\(command)'. Use: show [seconds], hide, shape <type>, color <value>, size <pixels>, countdown <seconds>, keepalive"
        }
    }
    
    private func handleShow(parts: [String]) -> String {
        // Check if duration is specified
        var duration: TimeInterval?
        if parts.count >= 2, let seconds = Double(parts[1]) {
            duration = seconds
        }
        
        if !isVisible {
            createWindow()
            isVisible = true
            
            // Start countdown timer (always enabled by default)
            let finalDuration = duration ?? countdownDuration
            startCountdownTimer(duration: finalDuration)
            return "OK: Indicator shown with \(Int(finalDuration))s countdown"
        } else {
            // Update countdown (always running)
            let finalDuration = duration ?? countdownDuration
            startCountdownTimer(duration: finalDuration)
            return "OK: Already visible, countdown updated to \(Int(finalDuration))s"
        }
    }
    
    private func handleHide() -> String {
        if isVisible {
            stopTimers()
            window?.orderOut(nil)
            window = nil
            isVisible = false
            return "OK: Hidden"
        } else {
            return "OK: Already hidden"
        }
    }
    
    private func handleShape(parts: [String]) -> String {
        guard parts.count == 2 else {
            return "ERROR: Shape command requires argument. Use: shape <circle|square|triangle>"
        }
        
        let shapeArg = parts[1]
        switch shapeArg {
        case "circle":
            currentShape = .circle
            updateVisibleShape()
            return "OK: Shape set to circle"
        case "square":
            currentShape = .ring // Using ring for square representation
            updateVisibleShape()
            return "OK: Shape set to square"
        case "triangle":
            currentShape = .orb // Using orb for triangle representation
            updateVisibleShape()
            return "OK: Shape set to triangle"
        default:
            return "ERROR: Unknown shape '\(shapeArg)'. Use: circle, square, triangle"
        }
    }
    
    private func handleColor(parts: [String]) -> String {
        guard parts.count == 2 else {
            return "ERROR: Color command requires argument. Use: color <name|hex>"
        }
        
        let colorArg = parts[1]
        if let color = parseColor(colorArg) {
            currentColor = color
            updateVisibleShape()
            return "OK: Color set to \(colorArg)"
        } else {
            return "ERROR: Unknown color '\(colorArg)'. Use: red, green, blue, yellow, orange, purple, white, black, or hex like #FF0000"
        }
    }
    
    private func handleSize(parts: [String]) -> String {
        guard parts.count == 2 else {
            return "ERROR: Size command requires argument. Use: size <pixels>"
        }
        
        guard let sizeValue = Double(parts[1]), sizeValue >= 10, sizeValue <= 200 else {
            return "ERROR: Size must be a number between 10 and 200 pixels"
        }
        
        let size = CGFloat(sizeValue)
        
        currentSize = size
        updateVisibleShape()
        return "OK: Size set to \(Int(size)) pixels"
    }
    
    private func parseColor(_ colorString: String) -> NSColor? {
        switch colorString {
        case "red": return .red
        case "green": return .green
        case "blue": return .blue
        case "yellow": return .yellow
        case "orange": return .orange
        case "purple": return .purple
        case "white": return .white
        case "black": return .black
        case "cyan": return .cyan
        case "magenta": return .magenta
        default:
            // Try hex color
            if colorString.hasPrefix("#") && colorString.count == 7 {
                let hex = String(colorString.dropFirst())
                if let rgb = Int(hex, radix: 16) {
                    let red = CGFloat((rgb >> 16) & 0xFF) / 255.0
                    let green = CGFloat((rgb >> 8) & 0xFF) / 255.0
                    let blue = CGFloat(rgb & 0xFF) / 255.0
                    return NSColor(red: red, green: green, blue: blue, alpha: 1.0)
                }
            }
            return nil
        }
    }
    
    private func handleCountdown(parts: [String]) -> String {
        guard parts.count == 2 else {
            return "ERROR: Countdown command requires argument. Use: countdown <seconds>"
        }
        
        guard let seconds = Double(parts[1]), seconds > 0, seconds <= 3600 else {
            return "ERROR: Countdown must be a number between 1 and 3600 seconds"
        }
        
        countdownDuration = seconds
        
        if isVisible {
            startCountdownTimer(duration: seconds)
            return "OK: Countdown updated to \(Int(seconds))s and restarted"
        } else {
            return "OK: Countdown set to \(Int(seconds))s (will start when shown)"
        }
    }
    
    private func handleKeepalive() -> String {
        lastKeepaliveTime = Date()
        
        if !isVisible {
            return "OK: Keepalive received (indicator not visible)"
        }
        
        // Reset countdown timer if running
        if countdownTimer != nil {
            startCountdownTimer(duration: countdownDuration)
            return "OK: Keepalive received, countdown reset"
        } else {
            return "OK: Keepalive received"
        }
    }
    
    private func startCountdownTimer(duration: TimeInterval) {
        stopTimers()
        
        countdownTimer = Timer.scheduledTimer(withTimeInterval: duration, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.handleCountdownExpired()
            }
        }
        
        // Start keepalive monitor
        startKeepaliveMonitor()
    }
    
    private func startKeepaliveMonitor() {
        keepaliveTimer = Timer.scheduledTimer(withTimeInterval: keepaliveInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.checkKeepalive()
            }
        }
    }
    
    private func checkKeepalive() {
        let timeSinceLastKeepalive = Date().timeIntervalSince(lastKeepaliveTime)
        
        if timeSinceLastKeepalive > keepaliveInterval * 2 {
            // No keepalive for too long, close indicator
            handleCountdownExpired()
        }
    }
    
    private func handleCountdownExpired() {
        if isVisible {
            stopTimers()
            window?.orderOut(nil)
            window = nil
            isVisible = false
            
            // Exit the application
            NSApplication.shared.terminate(nil)
        }
    }
    
    private func stopTimers() {
        countdownTimer?.invalidate()
        countdownTimer = nil
        keepaliveTimer?.invalidate()
        keepaliveTimer = nil
    }
    
    private func updateVisibleShape() {
        if isVisible {
            window?.orderOut(nil)
            window = nil
            createWindow()
        }
    }
    
    private func createWindow() {
        let size = currentSize
        let window = NSWindow(
            contentRect: CGRect(x: 0, y: 0, width: size, height: size),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        
        window.level = .floating
        window.isOpaque = false
        window.backgroundColor = .clear
        window.ignoresMouseEvents = true
        window.collectionBehavior = [.canJoinAllSpaces]
        
        // Create view based on current shape
        let view = NSView(frame: CGRect(x: 0, y: 0, width: size, height: size))
        view.wantsLayer = true
        
        switch currentShape {
        case .circle:
            view.layer?.backgroundColor = currentColor.cgColor
            view.layer?.cornerRadius = size / 2
        case .ring: // Square
            view.layer?.backgroundColor = currentColor.cgColor
            view.layer?.cornerRadius = 0
        case .orb: // Triangle
            view.layer?.backgroundColor = NSColor.clear.cgColor
            let triangleLayer = createTriangleLayer(size: size, color: currentColor)
            view.layer?.addSublayer(triangleLayer)
        case .custom:
            view.layer?.backgroundColor = currentColor.cgColor
            view.layer?.cornerRadius = size / 2
        }
        
        window.contentView = view
        
        // Position at screen center
        if let screen = NSScreen.main {
            let screenFrame = screen.visibleFrame
            let x = screenFrame.midX - size / 2
            let y = screenFrame.midY - size / 2
            window.setFrameOrigin(CGPoint(x: x, y: y))
        }
        
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
        self.window = window
    }
    
    private func createTriangleLayer(size: CGFloat, color: NSColor) -> CAShapeLayer {
        let layer = CAShapeLayer()
        let path = CGMutablePath()
        
        // Create triangle path (equilateral triangle)
        let height = size * 0.866 // sqrt(3)/2 for equilateral triangle
        let centerX = size / 2
        let centerY = size / 2
        
        // Top point
        path.move(to: CGPoint(x: centerX, y: centerY + height / 2))
        // Bottom left
        path.addLine(to: CGPoint(x: centerX - size / 2, y: centerY - height / 2))
        // Bottom right
        path.addLine(to: CGPoint(x: centerX + size / 2, y: centerY - height / 2))
        // Close path
        path.closeSubpath()
        
        layer.path = path
        layer.fillColor = color.cgColor
        layer.frame = CGRect(x: 0, y: 0, width: size, height: size)
        
        return layer
    }
}