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
    
    // Response buffer for batching
    private var responseBuffer: [CommandResponse] = []
    private var responseTimer: DispatchSourceTimer?
    private let responseQueue = DispatchQueue(label: "response.queue", qos: .userInteractive)
    private let maxBufferSize = 10
    private let bufferFlushDelay: TimeInterval = 0.001 // 1ms
    
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
        // Add to buffer
        responseBuffer.append(response)
        
        // Flush immediately if buffer is full or this is a high-priority response
        if responseBuffer.count >= maxBufferSize || response.status == "error" {
            await flushResponseBuffer()
        } else {
            // Schedule flush
            scheduleResponseFlush()
        }
    }
    
    private func scheduleResponseFlush() {
        responseTimer?.cancel()
        
        let timer = DispatchSource.makeTimerSource(queue: responseQueue)
        timer.schedule(deadline: .now() + bufferFlushDelay)
        timer.setEventHandler { [weak self] in
            Task {
                await self?.flushResponseBuffer()
            }
        }
        timer.resume()
        responseTimer = timer
    }
    
    private func flushResponseBuffer() async {
        guard !responseBuffer.isEmpty else { return }
        
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        
        let responses = responseBuffer
        responseBuffer.removeAll()
        
        // Send all buffered responses
        for response in responses {
            do {
                let data = try encoder.encode(response)
                if let jsonString = String(data: data, encoding: .utf8) {
                    print(jsonString, terminator: "\n")
                }
            } catch {
                logger.error("Failed to encode response: \(error.localizedDescription)")
            }
        }
        
        fflush(stdout)
        logger.debug("Flushed \(responses.count) responses")
    }
    
    private func handleStdinInput() async {
        let stdin = FileHandle.standardInput
        
        // Set stdin to non-blocking mode for better performance
        var flags = fcntl(stdin.fileDescriptor, F_GETFL)
        fcntl(stdin.fileDescriptor, F_SETFL, flags | O_NONBLOCK)
        
        do {
            for try await line in stdin.bytes.lines {
                guard isListening else { break }
                
                let signpostID = OSSignpostID(log: signpostLogger)
                os_signpost(.begin, log: signpostLogger, name: "ProcessCommand", signpostID: signpostID)
                
                // Process in parallel for better throughput
                Task {
                    await processInputLine(line)
                }
                
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