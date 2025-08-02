import QuartzCore
import Foundation
import Logging
import OSLog

@MainActor
final class AnimationController {
    private let logger = Logger(label: "animation.controller")
    private let signpostLogger = OSLog(subsystem: "com.transcription.indicator", category: "animation")
    
    private var currentState: AnimationState = .off
    private var targetLayer: CALayer?
    private var config: AnimationConfig = .default
    private var completionHandler: (() -> Void)?
    
    // Animation layer pool for reuse
    private var animationPool: [String: CAAnimation] = [:]
    private let animationKeys = ["appear", "breathing", "disappear"]
    
    func updateConfig(_ newConfig: AnimationConfig) {
        config = newConfig
        
        if currentState == .idle {
            startBreathingAnimation()
        }
    }
    
    func setTargetLayer(_ layer: CALayer) {
        targetLayer = layer
    }
    
    func transitionTo(_ state: AnimationState, completion: (() -> Void)? = nil) {
        guard currentState != state else {
            completion?()
            return
        }
        
        let signpostID = OSSignpostID(log: signpostLogger)
        os_signpost(.begin, log: signpostLogger, name: "AnimationTransition", signpostID: signpostID,
                   "From: %{public}s To: %{public}s", stateString(currentState), stateString(state))
        
        logger.debug("Animation transition: \(stateString(currentState)) -> \(stateString(state))")
        
        completionHandler = completion
        
        switch (currentState, state) {
        case (.off, .appearing):
            startAppearAnimation()
        case (.appearing, .idle):
            startBreathingAnimation()
        case (.idle, .disappearing), (.appearing, .disappearing):
            startDisappearAnimation()
        case (.disappearing, .off):
            stopAllAnimations()
        default:
            logger.warning("Invalid animation transition: \(stateString(currentState)) -> \(stateString(state))")
            completion?()
            return
        }
        
        currentState = state
        
        os_signpost(.end, log: signpostLogger, name: "AnimationTransition", signpostID: signpostID)
    }
    
    private func startAppearAnimation() {
        guard let layer = targetLayer else {
            logger.error("No target layer for appear animation")
            completionHandler?()
            return
        }
        
        PerformanceMonitor.shared.startAnimationMeasurement()
        defer { PerformanceMonitor.shared.endAnimationMeasurement() }
        
        layer.removeAllAnimations()
        
        // Try to reuse cached animation or create new one
        let group: CAAnimationGroup
        if let cached = animationPool["appear"] as? CAAnimationGroup {
            group = cached.copy() as! CAAnimationGroup
            // Update duration if config changed
            if let opacity = group.animations?.first(where: { ($0 as? CABasicAnimation)?.keyPath == "opacity" }) as? CABasicAnimation {
                opacity.duration = config.inDuration
            }
        } else {
            let scaleAnimation = CASpringAnimation(keyPath: "transform.scale")
            scaleAnimation.fromValue = 0.8
            scaleAnimation.toValue = 1.0
            scaleAnimation.damping = 10
            scaleAnimation.initialVelocity = 5
            scaleAnimation.mass = 1
            scaleAnimation.stiffness = 150
            scaleAnimation.duration = scaleAnimation.settlingDuration
            
            let opacityAnimation = CABasicAnimation(keyPath: "opacity")
            opacityAnimation.fromValue = 0.0
            opacityAnimation.toValue = 1.0
            opacityAnimation.duration = config.inDuration
            opacityAnimation.timingFunction = CAMediaTimingFunction(name: .easeOut)
            
            group = CAAnimationGroup()
            group.animations = [scaleAnimation, opacityAnimation]
            group.duration = max(scaleAnimation.duration, opacityAnimation.duration)
            group.fillMode = .forwards
            group.isRemovedOnCompletion = false
            
            // Cache for reuse
            animationPool["appear"] = group.copy() as? CAAnimation
        }
        
        group.completion = { [weak self] _ in
            self?.completionHandler?()
            self?.completionHandler = nil
            PerformanceMonitor.shared.recordFrameTime()
        }
        
        layer.add(group, forKey: "appear")
        
        logger.debug("Started appear animation")
    }
    
