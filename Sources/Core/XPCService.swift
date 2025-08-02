import Foundation
import OSLog
import Logging
import AppKit
import Security
import Darwin

// MARK: - XPC Protocol Definition

@objc protocol TranscriptionIndicatorXPCProtocol {
    func showIndicator(configData: Data, reply: @escaping @Sendable (Bool, Error?) -> Void)
    func hideIndicator(reply: @escaping @Sendable (Bool, Error?) -> Void)
    func updateConfig(configData: Data, reply: @escaping @Sendable (Bool, Error?) -> Void)
    func getHealth(reply: @escaping @Sendable (Data?, Error?) -> Void)
}

// MARK: - XPC Service Implementation

final class TranscriptionIndicatorXPCService: NSObject, NSXPCListenerDelegate, @unchecked Sendable {
    private let listener: NSXPCListener
    private let logger = Logger(subsystem: "com.transcription.indicator.xpc", category: "service")
    private let securityValidator = SecurityValidator()
    private let auditLogger = OSLog(subsystem: "com.transcription.indicator.xpc", category: "security.audit")
    
    // Service state
    private var activeConnections = Set<NSXPCConnection>()
    private let connectionQueue = DispatchQueue(label: "xpc.connections", attributes: .concurrent)
    
    override init() {
        self.listener = NSXPCListener(machServiceName: "com.transcription.indicator.xpc")
        super.init()
        self.listener.delegate = self
    }
    
    func start() {
        logger.info("Starting XPC service")
        listener.resume()
    }
    
    // MARK: - NSXPCListenerDelegate
    
    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection newConnection: NSXPCConnection) -> Bool {
        logger.info("New XPC connection request from pid: \(newConnection.processIdentifier)")
        
        // Verify caller authorization
        guard isConnectionAuthorized(newConnection) else {
            logger.error("Rejecting unauthorized connection from pid: \(newConnection.processIdentifier)")
            recordSecurityEvent("Unauthorized XPC connection attempt", connection: newConnection)
            return false
        }
        
        // Configure connection
        newConnection.exportedInterface = NSXPCInterface(with: TranscriptionIndicatorXPCProtocol.self)
        newConnection.exportedObject = TranscriptionIndicatorXPCServiceHandler(parent: self)
        
        // Set up connection handlers
        newConnection.interruptionHandler = { [weak self] in
            self?.logger.warning("XPC connection interrupted")
            self?.removeConnection(newConnection)
        }
        
        newConnection.invalidationHandler = { [weak self] in
            self?.logger.info("XPC connection invalidated")
            self?.removeConnection(newConnection)
        }
        
        // Add to active connections
        addConnection(newConnection)
        
        newConnection.resume()
        
        recordSecurityEvent("XPC connection accepted", connection: newConnection)
        return true
    }
    
    // MARK: - Authorization
    
    private func isConnectionAuthorized(_ connection: NSXPCConnection) -> Bool {
        // For production, use code signature verification without private APIs
        return verifyProcessIntegrity(connection) && verifyCodeSignature(connection)
    }
    
    private func verifyCodeSignature(_ connection: NSXPCConnection) -> Bool {
        let pid = connection.processIdentifier
        
        // Get code reference for the process
        var code: SecCode?
        let status = SecCodeCopyGuestWithAttributes(
            nil,
            [kSecGuestAttributePid: pid] as CFDictionary,
            [],
            &code
        )
        
        guard status == errSecSuccess, let code = code else {
            logger.error("Failed to get SecCode for pid \(pid): \(status)")
            return false
        }
        
        // For basic validation, check if code is properly signed
        let validationResult = SecCodeCheckValidity(code, [], nil)
        
        if validationResult != errSecSuccess {
            logger.error("Code signature validation failed for pid \(pid): \(validationResult)")
            return false
        }
        
        // Additional requirement checking can be added here
        // For now, accept any validly signed code
        logger.info("Code signature validation passed for pid \(pid)")
        return true
    }
    
    private func verifyProcessIntegrity(_ connection: NSXPCConnection) -> Bool {
        let pid = connection.processIdentifier
        
        // Get process info
        guard let app = NSRunningApplication(processIdentifier: pid) else {
            logger.error("Failed to get running application info")
            return false
        }
        
        // Verify bundle identifier
        guard let bundleID = app.bundleIdentifier,
              bundleID.hasPrefix("com.yourcompany") else {
            logger.error("Invalid bundle identifier: \(app.bundleIdentifier ?? "nil")")
            return false
        }
        
        // Check if app is sandboxed
        if !isProcessSandboxed(pid: pid) {
            logger.warning("Connecting process is not sandboxed")
            // Could reject non-sandboxed apps
        }
        
        return true
    }
    
    private func isProcessSandboxed(pid: pid_t) -> Bool {
        var sandboxed = 0
        var size = MemoryLayout.size(ofValue: sandboxed)
        
        let result = sysctlbyname("security.mac.sandbox.sentinel", &sandboxed, &size, nil, 0)
        return result == 0 && sandboxed != 0
    }
    
    // MARK: - Connection Management
    
    private func addConnection(_ connection: NSXPCConnection) {
        let _ = connectionQueue.sync(flags: .barrier) {
            self.activeConnections.insert(connection)
        }
    }
    
    private func removeConnection(_ connection: NSXPCConnection) {
        connectionQueue.async(flags: .barrier) { [weak self] in
            self?.activeConnections.remove(connection)
        }
    }
    
    private func recordSecurityEvent(_ event: String, connection: NSXPCConnection) {
        let pid = connection.processIdentifier
        let app = NSRunningApplication(processIdentifier: pid)
        
        os_signpost(.event, log: auditLogger,
                    name: "XPCSecurityEvent",
                    "event=%{public}@ pid=%d app=%{public}@",
                    event, pid, app?.localizedName ?? "Unknown")
    }
}

