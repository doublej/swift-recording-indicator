import QuartzCore
import AppKit
import OSLog

/// Efficient layer cache for reusing Core Animation layers
@MainActor
final class LayerCache {
    static let shared = LayerCache()
    
    private let logger = Logger(label: "layer.cache")
    
    private var shapeLayerPool: [IndicatorConfig.Shape: [CAShapeLayer]] = [:]
    private var textLayerPool: [CATextLayer] = []
    private var replicatorLayerPool: [CAReplicatorLayer] = []
    
    private let maxPoolSize = 5
    
    private init() {
        // Register cleanup handler
        MemoryManager.shared.registerCleanupHandler { [weak self] in
            Task { @MainActor in
                self?.clearCache()
            }
        }
    }
    
    /// Get or create a shape layer for the specified shape
    func shapeLayer(for shape: IndicatorConfig.Shape) -> CAShapeLayer {
        if let layers = shapeLayerPool[shape], !layers.isEmpty {
            var poolLayers = layers
            let layer = poolLayers.removeLast()
            shapeLayerPool[shape] = poolLayers
            
            // Reset layer properties
            resetShapeLayer(layer)
            
            logger.debug("Reused shape layer from pool for: \(shape.rawValue)")
            return layer
        }
        
        // Create new layer
        let layer = createShapeLayer(for: shape)
        logger.debug("Created new shape layer for: \(shape.rawValue)")
        return layer
    }
    
    /// Return a shape layer to the pool
    func returnShapeLayer(_ layer: CAShapeLayer, shape: IndicatorConfig.Shape) {
        var layers = shapeLayerPool[shape] ?? []
        
        // Only keep up to maxPoolSize layers
        guard layers.count < maxPoolSize else { return }
        
        // Clean up the layer before pooling
        layer.removeFromSuperlayer()
        layer.removeAllAnimations()
        
        layers.append(layer)
        shapeLayerPool[shape] = layers
        
        logger.debug("Returned shape layer to pool for: \(shape.rawValue)")
    }
    
    /// Get or create a text layer
    func textLayer() -> CATextLayer {
        if !textLayerPool.isEmpty {
            let layer = textLayerPool.removeLast()
            resetTextLayer(layer)
            return layer
        }
        
        return createTextLayer()
    }
    
    /// Return a text layer to the pool
    func returnTextLayer(_ layer: CATextLayer) {
        guard textLayerPool.count < maxPoolSize else { return }
        
        layer.removeFromSuperlayer()
        layer.removeAllAnimations()
        textLayerPool.append(layer)
    }
    
    /// Get or create a replicator layer
    func replicatorLayer() -> CAReplicatorLayer {
        if !replicatorLayerPool.isEmpty {
            let layer = replicatorLayerPool.removeLast()
            resetReplicatorLayer(layer)
            return layer
        }
        
        return createReplicatorLayer()
    }
    
    /// Return a replicator layer to the pool
    func returnReplicatorLayer(_ layer: CAReplicatorLayer) {
        guard replicatorLayerPool.count < maxPoolSize else { return }
        
        layer.removeFromSuperlayer()
        layer.removeAllAnimations()
        replicatorLayerPool.append(layer)
    }
    
    /// Clear all cached layers
    func clearCache() {
        logger.info("Clearing layer cache")
        
        for (_, layers) in shapeLayerPool {
            for layer in layers {
                layer.removeFromSuperlayer()
            }
        }
        shapeLayerPool.removeAll()
        
        for layer in textLayerPool {
            layer.removeFromSuperlayer()
        }
        textLayerPool.removeAll()
        
        for layer in replicatorLayerPool {
            layer.removeFromSuperlayer()
        }
        replicatorLayerPool.removeAll()
    }
    
    // MARK: - Private Methods
    
    private func createShapeLayer(for shape: IndicatorConfig.Shape) -> CAShapeLayer {
        let layer = CAShapeLayer()
        
        // Configure for optimal performance
        layer.shouldRasterize = true
        layer.rasterizationScale = NSScreen.main?.backingScaleFactor ?? 2.0
        layer.drawsAsynchronously = true
        layer.contentsScale = NSScreen.main?.backingScaleFactor ?? 2.0
        
        // Disable implicit animations
        layer.actions = [
            "position": NSNull(),
            "bounds": NSNull(),
            "path": NSNull(),
            "fillColor": NSNull(),
            "strokeColor": NSNull(),
            "lineWidth": NSNull(),
            "opacity": NSNull()
        ]
        
        return layer
    }
    
    private func resetShapeLayer(_ layer: CAShapeLayer) {
        layer.path = nil
        layer.fillColor = nil
        layer.strokeColor = nil
        layer.lineWidth = 0
        layer.opacity = 1.0
        layer.transform = CATransform3DIdentity
        layer.isHidden = false
    }
    
    private func createTextLayer() -> CATextLayer {
        let layer = CATextLayer()
        layer.contentsScale = NSScreen.main?.backingScaleFactor ?? 2.0
        layer.allowsFontSubpixelQuantization = true
        return layer
    }
    
    private func resetTextLayer(_ layer: CATextLayer) {
        layer.string = nil
        layer.fontSize = 17
        layer.foregroundColor = nil
        layer.opacity = 1.0
        layer.transform = CATransform3DIdentity
    }
    
    private func createReplicatorLayer() -> CAReplicatorLayer {
        let layer = CAReplicatorLayer()
        layer.shouldRasterize = true
        layer.rasterizationScale = NSScreen.main?.backingScaleFactor ?? 2.0
        return layer
    }
    
    private func resetReplicatorLayer(_ layer: CAReplicatorLayer) {
        layer.instanceCount = 1
        layer.instanceDelay = 0
        layer.instanceTransform = CATransform3DIdentity
        layer.sublayers?.forEach { $0.removeFromSuperlayer() }
    }
}