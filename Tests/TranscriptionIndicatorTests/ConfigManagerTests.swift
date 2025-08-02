import XCTest
@testable import TranscriptionIndicator

final class ConfigManagerTests: XCTestCase {
    
    private var userDefaults: UserDefaults!
    private var configManager: UserDefaultsConfigManager!
    
    override func setUp() {
        super.setUp()
        
        // Use a test-specific UserDefaults suite
        userDefaults = UserDefaults(suiteName: "test.transcription.indicator")!
        configManager = UserDefaultsConfigManager(userDefaults: userDefaults)
        
        // Clear any existing test data
        userDefaults.removePersistentDomain(forName: "test.transcription.indicator")
    }
    
    override func tearDown() {
        // Clean up test data
        userDefaults.removePersistentDomain(forName: "test.transcription.indicator")
        
        userDefaults = nil
        configManager = nil
        super.tearDown()
    }
    
    func testDefaultConfigurationLoad() throws {
        // First load should return defaults and save them
        let config = try configManager.load()
        
        XCTAssertEqual(config.indicator.v, 1)
        XCTAssertEqual(config.indicator.shape, .circle)
        XCTAssertEqual(config.indicator.size, 20)
        XCTAssertEqual(config.indicator.opacity, 0.9)
    }
    
    func testConfigurationSaveAndLoad() throws {
        // Create modified configuration using initializer
        let modifiedIndicator = IndicatorConfig(
            v: 1,
            mode: .cursor,
            visibility: .forceOn,
            shape: .ring,
            colors: IndicatorConfig.Colors(primary: "#00FF00"),
            size: 30,
            opacity: 0.8,
            offset: IndicatorConfig.Offset(x: 5, y: -5),
            screenEdgePadding: 12,
            secureFieldPolicy: .dim,
            animations: .default,
            health: .default,
            exitOnIdle: true
        )
        
        let config = AppConfiguration(
            indicator: modifiedIndicator,
            logging: .default,
            performance: .default
        )
        
        // Save the configuration
        try configManager.save(config)
        
        // Load it back
        let loadedConfig = try configManager.load()
        
        XCTAssertEqual(loadedConfig.indicator.mode, .cursor)
        XCTAssertEqual(loadedConfig.indicator.visibility, .forceOn)
        XCTAssertEqual(loadedConfig.indicator.shape, .ring)
        XCTAssertEqual(loadedConfig.indicator.colors.primary, "#00FF00")
        XCTAssertEqual(loadedConfig.indicator.size, 30)
        XCTAssertEqual(loadedConfig.indicator.opacity, 0.8)
        XCTAssertEqual(loadedConfig.indicator.offset.x, 5)
        XCTAssertEqual(loadedConfig.indicator.offset.y, -5)
        XCTAssertEqual(loadedConfig.indicator.screenEdgePadding, 12)
        XCTAssertEqual(loadedConfig.indicator.secureFieldPolicy, .dim)
        XCTAssertEqual(loadedConfig.indicator.exitOnIdle, true)
    }
    
    func testConfigurationValidation() {
        // Create invalid configuration
        let invalidIndicator = IndicatorConfig(
            v: 1,
            mode: .caret,
            visibility: .auto,
            shape: .circle,
            colors: IndicatorConfig.Colors(primary: "invalid_color"),
            size: 20,
            opacity: 0.9,
            offset: IndicatorConfig.Offset(),
            screenEdgePadding: 8,
            secureFieldPolicy: .hide,
            animations: .default,
            health: .default,
            exitOnIdle: false
        )
        
        let config = AppConfiguration(
            indicator: invalidIndicator,
            logging: .default,
            performance: .default
        )
        
        XCTAssertThrowsError(try configManager.save(config)) { error in
            if case TranscriptionIndicatorError.invalidConfig(let field, _) = error {
                XCTAssertEqual(field, "colors.primary")
            } else {
                XCTFail("Expected invalidConfig error")
            }
        }
    }
    
