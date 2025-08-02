import Foundation
import Logging
import OSLog

actor CommandProcessor: CommandProcessing {
    private let logger = Logger(label: "command.processor")
    private let signpostLogger = OSLog(subsystem: "com.transcription.indicator", category: "commands")
    
    private let configManager: ConfigurationManaging
    private var detector: TextInputDetecting?
    private var renderer: IndicatorRendering?
    private let healthMonitor: HealthMonitoring
    
    private var currentConfig: IndicatorConfig = .default
    private var isIndicatorVisible = false
    
    init(configManager: ConfigurationManaging) {
        self.configManager = configManager
        self.healthMonitor = HealthMonitor()
        
        Task {
            await loadInitialConfig()
        }
    }
    
    func setDependencies(detector: TextInputDetecting, renderer: IndicatorRendering) async {
        self.detector = detector
        self.renderer = renderer
    }
    
    func process(_ command: Command) async throws -> CommandResponse {
        let signpostID = OSSignpostID(log: signpostLogger)
        os_signpost(.begin, log: signpostLogger, name: "ProcessCommand", signpostID: signpostID, 
                   "Command: %{public}s", command.command)
        
        defer {
            os_signpost(.end, log: signpostLogger, name: "ProcessCommand", signpostID: signpostID)
        }
        
        logger.info("Processing command: \(command.command) with ID: \(command.id)")
        
        let response: CommandResponse
        
        switch command.command {
        case Command.CommandType.show.rawValue:
            response = try await handleShow(command)
        case Command.CommandType.hide.rawValue:
            response = await handleHide(command)
        case Command.CommandType.health.rawValue:
            response = await handleHealth(command)
        case Command.CommandType.config.rawValue:
            response = try await handleConfig(command)
        default:
            throw TranscriptionIndicatorError.invalidCommand("Unknown command: \(command.command)")
        }
        
        logger.debug("Command processed successfully: \(command.id)")
        return response
    }
    
    private func handleShow(_ command: Command) async throws -> CommandResponse {
        guard let detector = detector, let renderer = renderer else {
            throw TranscriptionIndicatorError.internalError("Dependencies not initialized")
        }
        
        if let config = command.config {
            try SecurityValidator.validateConfig(config)
            currentConfig = config
            try saveConfig()
        }
        
        if !isIndicatorVisible {
            try await detector.startDetection()
            await renderer.show(config: currentConfig)
            isIndicatorVisible = true
            
            await healthMonitor.startMonitoring(interval: currentConfig.health.interval)
            
            Task {
                await monitorCaretChanges()
            }
        } else {
            await renderer.updateConfig(currentConfig)
        }
        
        return CommandResponse.success(id: command.id, message: "Indicator shown")
    }
    
    private func handleHide(_ command: Command) async -> CommandResponse {
        if isIndicatorVisible, let detector = detector, let renderer = renderer {
            await detector.stopDetection()
            await renderer.hide()
            await healthMonitor.stopMonitoring()
            isIndicatorVisible = false
        }
        
        return CommandResponse.success(id: command.id, message: "Indicator hidden")
    }
    
    private func handleHealth(_ command: Command) async -> CommandResponse {
        let pid = ProcessInfo.processInfo.processIdentifier
        return CommandResponse.health(id: command.id, pid: Int(pid))
    }
    
    private func handleConfig(_ command: Command) async throws -> CommandResponse {
        guard let newConfig = command.config else {
            throw TranscriptionIndicatorError.invalidConfig(field: "config", reason: "Missing configuration")
        }
        
        try SecurityValidator.validateConfig(newConfig)
        
        let oldConfig = currentConfig
        currentConfig = mergeConfigs(base: currentConfig, update: newConfig)
        
        try saveConfig()
        
        if isIndicatorVisible, let renderer = renderer {
            await renderer.updateConfig(currentConfig)
            
            if oldConfig.health.interval != currentConfig.health.interval {
                await healthMonitor.stopMonitoring()
                await healthMonitor.startMonitoring(interval: currentConfig.health.interval)
            }
        }
        
        return CommandResponse.success(id: command.id, message: "Configuration updated")
    }
    
    private func monitorCaretChanges() async {
        guard let detector = detector, let renderer = renderer else { return }
        
        for await caretRect in await detector.caretRectPublisher {
            guard isIndicatorVisible else { break }
            
            if let rect = caretRect {
                await renderer.updatePosition(rect, config: currentConfig)
            }
        }
    }
    
    private func loadInitialConfig() async {
        do {
            let appConfig = try configManager.load()
            currentConfig = appConfig.indicator
            logger.info("Loaded initial configuration")
        } catch {
            logger.warning("Failed to load config, using defaults: \(error.localizedDescription)")
            currentConfig = .default
        }
    }
    
    private func saveConfig() throws {
        let appConfig = AppConfiguration(
            indicator: currentConfig,
            logging: .default,
            performance: .default
        )
        try configManager.save(appConfig)
    }
    
    private func mergeConfigs(base: IndicatorConfig, update: IndicatorConfig) -> IndicatorConfig {
        return IndicatorConfig(
            v: update.v,
            mode: update.mode,
            visibility: update.visibility,
            shape: update.shape,
            colors: update.colors,
            size: update.size,
            opacity: update.opacity,
            offset: update.offset,
            screenEdgePadding: update.screenEdgePadding,
            secureFieldPolicy: update.secureFieldPolicy,
            animations: update.animations,
            health: update.health,
            exitOnIdle: update.exitOnIdle
        )
    }
}