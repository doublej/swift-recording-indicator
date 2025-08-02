import Foundation
import Logging
import OSLog
import AppKit

actor StdinStdoutHandler: CommunicationHandling {
    private let logger = Logger(label: "stdin.handler")
    private let signpostLogger = OSLog(subsystem: "com.transcription.indicator", category: "communication")
    
    private let processor: CommandProcessing
    private var isListening = false
    private var stdinTask: Task<Void, Never>?
    private let securityValidator = SecurityValidator()
    
    init(processor: CommandProcessing) {
        self.processor = processor
    }
    
    func startListening() async throws {
        guard !isListening else { return }
        isListening = true
        
        logger.info("Starting stdin communication handler")
        
        stdinTask = Task {
            await handleStdinInput()
        }
    }
    
    func stopListening() async {
        isListening = false
        stdinTask?.cancel()
        stdinTask = nil
        logger.info("Stopped stdin communication handler")
    }
    
    func sendResponse(_ response: CommandResponse) async throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        
        do {
            let data = try encoder.encode(response)
            if let jsonString = String(data: data, encoding: .utf8) {
                print(jsonString, terminator: "\n")
                fflush(stdout)
                
                logger.debug("Sent response: \(SecurityValidator.sanitizeForLogging(jsonString))")
            }
        } catch {
            logger.error("Failed to encode response: \(error.localizedDescription)")
            throw TranscriptionIndicatorError.communicationFailure("Failed to encode response")
        }
    }
    
    private func handleStdinInput() async {
        let stdin = FileHandle.standardInput
        
        do {
            for try await line in stdin.bytes.lines {
                guard isListening else { break }
                
                let signpostID = OSSignpostID(log: signpostLogger)
                os_signpost(.begin, log: signpostLogger, name: "ProcessCommand", signpostID: signpostID)
                
                await processInputLine(line)
                
                os_signpost(.end, log: signpostLogger, name: "ProcessCommand", signpostID: signpostID)
            }
        } catch {
            logger.error("Stdin reading error: \(error.localizedDescription)")
            if isListening {
                await handleCommunicationFailure()
            }
        }
        
        logger.info("Stdin handler exited")
        if isListening {
            await handleEOF()
        }
    }
    
    private func processInputLine(_ line: String) async {
        logger.debug("Processing input line: \(SecurityValidator.sanitizeForLogging(line))")
        
        do {
            try securityValidator.checkRateLimit()
            
            let command = try SecurityValidator.validateCommand(line)
            let response = try await processor.process(command)
            try await sendResponse(response)
            
        } catch let error as TranscriptionIndicatorError {
            let errorResponse = CommandResponse.error(id: extractIdFromLine(line), error: error)
            do {
                try await sendResponse(errorResponse)
            } catch {
                logger.error("Failed to send error response: \(error.localizedDescription)")
            }
        } catch {
            let internalError = TranscriptionIndicatorError.internalError(error.localizedDescription)
            let errorResponse = CommandResponse.error(id: extractIdFromLine(line), error: internalError)
            do {
                try await sendResponse(errorResponse)
            } catch {
                logger.error("Failed to send internal error response: \(error.localizedDescription)")
            }
        }
    }
    
    private func extractIdFromLine(_ line: String) -> String {
        if let data = line.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let id = json["id"] as? String {
            return id
        }
        return "unknown"
    }
    
    private func handleEOF() async {
        logger.info("EOF detected, initiating graceful shutdown")
        await stopListening()
        
        await MainActor.run {
            NSApplication.shared.terminate(nil)
        }
    }
    
    private func handleCommunicationFailure() async {
        logger.error("Communication failure detected")
        await stopListening()
        
        await MainActor.run {
            NSApplication.shared.terminate(nil)
        }
    }
}