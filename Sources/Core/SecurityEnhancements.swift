import Foundation
import CryptoKit
import OSLog
import ApplicationServices

// MARK: - Enhanced Security Validator

extension SecurityValidator {
    
    // MARK: JSON Structure Protection
    
    private static let maxNestingDepth = 5
    private static let maxTotalKeys = 50
    private static let maxArrayLength = 100
    
    static func validateJSONStructure(_ data: Data) throws {
        guard let json = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) else {
            throw TranscriptionIndicatorError.invalidCommand("Invalid JSON structure")
        }
        
        var keyCount = 0
        try validateDepth(json, currentDepth: 0, keyCount: &keyCount)
        
        guard keyCount <= maxTotalKeys else {
            throw TranscriptionIndicatorError.invalidCommand("Too many keys in JSON")
        }
    }
    
    private static func validateDepth(_ object: Any, currentDepth: Int, keyCount: inout Int) throws {
        guard currentDepth <= maxNestingDepth else {
            throw TranscriptionIndicatorError.invalidCommand("JSON nesting too deep")
        }
        
        if let dict = object as? [String: Any] {
            keyCount += dict.count
            for value in dict.values {
                try validateDepth(value, currentDepth: currentDepth + 1, keyCount: &keyCount)
            }
        } else if let array = object as? [Any] {
            guard array.count <= maxArrayLength else {
                throw TranscriptionIndicatorError.invalidCommand("Array too long")
            }
            for value in array {
                try validateDepth(value, currentDepth: currentDepth + 1, keyCount: &keyCount)
            }
        }
    }
    
    // MARK: Unicode and Injection Protection
    
    private static let dangerousPatterns = [
        #"[\\x00-\\x1F\\x7F]"#,  // Control characters
        #"[\u200B-\u200F\u202A-\u202E\u2060-\u206F]"#,  // Zero-width and directional characters
        #"(?i)(javascript|vbscript|data|file):"#,  // URL schemes
        #"[<>\"';(){}\\[\\]`]"#  // Shell metacharacters
    ]
    
    static func sanitizeString(_ input: String) throws -> String {
        // Normalize Unicode
        let normalized = input.precomposedStringWithCanonicalMapping
        
        // Check for dangerous patterns
        for pattern in dangerousPatterns {
            if normalized.range(of: pattern, options: .regularExpression) != nil {
                throw TranscriptionIndicatorError.invalidCommand("Invalid characters detected")
            }
        }
        
        // Additional length check
        guard normalized.count <= 1000 else {
            throw TranscriptionIndicatorError.invalidCommand("String too long")
        }
        
        return normalized
    }
    
    // MARK: Enhanced Config Validation
    
    static func validateConfigSecure(_ config: IndicatorConfig) throws {
        // Existing validation
        try validateConfig(config)
        
        // Additional security checks
        
        // Validate shape enum
        guard IndicatorConfig.Shape.allCases.contains(where: { $0.rawValue == config.shape.rawValue }) else {
            throw TranscriptionIndicatorError.invalidConfig(field: "shape", reason: "Invalid shape value")
        }
        
        // Validate mode enum
        guard IndicatorConfig.Mode.allCases.contains(where: { $0.rawValue == config.mode.rawValue }) else {
            throw TranscriptionIndicatorError.invalidConfig(field: "mode", reason: "Invalid mode value")
        }
        
        // Validate color space
        let allowedColorSpaces = ["sRGB", "displayP3", "genericRGB"]
        guard allowedColorSpaces.contains(config.colors.colorSpace) else {
            throw TranscriptionIndicatorError.invalidConfig(field: "colorSpace", reason: "Invalid color space")
        }
        
        // Validate animation timing
        let allowedTimings = ["linear", "easeIn", "easeOut", "easeInOut"]
        guard allowedTimings.contains(config.animations.timing) else {
            throw TranscriptionIndicatorError.invalidConfig(field: "timing", reason: "Invalid timing function")
        }
    }
}

