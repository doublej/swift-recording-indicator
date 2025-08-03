import Foundation
import AppKit
import Logging

@MainActor 
final class SimpleStdinHandler {
    private let logger = Logger(label: "simple.stdin.handler")
    private let processor: SimpleCommandProcessor
    private var isListening = false
    
    init(processor: SimpleCommandProcessor) {
        self.processor = processor
    }
    
    func startListening() async {
        guard !isListening else { return }
        isListening = true
        
        logger.info("Simple stdin handler started")
        logger.info("Commands: 'show [circle|ring|orb] [size]', 'hide', 'health'")
        
        await handleStdinInput()
    }
    
    func stopListening() {
        isListening = false
        logger.info("Simple stdin handler stopped")
    }
    
    private func handleStdinInput() async {
        while let line = readLine(strippingNewline: true) {
            guard isListening else { break }
            
            if line.isEmpty { continue }
            
            let response = await processor.processCommand(line)
            print(response)
            fflush(stdout)
        }
        
        logger.info("Stdin closed, keeping app alive for 15 seconds")
        stopListening()
        
        // Keep app alive to show window
        DispatchQueue.main.asyncAfter(deadline: .now() + 15) {
            NSApplication.shared.terminate(nil)
        }
    }
}