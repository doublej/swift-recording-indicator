import Foundation
import OSLog

final class SecurityValidator {
    private static let logger = Logger(subsystem: "com.transcription.indicator", category: "security")
    
    private static let maxCommandLength = 8192 // 8KB max JSON command
    private static let maxIdLength = 256
    private static let supportedVersions = [1]
    private static let allowedCommands = Set(Command.CommandType.allCases.map(\.rawValue))
    
    // Enhanced validation limits
    private static let maxNestingDepth = 5
    private static let maxTotalKeys = 50
    private static let maxArrayLength = 100
    
    private var rateLimiter = RateLimiter(maxRequests: 100, timeWindow: 60.0)
    
    static func validateCommand(_ input: String) throws -> Command {
        guard input.count <= maxCommandLength else {
            throw TranscriptionIndicatorError.invalidCommand("Command too long")
        }
        
        // Normalize Unicode before processing
        let normalizedInput = input.precomposedStringWithCanonicalMapping
        
        guard let data = normalizedInput.data(using: .utf8) else {
            throw TranscriptionIndicatorError.invalidCommand("Invalid UTF-8 encoding")
        }
        
        // Validate JSON structure before decoding
        try validateJSONStructure(data)
        
        let decoder = JSONDecoder()
        let command: Command
        
        do {
            command = try decoder.decode(Command.self, from: data)
        } catch {
            throw TranscriptionIndicatorError.invalidCommand("Invalid JSON: \(error.localizedDescription)")
        }
        
        try validateCommandStructure(command)
        
        logger.info("Validated command: \(command.command)")
        
        return command
    }
    
    private static func validateCommandStructure(_ command: Command) throws {
        guard command.id.count <= maxIdLength else {
            throw TranscriptionIndicatorError.invalidCommand("ID too long")
        }
        
        guard !command.id.isEmpty else {
            throw TranscriptionIndicatorError.invalidCommand("ID cannot be empty")
        }
        
        guard supportedVersions.contains(command.v) else {
            throw TranscriptionIndicatorError.unsupportedVersion(
                received: command.v, 
                supported: supportedVersions
            )
        }
        
        guard allowedCommands.contains(command.command) else {
            throw TranscriptionIndicatorError.invalidCommand("Unknown command: \(command.command)")
        }
        
        if let config = command.config {
            try validateConfig(config)
        }
    }
    
    static func validateConfig(_ config: IndicatorConfig) throws {
        guard config.size > 0 && config.size <= 200 else {
            throw TranscriptionIndicatorError.invalidConfig(
                field: "size", 
                reason: "must be between 1 and 200"
            )
        }
        
        guard config.opacity >= 0 && config.opacity <= 1 else {
            throw TranscriptionIndicatorError.invalidConfig(
                field: "opacity", 
                reason: "must be between 0.0 and 1.0"
            )
        }
        
        guard config.screenEdgePadding >= 0 && config.screenEdgePadding <= 100 else {
            throw TranscriptionIndicatorError.invalidConfig(
                field: "screenEdgePadding", 
                reason: "must be between 0 and 100"
            )
        }
        
        guard config.colors.alphaPrimary >= 0 && config.colors.alphaPrimary <= 1 else {
            throw TranscriptionIndicatorError.invalidConfig(
                field: "colors.alphaPrimary", 
                reason: "must be between 0.0 and 1.0"
            )
        }
        
        guard config.colors.alphaSecondary >= 0 && config.colors.alphaSecondary <= 1 else {
            throw TranscriptionIndicatorError.invalidConfig(
                field: "colors.alphaSecondary", 
                reason: "must be between 0.0 and 1.0"
            )
        }
        
        try validateColorString(config.colors.primary, field: "colors.primary")
        try validateColorString(config.colors.secondary, field: "colors.secondary")
        
        try validateAnimationConfig(config.animations)
        try validateHealthConfig(config.health)
    }
    
    private static func validateColorString(_ color: String, field: String) throws {
        let hexPattern = #"^#([A-Fa-f0-9]{6}|[A-Fa-f0-9]{8})$"#
        let regex = try NSRegularExpression(pattern: hexPattern)
        let range = NSRange(location: 0, length: color.count)
        
        guard regex.firstMatch(in: color, options: [], range: range) != nil else {
            throw TranscriptionIndicatorError.invalidConfig(
                field: field, 
                reason: "must be a valid hex color (e.g., #FF0000 or #FF0000FF)"
            )
        }
    }
    
    private static func validateAnimationConfig(_ config: AnimationConfig) throws {
        guard config.inDuration > 0 && config.inDuration <= 5.0 else {
            throw TranscriptionIndicatorError.invalidConfig(
                field: "animations.inDuration", 
                reason: "must be between 0.01 and 5.0 seconds"
            )
        }
        
        guard config.outDuration > 0 && config.outDuration <= 5.0 else {
            throw TranscriptionIndicatorError.invalidConfig(
                field: "animations.outDuration", 
                reason: "must be between 0.01 and 5.0 seconds"
            )
        }
        
        guard config.breathingCycle > 0 && config.breathingCycle <= 10.0 else {
            throw TranscriptionIndicatorError.invalidConfig(
                field: "animations.breathingCycle", 
                reason: "must be between 0.1 and 10.0 seconds"
            )
        }
    }
    
    private static func validateHealthConfig(_ config: HealthConfig) throws {
        guard config.interval > 0 && config.interval <= 3600 else {
            throw TranscriptionIndicatorError.invalidConfig(
                field: "health.interval", 
                reason: "must be between 1 and 3600 seconds"
            )
        }
        
        guard config.timeout > config.interval && config.timeout <= 7200 else {
            throw TranscriptionIndicatorError.invalidConfig(
                field: "health.timeout", 
                reason: "must be greater than interval and less than 7200 seconds"
            )
        }
    }
    
    func checkRateLimit() throws {
        guard rateLimiter.allowRequest() else {
            throw TranscriptionIndicatorError.invalidCommand("Rate limit exceeded")
        }
    }
    
    static func sanitizeForLogging(_ input: String) -> String {
        let maxLogLength = 100
        let truncated = input.count > maxLogLength ? String(input.prefix(maxLogLength)) + "..." : input
        return truncated.replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r")
    }
    
    // MARK: - Enhanced JSON Structure Validation
    // Note: validateJSONStructure is implemented in SecurityEnhancements.swift extension
}

private final class RateLimiter {
    private let maxRequests: Int
    private let timeWindow: TimeInterval
    private var requests: [Date] = []
    private let queue = DispatchQueue(label: "rate.limiter", attributes: .concurrent)
    
    init(maxRequests: Int, timeWindow: TimeInterval) {
        self.maxRequests = maxRequests
        self.timeWindow = timeWindow
    }
    
    func allowRequest() -> Bool {
        return queue.sync {
            let now = Date()
            let cutoff = now.addingTimeInterval(-timeWindow)
            
            requests = requests.filter { $0 > cutoff }
            
            guard requests.count < maxRequests else {
                return false
            }
            
            requests.append(now)
            return true
        }
    }
}