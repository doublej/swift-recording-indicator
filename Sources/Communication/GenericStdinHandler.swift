import Foundation
import AppKit
import Logging

protocol CommandProcessorProtocol {
    func processCommand(_ line: String) async -> String
}

extension SimpleCommandProcessor: CommandProcessorProtocol {}
extension EnhancedCommandProcessor: CommandProcessorProtocol {}

@MainActor 
final class GenericStdinHandler {
    private let logger = Logger(label: "generic.stdin.handler")
    private let processor: CommandProcessorProtocol
    private var isListening = false
    
    init(processor: CommandProcessorProtocol) {
        self.processor = processor
    }
    
    func startListening() async {
        guard !isListening else { return }
        isListening = true
        
        logger.info("Generic stdin handler started")
        logger.info("Commands: 'show [circle|ring|orb] [size]', 'show center [size]', 'hide', 'health'")
        
        await handleStdinInput()
    }
    
    func stopListening() {
        isListening = false
        logger.info("Generic stdin handler stopped")
    }
    
    private func handleStdinInput() async {
        let inputStream = FileHandle.standardInput
        
        while isListening {
            // Non-blocking check for available data
            let availableData = inputStream.availableData
            
            if availableData.isEmpty {
                // No data available, sleep briefly and continue
                try? await Task.sleep(nanoseconds: 100_000_000) // 100ms
                continue
            }
            
            guard let input = String(data: availableData, encoding: .utf8) else {
                logger.error("Failed to decode stdin input")
                continue
            }
            
            let lines = input.components(separatedBy: .newlines)
            
            for line in lines {
                let trimmedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
                
                if !trimmedLine.isEmpty {
                    logger.debug("Received input: '\(trimmedLine)'")
                    
                    let response = await processor.processCommand(trimmedLine)
                    print(response)
                    fflush(stdout) // Ensure immediate output
                }
            }
        }
        
        logger.info("Stdin handler finished")
    }
}