import Foundation
import AppKit

final class SimpleStdinHandler {
    private let processor: SimpleCommandProcessor
    private var isListening = false
    
    init(processor: SimpleCommandProcessor) {
        self.processor = processor
    }
    
    func startListening() {
        guard !isListening else { return }
        isListening = true
        
        DispatchQueue.global(qos: .background).async {
            self.handleStdinInput()
        }
    }
    
    func stopListening() {
        isListening = false
    }
    
    private func handleStdinInput() {
        while let line = readLine(strippingNewline: true) {
            guard isListening else { break }
            
            if line.isEmpty { continue }
            
            DispatchQueue.main.sync {
                let response = self.processor.processCommand(line)
                print(response)
                fflush(stdout)
            }
        }
        
        stopListening()
        
        // Keep app alive to show window
        DispatchQueue.main.asyncAfter(deadline: .now() + 15) {
            NSApplication.shared.terminate(nil)
        }
    }
}