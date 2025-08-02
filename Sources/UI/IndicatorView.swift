import AppKit
import QuartzCore
import CoreGraphics
import Logging

@MainActor
final class IndicatorView: NSView {
    private let logger = Logger(label: "indicator.view")
    
    private var shapeLayer: CAShapeLayer?
    private var animationController: AnimationController?
    private var currentConfig: IndicatorConfig?
    
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupView()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupView()
    }
    
    private func setupView() {
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        layer?.contentsScale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2.0
        
        layer?.actions = [
            "position": NSNull(),
            "bounds": NSNull(),
            "opacity": NSNull()
        ]
        
        animationController = AnimationController()
    }
    
    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        layer?.contentsScale = window?.backingScaleFactor ?? 2.0
    }
    
    func updateConfig(_ config: IndicatorConfig) {
        currentConfig = config
        
        if shapeLayer == nil {
            createShapeLayer(for: config)
        }
        
        updateShapeLayer(with: config)
        animationController?.updateConfig(config.animations)
        animationController?.setTargetLayer(shapeLayer!)
    }
    
    func show() {
        guard let layer = shapeLayer else { return }
        
        layer.isHidden = false
        animationController?.transitionTo(.appearing) { [weak self] in
            self?.animationController?.transitionTo(.idle)
        }
        
        logger.debug("Indicator view shown")
    }
    
    func hide(completion: @escaping () -> Void) {
        animationController?.transitionTo(.disappearing) { [weak self] in
            self?.shapeLayer?.isHidden = true
            completion()
        }
        
        logger.debug("Indicator view hidden")
    }
    
    private func createShapeLayer(for config: IndicatorConfig) {
        let newLayer = CAShapeLayer()
        newLayer.frame = bounds
        
        layer?.addSublayer(newLayer)
        shapeLayer = newLayer
        
        logger.debug("Shape layer created for shape: \(config.shape.rawValue)")
    }
    
    private func updateShapeLayer(with config: IndicatorConfig) {
        guard let shapeLayer = shapeLayer else { return }
        
        let size = config.size
        let bounds = CGRect(x: 0, y: 0, width: size, height: size)
        
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        
        shapeLayer.bounds = bounds
        shapeLayer.position = CGPoint(x: bounds.midX, y: bounds.midY)
        
        let path = createPath(for: config.shape, size: size)
        shapeLayer.path = path
        
        let primaryColor = parseColor(config.colors.primary, alpha: config.colors.alphaPrimary)
        shapeLayer.fillColor = primaryColor.cgColor
        
        if config.shape == .ring {
            shapeLayer.fillColor = NSColor.clear.cgColor
            let secondaryColor = parseColor(config.colors.secondary, alpha: config.colors.alphaSecondary)
            shapeLayer.strokeColor = secondaryColor.cgColor
            shapeLayer.lineWidth = size * 0.1
        }
        
        shapeLayer.opacity = Float(config.opacity)
        
        CATransaction.commit()
        
        logger.debug("Shape layer updated")
    }
    
    private func createPath(for shape: IndicatorConfig.Shape, size: Double) -> CGPath {
        let rect = CGRect(x: 0, y: 0, width: size, height: size)
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = size / 2.0
        
        switch shape {
        case .circle:
            return CGPath(ellipseIn: rect, transform: nil)
            
        case .ring:
            let path = CGMutablePath()
            let outerRadius = radius
            let innerRadius = radius * 0.6
            
            path.addArc(center: center, radius: outerRadius, startAngle: 0, endAngle: .pi * 2, clockwise: false)
            path.addArc(center: center, radius: innerRadius, startAngle: 0, endAngle: .pi * 2, clockwise: true)
            
            return path
            
        case .orb:
            let path = CGMutablePath()
            path.addEllipse(in: rect)
            
            let innerRect = rect.insetBy(dx: size * 0.3, dy: size * 0.3)
            path.addEllipse(in: innerRect)
            
            return path
            
        case .custom:
            return CGPath(ellipseIn: rect, transform: nil)
        }
    }
    
    private func parseColor(_ hexString: String, alpha: Double) -> NSColor {
        var hex = hexString.trimmingCharacters(in: .whitespacesAndNewlines)
        if hex.hasPrefix("#") {
            hex.removeFirst()
        }
        
        var rgbValue: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&rgbValue)
        
        let red = Double((rgbValue & 0xFF0000) >> 16) / 255.0
        let green = Double((rgbValue & 0x00FF00) >> 8) / 255.0
        let blue = Double(rgbValue & 0x0000FF) / 255.0
        
        return NSColor(red: red, green: green, blue: blue, alpha: alpha)
    }
    
    override func layout() {
        super.layout()
        
        if let shapeLayer = shapeLayer, let config = currentConfig {
            let size = config.size
            let bounds = CGRect(x: 0, y: 0, width: size, height: size)
            
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            shapeLayer.bounds = bounds
            shapeLayer.position = CGPoint(x: self.bounds.midX, y: self.bounds.midY)
            CATransaction.commit()
        }
    }
}