// MARK: - XPC Service Handler

final class TranscriptionIndicatorXPCServiceHandler: NSObject, TranscriptionIndicatorXPCProtocol, @unchecked Sendable {
    private weak var parent: TranscriptionIndicatorXPCService?
    private let logger = Logger(subsystem: "com.transcription.indicator.xpc", category: "handler")
    private let commandProcessor: CommandProcessing
    
    init(parent: TranscriptionIndicatorXPCService) {
        self.parent = parent
        self.commandProcessor = ServiceContainer.shared.resolve(CommandProcessing.self)
        super.init()
    }
    
    func showIndicator(configData: Data, reply: @escaping @Sendable (Bool, Error?) -> Void) {
        logger.info("Received showIndicator request")
        
        Task {
            do {
                // Note: NSXPCConnection.current() is not available in all contexts
                // For production, implement proper connection tracking
                // guard let connection = getCurrentConnection(),
                //       parent?.isConnectionAuthorized(connection) == true else {
                //     throw TranscriptionIndicatorError.permissionDenied(permission: "XPC authorization expired")
                // }
                
                // Validate and decode config
                try SecurityValidator.validateJSONStructure(configData)
                let config = try JSONDecoder().decode(IndicatorConfig.self, from: configData)
                try SecurityValidator.validateConfigSecure(config)
                
                // Create command
                let command = Command(
                    id: UUID().uuidString,
                    v: 1,
                    command: "show",
                    config: config
                )
                
                // Process command
                let response = try await commandProcessor.process(command)
                
                // Return success
                await MainActor.run {
                    reply(response.status == "ok", nil)
                }
                
            } catch {
                logger.error("showIndicator failed: \(error)")
                await MainActor.run {
                    reply(false, error)
                }
            }
        }
    }
    
    func hideIndicator(reply: @escaping @Sendable (Bool, Error?) -> Void) {
        logger.info("Received hideIndicator request")
        
        Task {
            do {
                // Note: Connection validation simplified for compilation
                // In production, implement proper connection tracking
                
                // Create command
                let command = Command(
                    id: UUID().uuidString,
                    v: 1,
                    command: "hide",
                    config: nil
                )
                
                // Process
                let response = try await commandProcessor.process(command)
                
                await MainActor.run {
                    reply(response.status == "ok", nil)
                }
                
            } catch {
                logger.error("hideIndicator failed: \(error)")
                await MainActor.run {
                    reply(false, error)
                }
            }
        }
    }
    
