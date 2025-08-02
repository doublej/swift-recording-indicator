import AppKit
import CoreGraphics
import Logging

@MainActor
final class CoreAnimationIndicatorRenderer: IndicatorRendering {
    private let logger = Logger(label: "indicator.renderer")
    
    private var window: IndicatorWindow?
    private var isVisible = false
    
    func show(config: IndicatorConfig) async {
        if window == nil {
            window = IndicatorWindow(
                contentRect: .zero,
                styleMask: [],
                backing: .buffered,
                defer: false
            )
        }
        
        window?.show(with: config)
        isVisible = true
        
        logger.info("Indicator shown")
    }
    
    func hide() async {
        window?.hide()
        isVisible = false
        
        logger.info("Indicator hidden")
    }
    
    func updateConfig(_ config: IndicatorConfig) async {
        window?.updateConfig(config)
        
        logger.debug("Indicator config updated")
    }
    
    func updatePosition(_ rect: CGRect, config: IndicatorConfig) async {
        guard isVisible else { return }
        
        window?.updatePosition(rect, config: config)
        
        logger.debug("Indicator position updated")
    }
}