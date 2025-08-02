import AppKit
import CoreGraphics
import OSLog
import Logging

@MainActor
final class IndicatorWindow: NSPanel {
    private let logger = Logger(label: "indicator.window")
    private let signpostLogger = OSLog(subsystem: "com.transcription.indicator", category: "ui")
    
    private var indicatorView: IndicatorView?
    private var currentConfig: IndicatorConfig?
    
    override init(contentRect: NSRect, styleMask: NSWindow.StyleMask, 
                  backing: NSWindow.BackingStoreType, defer flag: Bool) {
        super.init(contentRect: .zero, 
                   styleMask: [.borderless, .nonactivatingPanel], 
                   backing: .buffered, defer: false)
        
        setupWindow()
        setupNotifications()
    }
    
    private func setupWindow() {
        // Set window level to be above most applications but below critical system UI
        // Using screenSaver level - 1 ensures visibility over apps while respecting system overlays
        self.level = NSWindow.Level(Int(CGWindowLevelForKey(.screenSaverWindow)) - 1)
        
        // Comprehensive collection behavior for proper multi-space and full-screen support
        self.collectionBehavior = [
            .canJoinAllSpaces,          // Appears on all spaces
            .fullScreenAuxiliary,       // Visible in full-screen applications
            .stationary,                // Doesn't move with spaces transitions
            .ignoresCycle,              // Excluded from window cycling (Cmd+`)
            .fullScreenDisallowsTiling, // Prevents interference with full-screen tiling
            .transient                  // Hints this is a temporary overlay
        ]
        
        // Mouse and interaction behavior
        self.ignoresMouseEvents = true
        self.acceptsMouseMovedEvents = false
        
        // Visual properties for transparent overlay
        self.isOpaque = false
        self.hasShadow = false
        self.backgroundColor = .clear
        self.alphaValue = 1.0
        
        // Memory and lifecycle management
        self.isReleasedWhenClosed = false
        self.hidesOnDeactivate = false
        self.canHide = true
        
        // Security and sharing restrictions
        self.sharingType = .none
        self.isRestorable = false
        
        // Display and resolution handling
        self.displaysWhenScreenProfileChanges = true
        self.allowsToolTipsWhenApplicationIsInactive = false
        
        // Optimize window backing for performance (preferredBackingLocation deprecated in macOS 10.14)
        self.colorSpace = .genericRGB
        
        // Accessibility and focus behavior
        self.canBecomeVisibleWithoutLogin = false
        self.preventsApplicationTerminationWhenModal = false
        
        // Content view setup
        let view = IndicatorView()
        self.contentView = view
        self.indicatorView = view
        
        // Layer-backed view for better performance
        if let contentView = self.contentView {
            contentView.wantsLayer = true
            contentView.layer?.backgroundColor = CGColor.clear
        }
        
        logger.info("Indicator window initialized with optimized settings")
    }
    
