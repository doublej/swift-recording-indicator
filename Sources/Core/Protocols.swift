import Foundation
import CoreGraphics

protocol CommandProcessing: Actor {
    func process(_ command: Command) async throws -> CommandResponse
    func setDependencies(detector: TextInputDetecting, renderer: IndicatorRendering) async
}

protocol TextInputDetecting: Actor {
    var caretRectPublisher: AsyncStream<CGRect?> { get }
    func startDetection() async throws
    func stopDetection() async
}

@MainActor
protocol IndicatorRendering {
    func show(config: IndicatorConfig) async
    func hide() async
    func updateConfig(_ config: IndicatorConfig) async
    func updatePosition(_ rect: CGRect, config: IndicatorConfig) async
}

protocol ConfigurationManaging {
    func load() throws -> AppConfiguration
    func save(_ config: AppConfiguration) throws
    func validate(_ config: AppConfiguration) throws
}

protocol HealthMonitoring: Actor {
    func startMonitoring(interval: TimeInterval) async
    func stopMonitoring() async
    func reportHealth() async -> HealthResponse
}

protocol AccessibilityProviding {
    func observeCaretChanges() -> AsyncStream<CGRect?>
    func requestPermissions() async -> Bool
    func checkPermissions() -> Bool
}

protocol AnimationProviding: Actor {
    func animate(to state: AnimationState) async
    func updateConfiguration(_ config: AnimationConfig) async
}

protocol CommunicationHandling: Actor {
    func startListening() async throws
    func stopListening() async
    func sendResponse(_ response: CommandResponse) async throws
}