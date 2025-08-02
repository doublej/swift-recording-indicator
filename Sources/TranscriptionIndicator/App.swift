import AppKit
import Foundation
import Logging
import OSLog

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let logger = Logger(label: "app.delegate")
    private let signpostLogger = OSLog(subsystem: "com.transcription.indicator", category: "lifecycle")
    
    private var appCoordinator: AppCoordinator?
    private var serviceContainer = ServiceContainer.shared
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        let signpostID = OSSignpostID(log: signpostLogger)
        os_signpost(.begin, log: signpostLogger, name: "AppLaunch", signpostID: signpostID)
        
        logger.info("TranscriptionIndicator starting...")
        
        setupApplication()
        setupServices()
        startApplication()
        
        os_signpost(.end, log: signpostLogger, name: "AppLaunch", signpostID: signpostID)
        
        logger.info("TranscriptionIndicator ready")
    }
    
    func applicationWillTerminate(_ notification: Notification) {
        logger.info("TranscriptionIndicator terminating...")
        
        Task {
            await appCoordinator?.shutdown()
        }
    }
    
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        logger.info("Termination requested")
        return .terminateNow
    }
    
    private func setupApplication() {
        NSApplication.shared.setActivationPolicy(.prohibited)
        NSApplication.shared.disableRelaunchOnLogin()
        
        // Prevent automatic termination
        ProcessInfo.processInfo.disableAutomaticTermination("TranscriptionIndicator is running")
        
        setupMemoryPressureHandling()
        setupSystemNotifications()
    }
    
    private func setupServices() {
        serviceContainer.registerServices()
        
        let detector = serviceContainer.resolve(TextInputDetecting.self)
        let renderer = serviceContainer.resolve(IndicatorRendering.self)
        let communicationHandler = serviceContainer.resolve(CommunicationHandling.self)
        let processor = serviceContainer.resolve(CommandProcessing.self)
        
        Task {
            await processor.setDependencies(detector: detector, renderer: renderer)
        }
        
        appCoordinator = AppCoordinator(
            detector: detector,
            renderer: renderer,
            communicationHandler: communicationHandler
        )
    }
    
    private func startApplication() {
        Task {
            do {
                try await appCoordinator?.start()
            } catch {
                logger.error("Failed to start application: \(error.localizedDescription)")
                NSApplication.shared.terminate(nil)
            }
        }
    }
    
    private func setupMemoryPressureHandling() {
        let memoryPressureSource = DispatchSource.makeMemoryPressureSource(
            eventMask: [.warning, .critical],
            queue: .main
        )
        
        memoryPressureSource.setEventHandler { [weak self] in
            let event = memoryPressureSource.mask
            if event.contains(.critical) {
                self?.handleMemoryPressure()
            }
        }
        
        memoryPressureSource.resume()
    }
    
    private func setupSystemNotifications() {
        let notificationCenter = NSWorkspace.shared.notificationCenter
        
        notificationCenter.addObserver(
            forName: NSWorkspace.willSleepNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.logger.info("System going to sleep")
            Task {
                await self?.appCoordinator?.handleSystemSleep()
            }
        }
        
        notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.logger.info("System woke up")
            Task {
                await self?.appCoordinator?.handleSystemWake()
            }
        }
    }
    
    private func handleMemoryPressure() {
        logger.warning("Memory pressure detected")
        
        URLCache.shared.removeAllCachedResponses()
        
        Task {
            await appCoordinator?.handleMemoryPressure()
        }
    }
}

@MainActor
final class AppCoordinator: ObservableObject {
    private let logger = Logger(label: "app.coordinator")
    
    private let detector: TextInputDetecting
    private let renderer: IndicatorRendering
    private let communicationHandler: CommunicationHandling
    
    @Published private(set) var isActive = false
    @Published private(set) var currentConfig: IndicatorConfig?
    
    private var monitoringTask: Task<Void, Never>?
    
    init(detector: TextInputDetecting, renderer: IndicatorRendering, communicationHandler: CommunicationHandling) {
        self.detector = detector
        self.renderer = renderer
        self.communicationHandler = communicationHandler
    }
    
    func start() async throws {
        logger.info("Starting app coordinator")
        
        try await communicationHandler.startListening()
        
        monitoringTask = Task {
            await monitorCaretChanges()
        }
        
        isActive = true
        logger.info("App coordinator started")
    }
    
    func shutdown() async {
        logger.info("Shutting down app coordinator")
        
        isActive = false
        monitoringTask?.cancel()
        
        await communicationHandler.stopListening()
        await detector.stopDetection()
        await renderer.hide()
        
        logger.info("App coordinator shutdown complete")
    }
    
    func handleSystemSleep() async {
        logger.debug("Handling system sleep")
        await renderer.hide()
    }
    
    func handleSystemWake() async {
        logger.debug("Handling system wake")
        
        if let config = currentConfig {
            await renderer.show(config: config)
        }
    }
    
    func handleMemoryPressure() async {
        logger.warning("Handling memory pressure")
    }
    
    private func monitorCaretChanges() async {
        for await caretRect in await detector.caretRectPublisher {
            guard isActive, let config = currentConfig else { continue }
            
            if let rect = caretRect {
                await renderer.updatePosition(rect, config: config)
            }
        }
    }
}