// MARK: - Message Authentication

final class MessageAuthenticator {
    private let secretKey: SymmetricKey
    private let logger = Logger(subsystem: "com.transcription.indicator", category: "security.auth")
    
    init() throws {
        guard let secretData = ProcessInfo.processInfo.environment["INDICATOR_SECRET"]?.data(using: .utf8),
              secretData.count >= 32 else {
            throw TranscriptionIndicatorError.internalError("Invalid or missing secret key")
        }
        
        self.secretKey = SymmetricKey(data: secretData)
    }
    
    func signMessage(_ message: [String: Any]) throws -> String {
        var mutableMessage = message
        mutableMessage["timestamp"] = ISO8601DateFormatter().string(from: Date())
        mutableMessage["nonce"] = UUID().uuidString
        
        let data = try JSONSerialization.data(withJSONObject: mutableMessage, options: .sortedKeys)
        let signature = HMAC<SHA256>.authenticationCode(for: data, using: secretKey)
        
        return Data(signature).base64EncodedString()
    }
    
    func verifyMessage(_ message: String) throws -> [String: Any] {
        guard let data = message.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let providedHMAC = json["hmac"] as? String,
              let timestamp = json["timestamp"] as? String else {
            throw TranscriptionIndicatorError.invalidCommand("Invalid message format")
        }
        
        // Verify timestamp (prevent replay attacks)
        let formatter = ISO8601DateFormatter()
        guard let messageDate = formatter.date(from: timestamp),
              abs(messageDate.timeIntervalSinceNow) < 30 else { // 30 second window
            throw TranscriptionIndicatorError.invalidCommand("Message timestamp invalid")
        }
        
        // Verify HMAC
        var messageWithoutHMAC = json
        messageWithoutHMAC.removeValue(forKey: "hmac")
        
        let messageData = try JSONSerialization.data(withJSONObject: messageWithoutHMAC, options: .sortedKeys)
        let expectedSignature = HMAC<SHA256>.authenticationCode(for: messageData, using: secretKey)
        let expectedHMAC = Data(expectedSignature).base64EncodedString()
        
        // Constant-time comparison
        guard providedHMAC.count == expectedHMAC.count else {
            throw TranscriptionIndicatorError.invalidCommand("Authentication failed")
        }
        
        var equal = true
        for (a, b) in zip(providedHMAC.utf8, expectedHMAC.utf8) {
            equal = equal && (a == b)
        }
        
        guard equal else {
            throw TranscriptionIndicatorError.invalidCommand("Authentication failed")
        }
        
        return messageWithoutHMAC
    }
}

// MARK: - Secure Memory Management

final class SecureMemoryManager {
    private let logger = Logger(subsystem: "com.transcription.indicator", category: "security.memory")
    private let maxMemoryUsage: UInt64 = 100 * 1024 * 1024 // 100MB
    private var memoryPressureSource: DispatchSourceMemoryPressure?
    
    init() {
        setupMemoryPressureHandler()
    }
    
    private func setupMemoryPressureHandler() {
        memoryPressureSource = DispatchSource.makeMemoryPressureSource(eventMask: [.warning, .critical], queue: .main)
        
        memoryPressureSource?.setEventHandler { [weak self] in
            self?.handleMemoryPressure()
        }
        
        memoryPressureSource?.resume()
    }
    
    private func handleMemoryPressure() {
        logger.warning("Memory pressure detected, clearing caches")
        
        // Clear any caches
        URLCache.shared.removeAllCachedResponses()
        
        // Force garbage collection
        autoreleasepool {
            // Trigger memory cleanup
        }
        
        // Check current memory usage
        if let memoryUsage = getCurrentMemoryUsage(), memoryUsage > maxMemoryUsage {
            logger.error("Memory usage exceeded limit: \(memoryUsage) bytes")
            // Could implement more aggressive cleanup or restart
        }
    }
    
