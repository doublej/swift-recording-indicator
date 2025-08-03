import Foundation
import AppKit
import QuartzCore

enum ShapeType: String, CaseIterable {
    case circle
    case ring
    case orb
}

@MainActor
final class ShapeRenderer {
    
    /// Creates a view with the specified shape using simple NSView approach for reliable visibility
    static func createShapeView(type: ShapeType, size: Double, color: NSColor = .red) -> NSView {
        switch type {
        case .circle:
            return createCircleView(size: size, color: color)
        case .ring:
            return createRingView(size: size, color: color)
        case .orb:
            return createOrbView(size: size, color: color)
        }
    }
    
    /// Creates a solid circle using simple layer background approach (like original working version)
    private static func createCircleView(size: Double, color: NSColor) -> NSView {
        let view = NSView(frame: CGRect(x: 0, y: 0, width: size, height: size))
        view.wantsLayer = true
        view.layer?.backgroundColor = color.cgColor
        view.layer?.cornerRadius = size / 2
        return view
    }
    
    /// Creates a ring (hollow circle) using simple drawing approach
    private static func createRingView(size: Double, color: NSColor) -> NSView {
        let view = RingView(frame: CGRect(x: 0, y: 0, width: size, height: size))
        view.color = color
        view.ringWidth = size * 0.2 // 20% of size for ring width
        return view
    }
    
    /// Creates an orb with gradient effect using simple drawing approach
    private static func createOrbView(size: Double, color: NSColor) -> NSView {
        let view = OrbView(frame: CGRect(x: 0, y: 0, width: size, height: size))
        view.color = color
        return view
    }
}

/// Custom NSView for drawing a ring shape
private class RingView: NSView {
    var color: NSColor = .red
    var ringWidth: Double = 10.0
    
    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        
        let center = CGPoint(x: bounds.width / 2, y: bounds.height / 2)
        let outerRadius = min(bounds.width, bounds.height) / 2
        let innerRadius = outerRadius - ringWidth
        
        context.setFillColor(color.cgColor)
        
        // Draw outer circle
        context.addArc(center: center, radius: outerRadius, startAngle: 0, endAngle: .pi * 2, clockwise: false)
        // Draw inner circle (to create hole)
        context.addArc(center: center, radius: innerRadius, startAngle: 0, endAngle: .pi * 2, clockwise: true)
        
        context.fillPath(using: .evenOdd)
    }
}

/// Custom NSView for drawing an orb with gradient effect
private class OrbView: NSView {
    var color: NSColor = .red
    
    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        
        let center = CGPoint(x: bounds.width / 2, y: bounds.height / 2)
        let radius = min(bounds.width, bounds.height) / 2
        
        // Create radial gradient
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let highlightColor = color.blended(withFraction: 0.4, of: .white) ?? color
        let shadowColor = color.blended(withFraction: 0.3, of: .black) ?? color
        
        let colors = [highlightColor.cgColor, color.cgColor, shadowColor.cgColor]
        let locations: [CGFloat] = [0.0, 0.7, 1.0]
        
        guard let gradient = CGGradient(colorsSpace: colorSpace, colors: colors as CFArray, locations: locations) else {
            // Fallback to solid circle if gradient creation fails
            context.setFillColor(color.cgColor)
            context.addArc(center: center, radius: radius, startAngle: 0, endAngle: .pi * 2, clockwise: false)
            context.fillPath()
            return
        }
        
        // Draw gradient circle
        context.saveGState()
        context.addArc(center: center, radius: radius, startAngle: 0, endAngle: .pi * 2, clockwise: false)
        context.clip()
        
        let gradientCenter = CGPoint(x: center.x - radius * 0.3, y: center.y + radius * 0.3)
        context.drawRadialGradient(gradient, startCenter: gradientCenter, startRadius: 0,
                                 endCenter: center, endRadius: radius, options: [])
        
        context.restoreGState()
    }
}