    private func startBreathingAnimation() {
        guard let layer = targetLayer else {
            logger.error("No target layer for breathing animation")
            return
        }
        
        // Only remove non-breathing animations
        layer.removeAnimation(forKey: "appear")
        layer.removeAnimation(forKey: "disappear")
        
        // Check if breathing animation already exists and matches config
        if let existing = layer.animation(forKey: "breathing") as? CAKeyframeAnimation,
           existing.duration == config.breathingCycle {
            // Animation already running with correct duration
            completionHandler?()
            completionHandler = nil
            return
        }
        
        let breathing: CAKeyframeAnimation
        if let cached = animationPool["breathing"] as? CAKeyframeAnimation {
            breathing = cached.copy() as! CAKeyframeAnimation
            breathing.duration = config.breathingCycle
        } else {
            breathing = CAKeyframeAnimation(keyPath: "transform.scale")
            breathing.values = [1.0, 1.2, 1.0]
            breathing.keyTimes = [0, 0.5, 1.0]
            breathing.duration = config.breathingCycle
            breathing.repeatCount = .infinity
            breathing.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            breathing.fillMode = .forwards
            breathing.isRemovedOnCompletion = false
            
            // Cache for reuse
            animationPool["breathing"] = breathing.copy() as? CAAnimation
        }
        
        layer.add(breathing, forKey: "breathing")
        
        completionHandler?()
        completionHandler = nil
        
        logger.debug("Started breathing animation")
    }
    
    private func startDisappearAnimation() {
        guard let layer = targetLayer else {
            logger.error("No target layer for disappear animation")
            completionHandler?()
            return
        }
        
        layer.removeAllAnimations()
        
        let scaleAnimation = CABasicAnimation(keyPath: "transform.scale")
        scaleAnimation.fromValue = layer.presentation()?.value(forKeyPath: "transform.scale") ?? 1.0
        scaleAnimation.toValue = 0.8
        scaleAnimation.duration = config.outDuration
        scaleAnimation.timingFunction = CAMediaTimingFunction(name: .easeIn)
        
        let opacityAnimation = CABasicAnimation(keyPath: "opacity")
        opacityAnimation.fromValue = layer.presentation()?.opacity ?? layer.opacity
        opacityAnimation.toValue = 0.0
        opacityAnimation.duration = config.outDuration
        opacityAnimation.timingFunction = CAMediaTimingFunction(name: .easeIn)
        
        let group = CAAnimationGroup()
        group.animations = [scaleAnimation, opacityAnimation]
        group.duration = config.outDuration
        group.fillMode = .forwards
        group.isRemovedOnCompletion = false
        
        group.completion = { [weak self] _ in
            self?.completionHandler?()
            self?.completionHandler = nil
        }
        
        layer.add(group, forKey: "disappear")
        
        logger.debug("Started disappear animation")
    }
    
    private func stopAllAnimations() {
        targetLayer?.removeAllAnimations()
        
        completionHandler?()
        completionHandler = nil
        
        logger.debug("Stopped all animations")
    }
    
    deinit {
        // Clear animation pool on main actor since animationPool is main actor isolated
        Task { @MainActor in
            animationPool.removeAll()
        }
    }
    
    private func stateString(_ state: AnimationState) -> String {
        switch state {
        case .off: return "off"
        case .appearing: return "appearing"
        case .idle: return "idle"
        case .disappearing: return "disappearing"
        }
    }
}

extension CAAnimationGroup {
    var completion: ((Bool) -> Void)? {
        get {
            return (delegate as? AnimationDelegate)?.completion
        }
        set {
            delegate = newValue.map(AnimationDelegate.init)
        }
    }
}

private final class AnimationDelegate: NSObject, CAAnimationDelegate {
    let completion: (Bool) -> Void
    
    init(completion: @escaping (Bool) -> Void) {
        self.completion = completion
    }
    
    func animationDidStop(_ anim: CAAnimation, finished flag: Bool) {
        completion(flag)
    }
}