    func testExportImportConfiguration() throws {
        let originalConfig = AppConfiguration.default
        try configManager.save(originalConfig)
        
        // Export configuration
        let exportedJSON = try configManager.exportConfiguration()
        
        // Verify it's valid JSON
        XCTAssertNotNil(exportedJSON.data(using: .utf8))
        
        // Modify and save different configuration
        let modifiedIndicator = IndicatorConfig(
            v: 1,
            mode: .cursor,
            visibility: .auto,
            shape: .ring,
            colors: IndicatorConfig.Colors(primary: "#FF0000"),
            size: 25,
            opacity: 0.7,
            offset: IndicatorConfig.Offset(),
            screenEdgePadding: 8,
            secureFieldPolicy: .hide,
            animations: .default,
            health: .default,
            exitOnIdle: false
        )
        
        let modifiedConfig = AppConfiguration(
            indicator: modifiedIndicator,
            logging: .default,
            performance: .default
        )
        try configManager.save(modifiedConfig)
        
        // Import the original configuration
        try configManager.importConfiguration(from: exportedJSON)
        
        // Verify it matches the original
        let importedConfig = try configManager.load()
        XCTAssertEqual(importedConfig.indicator.mode, originalConfig.indicator.mode)
        XCTAssertEqual(importedConfig.indicator.shape, originalConfig.indicator.shape)
        XCTAssertEqual(importedConfig.indicator.size, originalConfig.indicator.size)
    }
    
    func testResetToDefaults() throws {
        // Save a custom configuration
        let customIndicator = IndicatorConfig(
            v: 1,
            mode: .cursor,
            visibility: .auto,
            shape: .ring,
            colors: IndicatorConfig.Colors(primary: "#FF0000"),
            size: 50,
            opacity: 0.5,
            offset: IndicatorConfig.Offset(),
            screenEdgePadding: 8,
            secureFieldPolicy: .hide,
            animations: .default,
            health: .default,
            exitOnIdle: false
        )
        
        let customConfig = AppConfiguration(
            indicator: customIndicator,
            logging: .default,
            performance: .default
        )
        try configManager.save(customConfig)
        
        // Reset to defaults
        try configManager.resetToDefaults()
        
        // Verify defaults are restored
        let resetConfig = try configManager.load()
        let defaultConfig = AppConfiguration.default
        
        XCTAssertEqual(resetConfig.indicator.mode, defaultConfig.indicator.mode)
        XCTAssertEqual(resetConfig.indicator.shape, defaultConfig.indicator.shape)
        XCTAssertEqual(resetConfig.indicator.size, defaultConfig.indicator.size)
        XCTAssertEqual(resetConfig.indicator.opacity, defaultConfig.indicator.opacity)
    }
    
    func testInvalidImport() {
        let invalidJSON = """
        {"invalid": "json structure that doesn't match AppConfiguration"}
        """
        
        XCTAssertThrowsError(try configManager.importConfiguration(from: invalidJSON))
    }
    
    func testLoggingConfigValidation() {
        let invalidLogging = LoggingConfig(level: "invalid_level", enableSignposts: true)
        let config = AppConfiguration(
            indicator: .default,
            logging: invalidLogging,
            performance: .default
        )
        
        XCTAssertThrowsError(try configManager.validate(config)) { error in
            if case TranscriptionIndicatorError.invalidConfig(let field, _) = error {
                XCTAssertEqual(field, "logging.level")
            } else {
                XCTFail("Expected invalidConfig error for logging level")
            }
        }
    }
    
    func testPerformanceConfigValidation() {
        let invalidPerformance = PerformanceConfig(
            enableMemoryMonitoring: true,
            memoryCheckInterval: 0, // Invalid
            maxMemoryUsage: 50 * 1024 * 1024
        )
        
        let config = AppConfiguration(
            indicator: .default,
            logging: .default,
            performance: invalidPerformance
        )
        
        XCTAssertThrowsError(try configManager.validate(config)) { error in
            if case TranscriptionIndicatorError.invalidConfig(let field, _) = error {
                XCTAssertEqual(field, "performance.memoryCheckInterval")
            } else {
                XCTFail("Expected invalidConfig error for memory check interval")
            }
        }
    }
}