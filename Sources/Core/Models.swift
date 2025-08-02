import Foundation
import CoreGraphics

struct Command: Codable {
    let id: String
    let v: Int
    let command: String
    let config: IndicatorConfig?
    
    enum CommandType: String, CaseIterable {
        case show = "show"
        case hide = "hide"
        case health = "health"
        case config = "config"
    }
}

struct CommandResponse: Codable {
    let id: String
    let status: String
    let message: String?
    let timestamp: String?
    let pid: Int?
    let v: Int?
    let code: String?
    let supported: [Int]?
    
    static func success(id: String, message: String) -> CommandResponse {
        return CommandResponse(
            id: id,
            status: "ok",
            message: message,
            timestamp: nil,
            pid: nil,
            v: nil,
            code: nil,
            supported: nil
        )
    }
    
    static func error(id: String, error: TranscriptionIndicatorError) -> CommandResponse {
        return CommandResponse(
            id: id,
            status: "error",
            message: error.localizedDescription,
            timestamp: nil,
            pid: nil,
            v: nil,
            code: error.errorCode,
            supported: nil
        )
    }
    
    static func health(id: String, pid: Int) -> CommandResponse {
        let formatter = ISO8601DateFormatter()
        return CommandResponse(
            id: id,
            status: "alive",
            message: nil,
            timestamp: formatter.string(from: Date()),
            pid: pid,
            v: 1,
            code: nil,
            supported: nil
        )
    }
}

struct HealthResponse: Codable {
    let status: String
    let timestamp: String
    let pid: Int
    let v: Int
    let memoryUsage: UInt64?
    let cpuUsage: Double?
}

struct IndicatorConfig: Codable {
    let v: Int
    let mode: Mode
    let visibility: Visibility
    let shape: Shape
    let colors: Colors
    let size: Double
    let opacity: Double
    let offset: Offset
    let screenEdgePadding: Double
    let secureFieldPolicy: SecureFieldPolicy
    let animations: AnimationConfig
    let health: HealthConfig
    let exitOnIdle: Bool
    
    enum Mode: String, Codable, CaseIterable {
        case caret = "caret"
        case cursor = "cursor"
    }
    
    enum Visibility: String, Codable, CaseIterable {
        case auto = "auto"
        case forceOn = "forceOn"
        case forceOff = "forceOff"
    }
    
    enum Shape: String, Codable, CaseIterable {
        case circle = "circle"
        case ring = "ring"
        case orb = "orb"
        case custom = "custom"
    }
    
    enum SecureFieldPolicy: String, Codable, CaseIterable {
        case hide = "hide"
        case dim = "dim"
        case allow = "allow"
    }
    
    struct Colors: Codable {
        let primary: String
        let secondary: String
        let alphaPrimary: Double
        let alphaSecondary: Double
        let colorSpace: String
        
        init(primary: String = "#FF0000", 
             secondary: String = "#FF8888", 
             alphaPrimary: Double = 1.0, 
             alphaSecondary: Double = 0.7, 
             colorSpace: String = "sRGB") {
            self.primary = primary
            self.secondary = secondary
            self.alphaPrimary = alphaPrimary
            self.alphaSecondary = alphaSecondary
            self.colorSpace = colorSpace
        }
    }
    
    struct Offset: Codable {
        let x: Double
        let y: Double
        
        init(x: Double = 0, y: Double = -10) {
            self.x = x
            self.y = y
        }
    }
    
    static let `default` = IndicatorConfig(
        v: 1,
        mode: .caret,
        visibility: .auto,
        shape: .circle,
        colors: Colors(),
        size: 20,
        opacity: 0.9,
        offset: Offset(),
        screenEdgePadding: 8,
        secureFieldPolicy: .hide,
        animations: AnimationConfig.default,
        health: HealthConfig.default,
        exitOnIdle: false
    )
}

struct AnimationConfig: Codable {
    let inDuration: Double
    let outDuration: Double
    let breathingCycle: Double
    let timing: String
    
    static let `default` = AnimationConfig(
        inDuration: 0.25,
        outDuration: 0.18,
        breathingCycle: 1.8,
        timing: "easeInOut"
    )
}

struct HealthConfig: Codable {
    let interval: Double
    let timeout: Double
    
    static let `default` = HealthConfig(
        interval: 30,
        timeout: 75
    )
}

struct AppConfiguration: Codable {
    let indicator: IndicatorConfig
    let logging: LoggingConfig
    let performance: PerformanceConfig
    
    static let `default` = AppConfiguration(
        indicator: .default,
        logging: .default,
        performance: .default
    )
}

struct LoggingConfig: Codable {
    let level: String
    let enableSignposts: Bool
    
    static let `default` = LoggingConfig(
        level: "info",
        enableSignposts: true
    )
}

struct PerformanceConfig: Codable {
    let enableMemoryMonitoring: Bool
    let memoryCheckInterval: Double
    let maxMemoryUsage: UInt64
    
    static let `default` = PerformanceConfig(
        enableMemoryMonitoring: true,
        memoryCheckInterval: 30.0,
        maxMemoryUsage: 50 * 1024 * 1024 // 50MB
    )
}

enum AnimationState {
    case off
    case appearing
    case idle
    case disappearing
}