    private func getCurrentMemoryUsage() -> UInt64? {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4
        
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_,
                         task_flavor_t(MACH_TASK_BASIC_INFO),
                         $0,
                         &count)
            }
        }
        
        return result == KERN_SUCCESS ? info.resident_size : nil
    }
    
    deinit {
        memoryPressureSource?.cancel()
    }
}

// MARK: - Runtime Integrity Verification

final class RuntimeIntegrityChecker {
    private let logger = Logger(subsystem: "com.transcription.indicator", category: "security.integrity")
    
    func verifyIntegrity() throws {
        // Check code signature
        try verifyCodeSignature()
        
        // Check for debugger
        if isDebuggerAttached() {
            throw TranscriptionIndicatorError.internalError("Debugger detected")
        }
        
        // Check for jailbreak (if relevant)
        if isJailbroken() {
            throw TranscriptionIndicatorError.internalError("Jailbroken device detected")
        }
    }
    
    private func verifyCodeSignature() throws {
        var staticCode: SecStaticCode?
        let code = SecCodeSelf()
        
        guard SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess,
              let staticCode = staticCode else {
            throw TranscriptionIndicatorError.internalError("Failed to get static code")
        }
        
        // Define requirements
        let requirements = """
            anchor apple generic and \
            identifier "com.transcription.indicator" and \
            certificate leaf[subject.OU] = "YOUR_TEAM_ID"
        """
        
        var requirement: SecRequirement?
        guard SecRequirementCreateWithString(requirements as CFString, [], &requirement) == errSecSuccess,
              let requirement = requirement else {
            throw TranscriptionIndicatorError.internalError("Failed to create requirement")
        }
        
        // Verify
        let result = SecStaticCodeCheckValidity(staticCode, [.enforceRevocationChecks], requirement)
        guard result == errSecSuccess else {
            throw TranscriptionIndicatorError.internalError("Code signature verification failed: \(result)")
        }
        
        logger.info("Code signature verified successfully")
    }
    
    private func isDebuggerAttached() -> Bool {
        var info = kinfo_proc()
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, getpid()]
        var size = MemoryLayout<kinfo_proc>.stride
        
        let result = sysctl(&mib, u_int(mib.count), &info, &size, nil, 0)
        
        return result == 0 && (info.kp_proc.p_flag & P_TRACED) != 0
    }
    
    private func isJailbroken() -> Bool {
        #if targetEnvironment(simulator)
        return false
        #else
        // Check for common jailbreak files
        let jailbreakPaths = [
            "/Applications/Cydia.app",
            "/Library/MobileSubstrate/MobileSubstrate.dylib",
            "/bin/bash",
            "/usr/sbin/sshd",
            "/etc/apt"
        ]
        
        for path in jailbreakPaths {
            if FileManager.default.fileExists(atPath: path) {
                return true
            }
        }
        
        // Check if we can write to system directories
        let systemPath = "/private/test_\(UUID().uuidString)"
        do {
            try "test".write(toFile: systemPath, atomically: true, encoding: .utf8)
            try FileManager.default.removeItem(atPath: systemPath)
            return true // If we can write, device is jailbroken
        } catch {
            // Expected behavior on non-jailbroken device
        }
        
        return false
        #endif
    }
}

// MARK: - Secure Accessibility Wrapper

final class SecureAccessibilityWrapper {
    private let auditLogger = OSLog(subsystem: "com.transcription.indicator", category: "security.audit")
    private let accessQueue = DispatchQueue(label: "accessibility.secure", attributes: .concurrent)
    