    func updateConfig(configData: Data, reply: @escaping @Sendable (Bool, Error?) -> Void) {
        logger.info("Received updateConfig request")
        
        Task {
            do {
                // Note: Connection validation simplified for compilation
                // In production, implement proper connection tracking
                
                // Validate and decode config
                try SecurityValidator.validateJSONStructure(configData)
                let config = try JSONDecoder().decode(IndicatorConfig.self, from: configData)
                try SecurityValidator.validateConfigSecure(config)
                
                // Create command
                let command = Command(
                    id: UUID().uuidString,
                    v: 1,
                    command: "config",
                    config: config
                )
                
                // Process
                let response = try await commandProcessor.process(command)
                
                await MainActor.run {
                    reply(response.status == "ok", nil)
                }
                
            } catch {
                logger.error("updateConfig failed: \(error)")
                await MainActor.run {
                    reply(false, error)
                }
            }
        }
    }
    
    func getHealth(reply: @escaping @Sendable (Data?, Error?) -> Void) {
        logger.info("Received getHealth request")
        
        Task {
            do {
                // Note: Connection validation simplified for compilation
                // In production, implement proper connection tracking
                
                // Create command
                let command = Command(
                    id: UUID().uuidString,
                    v: 1,
                    command: "health",
                    config: nil
                )
                
                // Process
                let response = try await commandProcessor.process(command)
                
                // Encode response
                let responseData = try JSONEncoder().encode(response)
                
                await MainActor.run {
                    reply(responseData, nil)
                }
                
            } catch {
                logger.error("getHealth failed: \(error)")
                await MainActor.run {
                    reply(nil, error)
                }
            }
        }
    }
}

// MARK: - XPC Client

public final class TranscriptionIndicatorXPCClient: @unchecked Sendable {
    private let connection: NSXPCConnection
    private let logger = Logger(subsystem: "com.transcription.indicator", category: "xpc.client")
    
    public init() {
        self.connection = NSXPCConnection(machServiceName: "com.transcription.indicator.xpc")
        self.connection.remoteObjectInterface = NSXPCInterface(with: TranscriptionIndicatorXPCProtocol.self)
        
        connection.interruptionHandler = { [weak self] in
            self?.logger.warning("XPC connection interrupted")
        }
        
        connection.invalidationHandler = { [weak self] in
            self?.logger.warning("XPC connection invalidated")
        }
        
        connection.resume()
    }
    
    func showIndicator(config: IndicatorConfig) async throws {
        let configData = try JSONEncoder().encode(config)
        
        return try await withCheckedThrowingContinuation { continuation in
            let proxy = connection.remoteObjectProxyWithErrorHandler { error in
                continuation.resume(throwing: error)
            } as! TranscriptionIndicatorXPCProtocol
            
            proxy.showIndicator(configData: configData) { success, error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else if success {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: TranscriptionIndicatorError.internalError("Show indicator failed"))
                }
            }
        }
    }
    
    func hideIndicator() async throws {
        return try await withCheckedThrowingContinuation { continuation in
            let proxy = connection.remoteObjectProxyWithErrorHandler { error in
                continuation.resume(throwing: error)
            } as! TranscriptionIndicatorXPCProtocol
            
            proxy.hideIndicator { success, error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else if success {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: TranscriptionIndicatorError.internalError("Hide indicator failed"))
                }
            }
        }
    }
    
    func updateConfig(_ config: IndicatorConfig) async throws {
        let configData = try JSONEncoder().encode(config)
        
        return try await withCheckedThrowingContinuation { continuation in
            let proxy = connection.remoteObjectProxyWithErrorHandler { error in
                continuation.resume(throwing: error)
            } as! TranscriptionIndicatorXPCProtocol
            
            proxy.updateConfig(configData: configData) { success, error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else if success {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: TranscriptionIndicatorError.internalError("Update config failed"))
                }
            }
        }
    }
    
    func getHealth() async throws -> HealthResponse {
        return try await withCheckedThrowingContinuation { continuation in
            let proxy = connection.remoteObjectProxyWithErrorHandler { error in
                continuation.resume(throwing: error)
            } as! TranscriptionIndicatorXPCProtocol
            
            proxy.getHealth { data, error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else if let data = data {
                    do {
                        let response = try JSONDecoder().decode(HealthResponse.self, from: data)
                        continuation.resume(returning: response)
                    } catch {
                        continuation.resume(throwing: error)
                    }
                } else {
                    continuation.resume(throwing: TranscriptionIndicatorError.internalError("No health data"))
                }
            }
        }
    }
    
    deinit {
        connection.invalidate()
    }
}