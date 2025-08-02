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
        self.level = NSWindow.Level(Int(CGWindowLevelForKey(.statusWindow)) - 1)
        self.collectionBehavior = [
            .canJoinAllSpaces, 
            .fullScreenAuxiliary, 
            .stationary,
            .ignoresCycle
        ]
        
        self.ignoresMouseEvents = true
        self.isOpaque = false
        self.hasShadow = false
        self.backgroundColor = .clear
        self.isReleasedWhenClosed = false
        self.sharingType = .none
        self.displaysWhenScreenProfileChanges = true
        
        let view = IndicatorView()
        self.contentView = view
        self.indicatorView = view
        
        logger.info("Indicator window initialized")
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
        guard let screen = NSScreen.main else { return }
        
        let screenRect = screen.frame
        let screenVisibleRect = screen.visibleFrame
        
        var targetPoint = CGPoint(
            x: rect.midX + config.offset.x,
            y: rect.minY + config.offset.y
        )
        
        let padding = config.screenEdgePadding
        let windowSize = frame.size
        
        targetPoint.x = max(padding, min(targetPoint.x, screenRect.width - windowSize.width - padding))
        targetPoint.y = max(padding, min(targetPoint.y, screenVisibleRect.height - windowSize.height - padding))
        
        let windowOrigin = CGPoint(
            x: targetPoint.x,
            y: screenRect.height - targetPoint.y - windowSize.height
        )
        
        setFrameOrigin(windowOrigin)
        
        logger.debug("Indicator position updated to: \(windowOrigin.debugDescription)")
    }
    
    private func handleDisplayChange() {
        logger.info("Display configuration changed")
        
        guard currentConfig != nil else { return }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            self?.indicatorView?.layer?.contentsScale = self?.screen?.backingScaleFactor ?? 2.0
        }
    }
    
    private func handleSpaceChange() {
        logger.debug("Active space changed")
        
        if isVisible {
            orderFront(nil)
        }
    }
    
    private func handleFullScreenTransition() {
        logger.debug("Full screen transition detected")
        
        alphaValue = 0
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.alphaValue = 1
            self?.orderFront(nil)
        }
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        logger.info("Indicator window deinitialized")
    }
}