    func getAttributeSecure<T>(
        from element: AXUIElement,
        attribute: CFString,
        expectedType: T.Type
    ) async -> T? {
        return await withCheckedContinuation { continuation in
            accessQueue.async {
                var value: CFTypeRef?
                let result = AXUIElementCopyAttributeValue(element, attribute, &value)
                
                // Audit log
                self.logAccessibilityAccess(element: element, attribute: attribute, success: result == .success)
                
                guard result == .success, let value = value else {
                    continuation.resume(returning: nil)
                    return
                }
                
                // Type-safe casting
                if let typedValue = value as? T {
                    continuation.resume(returning: typedValue)
                } else {
                    os_log(.error, log: self.auditLogger, 
                           "Type mismatch for attribute %{public}@", attribute as String)
                    continuation.resume(returning: nil)
                }
            }
        }
    }
    
    private func logAccessibilityAccess(element: AXUIElement, attribute: CFString, success: Bool) {
        var pid: pid_t = 0
        AXUIElementGetPid(element, &pid)
        
        let appName = NSRunningApplication(processIdentifier: pid)?.localizedName ?? "Unknown"
        
        os_signpost(.event, log: auditLogger,
                    name: "AXAccess",
                    "app=%{public}@ attr=%{public}@ success=%{public}@",
                    appName, attribute as String, success ? "true" : "false")
    }
    
    func isDefinitelySecureField(_ element: AXUIElement) async -> Bool {
        // Layer 1: Check subrole (using string literals as constants may not be available)
        if let subrole = await getAttributeSecure(from: element, attribute: "AXSubrole" as CFString, expectedType: String.self),
           subrole == "AXSecureTextField" {
            return true
        }
        
        // Layer 2: Check for password attribute
        if let isPassword = await getAttributeSecure(from: element, attribute: "AXIsPasswordField" as CFString, expectedType: Bool.self),
           isPassword {
            return true
        }
        
        // Layer 3: Check parent context
        if let parent = await getAttributeSecure(from: element, attribute: "AXParent" as CFString, expectedType: AXUIElement.self),
           let parentRole = await getAttributeSecure(from: parent, attribute: "AXRole" as CFString, expectedType: String.self),
           parentRole == "AXSheet" || parentRole == "AXWindow" {
            
            if let title = await getAttributeSecure(from: parent, attribute: "AXTitle" as CFString, expectedType: String.self) {
                let secureKeywords = ["password", "passcode", "pin", "secret", "private", "secure", "auth", "login", "credential"]
                let lowercaseTitle = title.lowercased()
                
                if secureKeywords.contains(where: { lowercaseTitle.contains($0) }) {
                    return true
                }
            }
        }
        
        // Layer 4: Check value pattern (all bullets/asterisks)
        if let value = await getAttributeSecure(from: element, attribute: "AXValue" as CFString, expectedType: String.self),
           !value.isEmpty {
            // Break down the complex expression to avoid type-checking timeout
            let isBullet = value.allSatisfy { $0 == "•" }
            let isAsterisk = value.allSatisfy { $0 == "*" }
            let isCircle = value.allSatisfy { $0 == "●" }
            
            if isBullet || isAsterisk || isCircle {
                return true
            }
        }
        
        return false
    }
}

// MARK: - Security Event Monitor

final class SecurityEventMonitor {
    private let logger = Logger(subsystem: "com.transcription.indicator", category: "security.monitor")
    private var suspiciousActivityCount = 0
    private let suspiciousActivityThreshold = 10
    private var lastActivityReset = Date()
    
    func recordSuspiciousActivity(type: String, details: String) {
        logger.warning("Suspicious activity: \(type) - \(details)")
        
        suspiciousActivityCount += 1
        
        // Reset counter every hour
        if Date().timeIntervalSince(lastActivityReset) > 3600 {
            suspiciousActivityCount = 0
            lastActivityReset = Date()
        }
        
        // Take action if threshold exceeded
        if suspiciousActivityCount > suspiciousActivityThreshold {
            logger.error("Suspicious activity threshold exceeded")
            // Could implement auto-shutdown or alert
        }
    }
    
    func recordSecurityEvent(event: String, severity: OSLogType = .info) {
        logger.log(level: .info, "Security event: \(event, privacy: .public)")
    }
}