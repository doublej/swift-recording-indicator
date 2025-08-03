import Foundation
import Logging
import AppKit
import QuartzCore

@MainActor
final class SimpleCommandProcessor {
    private let logger = Logger(label: "simple.command.processor")
    private var window: NSWindow?
    private var isVisible = false
    private var currentShape: ShapeType = .circle
    private var animationController: AnimationController?
    private let animationConfig: AnimationConfig = .default
    
    func processCommand(_ line: String) async -> String {
        let command = line.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        
        logger.info("Processing command: '\(command)'")
        
        switch command {
        case "show":
            return await handleShow(shape: .circle, size: 50)
        case "show circle":
            return await handleShow(shape: .circle, size: 50)
        case "show ring":
            return await handleShow(shape: .ring, size: 50)
        case "show orb":
            return await handleShow(shape: .orb, size: 50)
        case "hide":
            return await handleHide()
        case "health":
            return handleHealth()
        case let cmd where cmd.starts(with: "show circle "):
            return await handleShowWithShapeAndSize(cmd, shape: .circle)
        case let cmd where cmd.starts(with: "show ring "):
            return await handleShowWithShapeAndSize(cmd, shape: .ring)
        case let cmd where cmd.starts(with: "show orb "):
            return await handleShowWithShapeAndSize(cmd, shape: .orb)
        case let cmd where cmd.starts(with: "show "):
            return await handleShowWithSize(cmd)
        default:
            return "ERROR: Unknown command '\(command)'. Use: show [circle|ring|orb] [size], hide, health"
        }
    }
    
    private func handleShow(shape: ShapeType, size: Double) async -> String {
        if !isVisible {
            createWindow(shape: shape, size: size)
            currentShape = shape
            isVisible = true
            
            logger.info("\(shape.rawValue.capitalized) shown with size \(size)")
            return "OK: \(shape.rawValue.capitalized) shown at cursor (size \(Int(size)))"
        } else {
            return "OK: Already visible"
        }
    }
    
    private func handleShowWithSize(_ command: String) async -> String {
        let parts = command.components(separatedBy: " ")
        guard parts.count == 2, let size = Double(parts[1]), size > 0 && size <= 300 else {
            return "ERROR: Invalid size. Use: 'show 50' (size 1-300)"
        }
        
        if !isVisible {
            createWindow(shape: .circle, size: size)
            currentShape = .circle
            isVisible = true
            logger.info("Circle shown with size \(size)")
            return "OK: Circle shown at cursor (size \(Int(size)))"
        } else {
            updateWindowSize(shape: currentShape, size: size)
            logger.info("Updated to size \(size)")
            return "OK: Updated to size \(Int(size))"
        }
    }
    
    private func handleShowWithShapeAndSize(_ command: String, shape: ShapeType) async -> String {
        let parts = command.components(separatedBy: " ")
        guard parts.count == 3, let size = Double(parts[2]), size > 0 && size <= 300 else {
            return "ERROR: Invalid size. Use: 'show \(shape.rawValue) 50' (size 1-300)"
        }
        
        if !isVisible {
            createWindow(shape: shape, size: size)
            currentShape = shape
            isVisible = true
            logger.info("\(shape.rawValue.capitalized) shown with size \(size)")
            return "OK: \(shape.rawValue.capitalized) shown at cursor (size \(Int(size)))"
        } else {
            updateWindowSize(shape: shape, size: size)
            currentShape = shape
            logger.info("Updated to \(shape.rawValue) size \(size)")
            return "OK: Updated to \(shape.rawValue) size \(Int(size))"
        }
    }
    
    private func handleHide() async -> String {
        if isVisible {
            window?.orderOut(nil)
            window = nil
            isVisible = false
            logger.info("Indicator hidden")
            return "OK: Hidden"
        } else {
            return "OK: Already hidden"
        }
    }
    
    private func handleHealth() -> String {
        let pid = ProcessInfo.processInfo.processIdentifier
        return "OK: Alive (PID: \(pid))"
    }
    
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
        
        // Position at screen center
        if let screen = NSScreen.main {
            let screenFrame = screen.visibleFrame
            let x = screenFrame.midX - size / 2
            let y = screenFrame.midY - size / 2
            newWindow.setFrameOrigin(CGPoint(x: x, y: y))
        }
        
        // Make sure window is visible and stays visible
        newWindow.makeKeyAndOrderFront(nil)
        newWindow.orderFrontRegardless()
        window = newWindow
        
        // Force display and debug
        newWindow.display()
        print("DEBUG: \(shape.rawValue.capitalized) window created at frame: \(newWindow.frame)")
        print("DEBUG: Window is visible: \(newWindow.isVisible)")
        print("DEBUG: Window level: \(newWindow.level.rawValue)")
        
        // Debug: Keep alive for 10 seconds to see the window
        DispatchQueue.main.asyncAfter(deadline: .now() + 10) {
            print("DEBUG: Window should still be visible")
            if let w = self.window {
                print("DEBUG: Window still exists: \(w.isVisible)")
            }
        }
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