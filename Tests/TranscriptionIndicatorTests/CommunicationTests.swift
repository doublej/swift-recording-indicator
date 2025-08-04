import AppKit
import Foundation

class DotTest {
    static func main() {
        print("Creating red dot test...")
        
        let app = NSApplication.shared
        app.setActivationPolicy(.prohibited)
        
        // Create a simple red dot window
        let window = createRedDot(size: 100)
        window.makeKeyAndOrderFront(nil)
        
        print("Red dot should be visible on screen for 10 seconds")
        
        // Keep app alive for 10 seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 10) {
            print("Test complete")
            NSApplication.shared.terminate(nil)
        }
        
        app.run()
    }
    
    static func createRedDot(size: Double) -> NSWindow {
        // Create window
        let window = NSWindow(
            contentRect: CGRect(x: 0, y: 0, width: size, height: size),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        
        // Window properties for visibility
        window.level = .floating
        window.isOpaque = false
        window.backgroundColor = .clear
        window.ignoresMouseEvents = true
        window.collectionBehavior = [.canJoinAllSpaces]
        
        // Create red circle view
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
        
        print("Window created at size \(size)")
        return window
    }
}

DotTest.main()