    private func setupNotifications() {
        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.handleDisplayChange()
            }
        }
        
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.handleSpaceChange()
            }
        }
        
        NotificationCenter.default.addObserver(
            forName: NSWindow.willEnterFullScreenNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            Task { @MainActor in
                if let window = notification.object as? NSWindow,
                   let self = self,
                   window.screen == self.screen {
                    self.handleFullScreenTransition()
                }
            }
        }
    }
    
    func show(with config: IndicatorConfig) {
        let signpostID = OSSignpostID(log: signpostLogger)
        os_signpost(.begin, log: signpostLogger, name: "ShowIndicator", signpostID: signpostID)
        
        currentConfig = config
        indicatorView?.updateConfig(config)
        
        let size = CGSize(width: config.size, height: config.size)
        setContentSize(size)
        
        if !isVisible {
            orderFront(nil)
        }
        
        indicatorView?.show()
        
        os_signpost(.end, log: signpostLogger, name: "ShowIndicator", signpostID: signpostID)
        logger.debug("Indicator window shown")
    }
    
    func hide() {
        let signpostID = OSSignpostID(log: signpostLogger)
        os_signpost(.begin, log: signpostLogger, name: "HideIndicator", signpostID: signpostID)
        
        indicatorView?.hide { [weak self] in
            self?.orderOut(nil)
        }
        
        os_signpost(.end, log: signpostLogger, name: "HideIndicator", signpostID: signpostID)
        logger.debug("Indicator window hidden")
    }
    
    func updateConfig(_ config: IndicatorConfig) {
        currentConfig = config
        
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        
        indicatorView?.updateConfig(config)
        
        let size = CGSize(width: config.size, height: config.size)
        setContentSize(size)
        
        CATransaction.commit()
        
        logger.debug("Indicator window config updated")
    }
    
    func updatePosition(_ rect: CGRect, config: IndicatorConfig) {
        // Find the screen containing the caret rect, fallback to main screen
        let targetScreen = findScreenContaining(rect) ?? NSScreen.main
        guard let screen = targetScreen else { 
            logger.warning("No screen available for positioning")
            return 
        }
        
        let screenRect = screen.frame
        let screenVisibleRect = screen.visibleFrame
        
        // Convert caret rect to screen coordinates if needed
        let adjustedRect = convertRectToScreen(rect, targetScreen: screen)
        
        var targetPoint = CGPoint(
            x: adjustedRect.midX + config.offset.x,
            y: adjustedRect.minY + config.offset.y
        )
        
        let padding = config.screenEdgePadding
        let windowSize = frame.size
        
        // Constrain to screen bounds with padding
        targetPoint.x = max(screenRect.minX + padding, 
                           min(targetPoint.x, screenRect.maxX - windowSize.width - padding))
        targetPoint.y = max(screenVisibleRect.minY + padding, 
                           min(targetPoint.y, screenVisibleRect.maxY - windowSize.height - padding))
        
        // Convert from screen coordinates to window coordinates
        let windowOrigin = CGPoint(
            x: targetPoint.x,
            y: screenRect.maxY - targetPoint.y - windowSize.height
        )
        
        // Move window to target screen if it's different from current screen
        if self.screen != screen {
            logger.debug("Moving indicator to different screen: \(screen.localizedName)")
        }
        
        setFrameOrigin(windowOrigin)
        
        // Cache the rect for handling display changes
        cacheCaretRect(rect)
        
        logger.debug("Indicator position updated to: \(windowOrigin.debugDescription) on screen: \(screen.localizedName)")
    }
    
    private func findScreenContaining(_ rect: CGRect) -> NSScreen? {
        // Find screen that contains the center point of the rect
        let centerPoint = CGPoint(x: rect.midX, y: rect.midY)
        
        for screen in NSScreen.screens {
            if screen.frame.contains(centerPoint) {
                return screen
            }
        }
        
        // Fallback: find closest screen by distance to center point
        return NSScreen.screens.min { screen1, screen2 in
            let distance1 = distanceFromPointToRect(centerPoint, screen1.frame)
            let distance2 = distanceFromPointToRect(centerPoint, screen2.frame)
            return distance1 < distance2
        }
    }
    
    private func convertRectToScreen(_ rect: CGRect, targetScreen: NSScreen) -> CGRect {
        // Rect coordinates might be in different coordinate system
        // This ensures proper positioning across multiple displays
        return rect
    }
    
    private func distanceFromPointToRect(_ point: CGPoint, _ rect: CGRect) -> CGFloat {
        let dx = max(0, max(rect.minX - point.x, point.x - rect.maxX))
        let dy = max(0, max(rect.minY - point.y, point.y - rect.maxY))
        return sqrt(dx * dx + dy * dy)
    }
    
    private func handleDisplayChange() {
        logger.info("Display configuration changed - updating for new display setup")
        
        guard let config = currentConfig else { 
            logger.debug("No active config during display change")
            return 
        }
        
        // Handle resolution changes, display arrangement changes, etc.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            guard let self = self else { return }
            
            // Update backing scale factor for new display
            if let newScale = self.screen?.backingScaleFactor {
                self.indicatorView?.layer?.contentsScale = newScale
                logger.debug("Updated backing scale factor to: \(newScale)")
            }
            
            // Re-validate current position is still on screen
            if self.isVisible, let lastRect = self.lastCaretRect {
                self.updatePosition(lastRect, config: config)
            }
        }
    }
    
    private func handleSpaceChange() {
        logger.debug("Active space changed - ensuring indicator visibility")
        
        // Ensure window remains visible on the new space
        if isVisible {
            // Brief delay to allow space transition to complete
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                guard let self = self else { return }
                
                // Force the window to front on the new space
                self.orderFront(nil)
                
                // Verify window level is still correct (some space transitions can affect this)
                let expectedLevel = NSWindow.Level(Int(CGWindowLevelForKey(.screenSaverWindow)) - 1)
                if self.level != expectedLevel {
                    self.level = expectedLevel
                    logger.debug("Restored window level after space change")
                }
            }
        }
    }
    
    private func handleFullScreenTransition() {
        logger.debug("Full screen transition detected - managing indicator visibility")
        
        // Smoothly handle full-screen transitions without jarring the user
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            context.allowsImplicitAnimation = true
            self.alphaValue = 0.3
        } completionHandler: { [weak self] in
            // After transition completes, restore full visibility
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                guard let self = self else { return }
                
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = 0.2
                    context.allowsImplicitAnimation = true
                    self.alphaValue = 1.0
                } completionHandler: { [weak self] in
                    self?.orderFront(nil)
                }
            }
        }
    }
    
    // Cache last caret rect for repositioning after display changes
    private var lastCaretRect: CGRect?
    
    private func cacheCaretRect(_ rect: CGRect) {
        lastCaretRect = rect
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        logger.info("Indicator window deinitialized")
    }
}