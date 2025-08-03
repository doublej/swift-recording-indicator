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
    
    /// Creates a view with the specified shape using CAShapeLayer for optimal performance
    static func createShapeView(type: ShapeType, size: Double, color: NSColor = .red) -> NSView {
        let view = NSView(frame: CGRect(x: 0, y: 0, width: size, height: size))
        view.wantsLayer = true
        view.layer = CALayer()
        view.layer?.backgroundColor = NSColor.clear.cgColor
        
        switch type {
        case .circle:
            addCircleLayer(to: view, size: size, color: color)
        case .ring:
            addRingLayer(to: view, size: size, color: color)
        case .orb:
            addOrbLayer(to: view, size: size, color: color)
        }
        
        return view
    }
    
    /// Creates a solid circle using CAShapeLayer
    private static func addCircleLayer(to view: NSView, size: Double, color: NSColor) {
        let shapeLayer = CAShapeLayer()
        let path = CGPath(ellipseIn: CGRect(x: 0, y: 0, width: size, height: size), transform: nil)
        
        shapeLayer.path = path
        shapeLayer.fillColor = color.cgColor
        shapeLayer.strokeColor = nil
        shapeLayer.frame = CGRect(x: 0, y: 0, width: size, height: size)
        
        // Optimize for performance
        shapeLayer.shouldRasterize = true
        shapeLayer.rasterizationScale = NSScreen.main?.backingScaleFactor ?? 2.0
        
        view.layer?.addSublayer(shapeLayer)
    }
    
    /// Creates a ring (hollow circle) using CAShapeLayer
    private static func addRingLayer(to view: NSView, size: Double, color: NSColor) {
        let shapeLayer = CAShapeLayer()
        let outerRadius = size / 2
        let innerRadius = outerRadius * 0.6 // 60% inner radius for visible ring
        let center = CGPoint(x: size / 2, y: size / 2)
        
        let path = CGMutablePath()
        path.addArc(center: center, radius: outerRadius, startAngle: 0, endAngle: .pi * 2, clockwise: false)
        path.addArc(center: center, radius: innerRadius, startAngle: 0, endAngle: .pi * 2, clockwise: true)
        
        shapeLayer.path = path
        shapeLayer.fillColor = color.cgColor
        shapeLayer.fillRule = .evenOdd
        shapeLayer.strokeColor = nil
        shapeLayer.frame = CGRect(x: 0, y: 0, width: size, height: size)
        
        // Optimize for performance
        shapeLayer.shouldRasterize = true
        shapeLayer.rasterizationScale = NSScreen.main?.backingScaleFactor ?? 2.0
        
        view.layer?.addSublayer(shapeLayer)
    }
    
    /// Creates an orb with gradient effect using CAShapeLayer and CAGradientLayer
    private static func addOrbLayer(to view: NSView, size: Double, color: NSColor) {
        // Base circle layer
        let shapeLayer = CAShapeLayer()
        let path = CGPath(ellipseIn: CGRect(x: 0, y: 0, width: size, height: size), transform: nil)
        
        shapeLayer.path = path
        shapeLayer.frame = CGRect(x: 0, y: 0, width: size, height: size)
        
        // Create gradient layer for orb effect
        let gradientLayer = CAGradientLayer()
        gradientLayer.frame = CGRect(x: 0, y: 0, width: size, height: size)
        gradientLayer.type = .radial
        gradientLayer.startPoint = CGPoint(x: 0.3, y: 0.3) // Offset for 3D effect
        gradientLayer.endPoint = CGPoint(x: 0.8, y: 0.8)
        
        // Create gradient colors from the base color
        let highlightColor = color.blended(withFraction: 0.4, of: .white) ?? color
        let shadowColor = color.blended(withFraction: 0.3, of: .black) ?? color
        
        gradientLayer.colors = [
            highlightColor.cgColor,
            color.cgColor,
            shadowColor.cgColor
        ]
        gradientLayer.locations = [0.0, 0.7, 1.0]
        
        // Mask the gradient with the circle shape
        gradientLayer.mask = shapeLayer
        
        // Optimize for performance
        gradientLayer.shouldRasterize = true
        gradientLayer.rasterizationScale = NSScreen.main?.backingScaleFactor ?? 2.0
        
        view.layer?.addSublayer(gradientLayer)
        
        // Add subtle outer glow for orb effect
        let glowLayer = CAShapeLayer()
        glowLayer.path = path
        glowLayer.fillColor = nil
        glowLayer.strokeColor = color.cgColor
        glowLayer.lineWidth = 2.0
        glowLayer.frame = CGRect(x: 0, y: 0, width: size, height: size)
        
        // Add glow effect
        glowLayer.shadowColor = color.cgColor
        glowLayer.shadowRadius = size * 0.1
        glowLayer.shadowOpacity = 0.5
        glowLayer.shadowOffset = CGSize.zero
        
        // Optimize for performance
        glowLayer.shouldRasterize = true
        glowLayer.rasterizationScale = NSScreen.main?.backingScaleFactor ?? 2.0
        
        view.layer?.insertSublayer(glowLayer, at: 0)
    }
}