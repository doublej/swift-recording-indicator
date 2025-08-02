import XCTest
@testable import TranscriptionIndicator

final class SecurityValidatorTests: XCTestCase {
    
    func testValidCommandValidation() throws {
        let validJSON = """
        {"id":"test1","v":1,"command":"show","config":{"shape":"circle","size":20,"opacity":0.9}}
        """
        
        let command = try SecurityValidator.validateCommand(validJSON)
        
        XCTAssertEqual(command.id, "test1")
        XCTAssertEqual(command.v, 1)
        XCTAssertEqual(command.command, "show")
        XCTAssertNotNil(command.config)
    }
    
    func testInvalidJSONRejection() {
        let invalidJSON = """
        {"invalid json": malformed
        """
        
        XCTAssertThrowsError(try SecurityValidator.validateCommand(invalidJSON)) { error in
            if case TranscriptionIndicatorError.invalidCommand(let message) = error {
                XCTAssertTrue(message.contains("Invalid JSON"))
            } else {
                XCTFail("Expected invalidCommand error")
            }
        }
    }
    
    func testCommandTooLong() {
        let longCommand = String(repeating: "x", count: 10000)
        let commandJSON = """
        {"id":"test","v":1,"command":"show","data":"\(longCommand)"}
        """
        
        XCTAssertThrowsError(try SecurityValidator.validateCommand(commandJSON)) { error in
            if case TranscriptionIndicatorError.invalidCommand(let message) = error {
                XCTAssertTrue(message.contains("too long"))
            } else {
                XCTFail("Expected invalidCommand error for length")
            }
        }
    }
    
    func testUnsupportedVersion() {
        let unsupportedVersionJSON = """
        {"id":"test","v":999,"command":"show"}
        """
        
        XCTAssertThrowsError(try SecurityValidator.validateCommand(unsupportedVersionJSON)) { error in
            if case TranscriptionIndicatorError.unsupportedVersion(let received, let supported) = error {
                XCTAssertEqual(received, 999)
                XCTAssertEqual(supported, [1])
            } else {
                XCTFail("Expected unsupportedVersion error")
            }
        }
    }
    
    func testInvalidCommand() {
        let invalidCommandJSON = """
        {"id":"test","v":1,"command":"invalid_command"}
        """
        
        XCTAssertThrowsError(try SecurityValidator.validateCommand(invalidCommandJSON)) { error in
            if case TranscriptionIndicatorError.invalidCommand(let message) = error {
                XCTAssertTrue(message.contains("Unknown command"))
            } else {
                XCTFail("Expected invalidCommand error")
            }
        }
    }
    
    func testConfigValidation() throws {
        // Valid config
        let validConfig = IndicatorConfig.default
        XCTAssertNoThrow(try SecurityValidator.validateConfig(validConfig))
        
        // Invalid size
        var invalidConfig = validConfig
        invalidConfig = IndicatorConfig(
            v: validConfig.v,
            mode: validConfig.mode,
            visibility: validConfig.visibility,
            shape: validConfig.shape,
            colors: validConfig.colors,
            size: -1, // Invalid
            opacity: validConfig.opacity,
            offset: validConfig.offset,
            screenEdgePadding: validConfig.screenEdgePadding,
            secureFieldPolicy: validConfig.secureFieldPolicy,
            animations: validConfig.animations,
            health: validConfig.health,
            exitOnIdle: validConfig.exitOnIdle
        )
        
        XCTAssertThrowsError(try SecurityValidator.validateConfig(invalidConfig)) { error in
            if case TranscriptionIndicatorError.invalidConfig(let field, _) = error {
                XCTAssertEqual(field, "size")
            } else {
                XCTFail("Expected invalidConfig error for size")
            }
        }
    }
    
    func testColorValidation() {
        let validColors = ["#FF0000", "#00FF00FF", "#123456", "#ABCDEF00"]
        let invalidColors = ["FF0000", "#GG0000", "#12345", "red", ""]
        
        for color in validColors {
            let config = IndicatorConfig(
                v: 1,
                mode: .caret,
                visibility: .auto,
                shape: .circle,
                colors: IndicatorConfig.Colors(primary: color),
                size: 20,
                opacity: 1.0,
                offset: IndicatorConfig.Offset(),
                screenEdgePadding: 8,
                secureFieldPolicy: .hide,
                animations: .default,
                health: .default,
                exitOnIdle: false
            )
            
            XCTAssertNoThrow(try SecurityValidator.validateConfig(config), "Valid color \(color) should pass")
        }
        
        for color in invalidColors {
            let config = IndicatorConfig(
                v: 1,
                mode: .caret,
                visibility: .auto,
                shape: .circle,
                colors: IndicatorConfig.Colors(primary: color),
                size: 20,
                opacity: 1.0,
                offset: IndicatorConfig.Offset(),
                screenEdgePadding: 8,
                secureFieldPolicy: .hide,
                animations: .default,
                health: .default,
                exitOnIdle: false
            )
            
            XCTAssertThrowsError(try SecurityValidator.validateConfig(config), "Invalid color \(color) should fail")
        }
    }
    
    func testSanitizeForLogging() {
        let input = "This is a test\nwith newlines\rand carriage returns"
        let sanitized = SecurityValidator.sanitizeForLogging(input)
        
        XCTAssertFalse(sanitized.contains("\n"))
        XCTAssertFalse(sanitized.contains("\r"))
        XCTAssertTrue(sanitized.contains("\\n"))
        XCTAssertTrue(sanitized.contains("\\r"))
    }
    
    func testLongStringSanitization() {
        let longInput = String(repeating: "a", count: 200)
        let sanitized = SecurityValidator.sanitizeForLogging(longInput)
        
        XCTAssertTrue(sanitized.count <= 103) // 100 chars + "..."
        XCTAssertTrue(sanitized.hasSuffix("..."))
    }
}