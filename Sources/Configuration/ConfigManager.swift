import Foundation
import Logging

final class UserDefaultsConfigManager: ConfigurationManaging {
    private let logger = Logger(label: "config.manager")
    
    private enum Keys {
        static let appConfiguration = "com.transcription.indicator.config"
        static let configVersion = "com.transcription.indicator.config.version"
    }
    
    private let userDefaults: UserDefaults
    private let currentVersion = 1
    
    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }
    
    func load() throws -> AppConfiguration {
        let version = userDefaults.integer(forKey: Keys.configVersion)
        
        if version == 0 {
            logger.info("No existing configuration found, using defaults")
            let defaultConfig = AppConfiguration.default
            try save(defaultConfig)
            return defaultConfig
        }
        
        if version != currentVersion {
            logger.warning("Configuration version mismatch. Current: \(currentVersion), Found: \(version)")
            return try migrateConfiguration(fromVersion: version)
        }
        
        guard let data = userDefaults.data(forKey: Keys.appConfiguration) else {
            logger.warning("Configuration data not found, using defaults")
            let defaultConfig = AppConfiguration.default
            try save(defaultConfig)
            return defaultConfig
        }
        
        do {
            let decoder = JSONDecoder()
            let config = try decoder.decode(AppConfiguration.self, from: data)
            
            try validate(config)
            
            logger.info("Configuration loaded successfully")
            return config
        } catch {
            logger.error("Failed to decode configuration: \(error.localizedDescription)")
            
            let defaultConfig = AppConfiguration.default
            try save(defaultConfig)
            return defaultConfig
        }
    }
    
    func save(_ config: AppConfiguration) throws {
        do {
            try validate(config)
            
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            
            let data = try encoder.encode(config)
            
            userDefaults.set(data, forKey: Keys.appConfiguration)
            userDefaults.set(currentVersion, forKey: Keys.configVersion)
            
            logger.info("Configuration saved successfully")
        } catch {
            logger.error("Failed to save configuration: \(error.localizedDescription)")
            throw error
        }
    }
    
    func validate(_ config: AppConfiguration) throws {
        try SecurityValidator.validateConfig(config.indicator)
        try validateLoggingConfig(config.logging)
        try validatePerformanceConfig(config.performance)
    }
    
    private func validateLoggingConfig(_ config: LoggingConfig) throws {
        let validLevels = ["trace", "debug", "info", "notice", "warning", "error", "critical"]
        guard validLevels.contains(config.level.lowercased()) else {
            throw TranscriptionIndicatorError.invalidConfig(
                field: "logging.level",
                reason: "must be one of: \(validLevels.joined(separator: ", "))"
            )
        }
    }
    
    private func validatePerformanceConfig(_ config: PerformanceConfig) throws {
        guard config.memoryCheckInterval > 0 && config.memoryCheckInterval <= 300 else {
            throw TranscriptionIndicatorError.invalidConfig(
                field: "performance.memoryCheckInterval",
                reason: "must be between 1 and 300 seconds"
            )
        }
        
        guard config.maxMemoryUsage > 0 && config.maxMemoryUsage <= 1024 * 1024 * 1024 else { // 1GB
            throw TranscriptionIndicatorError.invalidConfig(
                field: "performance.maxMemoryUsage",
                reason: "must be between 1 byte and 1GB"
            )
        }
    }
    
    private func migrateConfiguration(fromVersion: Int) throws -> AppConfiguration {
        logger.info("Migrating configuration from version \(fromVersion) to \(currentVersion)")
        
        switch fromVersion {
        case 0:
            let defaultConfig = AppConfiguration.default
            try save(defaultConfig)
            return defaultConfig
        default:
            logger.warning("Unknown configuration version \(fromVersion), using defaults")
            let defaultConfig = AppConfiguration.default
            try save(defaultConfig)
            return defaultConfig
        }
    }
    
    func exportConfiguration() throws -> String {
        let config = try load()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        
        let data = try encoder.encode(config)
        guard let jsonString = String(data: data, encoding: .utf8) else {
            throw TranscriptionIndicatorError.internalError("Failed to convert configuration to string")
        }
        
        logger.info("Configuration exported")
        return jsonString
    }
    
    func importConfiguration(from jsonString: String) throws {
        guard let data = jsonString.data(using: .utf8) else {
            throw TranscriptionIndicatorError.invalidConfig(
                field: "import",
                reason: "Invalid UTF-8 string"
            )
        }
        
        let decoder = JSONDecoder()
        let config = try decoder.decode(AppConfiguration.self, from: data)
        
        try validate(config)
        try save(config)
        
        logger.info("Configuration imported successfully")
    }
    
    func resetToDefaults() throws {
        let defaultConfig = AppConfiguration.default
        try save(defaultConfig)
        logger.info("Configuration reset to defaults")
    }
    
    func backupConfiguration() throws -> URL {
        let config = try load()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        
        let data = try encoder.encode(config)
        
        let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let backupURL = documentsURL.appendingPathComponent("TranscriptionIndicator_config_backup_\(Date().timeIntervalSince1970).json")
        
        try data.write(to: backupURL)
        
        logger.info("Configuration backed up to: \(backupURL.path)")
        return backupURL
    }
    
    func restoreConfiguration(from url: URL) throws {
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        let config = try decoder.decode(AppConfiguration.self, from: data)
        
        try validate(config)
        try save(config)
        
        logger.info("Configuration restored from: \(url.path)")
    }
}