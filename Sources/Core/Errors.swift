import Foundation

enum TranscriptionIndicatorError: Error, LocalizedError, Codable {
    case invalidCommand(String)
    case invalidConfig(field: String, reason: String)
    case unsupportedVersion(received: Int, supported: [Int])
    case permissionDenied(permission: String)
    case internalError(String)
    case communicationFailure(String)
    case accessibilityError(String)
    
    var errorDescription: String? {
        switch self {
        case .invalidCommand(let cmd):
            return "Invalid command: \(cmd)"
        case .invalidConfig(let field, let reason):
            return "Invalid configuration for \(field): \(reason)"
        case .unsupportedVersion(let received, let supported):
            return "Unsupported version \(received). Supported: \(supported)"
        case .permissionDenied(let permission):
            return "Permission denied: \(permission)"
        case .internalError(let message):
            return "Internal error: \(message)"
        case .communicationFailure(let message):
            return "Communication failure: \(message)"
        case .accessibilityError(let message):
            return "Accessibility error: \(message)"
        }
    }
    
    var errorCode: String {
        switch self {
        case .invalidCommand: return "INVALID_COMMAND"
        case .invalidConfig: return "INVALID_CONFIG"
        case .unsupportedVersion: return "UNSUPPORTED_VERSION"
        case .permissionDenied: return "PERMISSION_DENIED"
        case .internalError: return "INTERNAL_ERROR"
        case .communicationFailure: return "COMMUNICATION_FAILURE"
        case .accessibilityError: return "ACCESSIBILITY_ERROR"
        }
    }
}

typealias DetectionResult = Result<CGRect?, TranscriptionIndicatorError>
typealias CommandResult = Result<CommandResponse, TranscriptionIndicatorError>