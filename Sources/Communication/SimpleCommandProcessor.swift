import Foundation
import AppKit

@MainActor final class SimpleCommandProcessor {
    private var window: NSWindow?
    private var isVisible = false
    
    func processCommand(_ line: String) -> String {
        let command = line.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        
        switch command {
        case "show":
            return handleShow()
        case "hide":
            return handleHide()
        default:
            return "ERROR: Unknown command '\(command)'. Use: show, hide"
        }
    }
    
    private func handleShow() -> String {
        if !isVisible {
            createWindow()
            isVisible = true
            return "OK: Circle shown"
        } else {
            return "OK: Already visible"
        }
    }
    
    private func handleHide() -> String {
        if isVisible {
            window?.orderOut(nil)
            window = nil
            isVisible = false
            return "OK: Hidden"
        } else {
            return "OK: Already hidden"
        }
    }
    
    private func createWindow() {
        let size: CGFloat = 50
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
        
        // Create simple red circle view
        let view = NSView(frame: CGRect(x: 0, y: 0, width: size, height: size))
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.red.cgColor
        view.layer?.cornerRadius = size / 2
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
}