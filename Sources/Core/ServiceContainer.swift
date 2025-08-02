import Foundation

@MainActor
final class ServiceContainer {
    static let shared = ServiceContainer()
    
    private var services: [ObjectIdentifier: Any] = [:]
    private var singletons: [ObjectIdentifier: Any] = [:]
    
    private init() {}
    
    func register<T>(_ type: T.Type, factory: @escaping () -> T) {
        services[ObjectIdentifier(type)] = factory
    }
    
    func registerSingleton<T>(_ type: T.Type, factory: @escaping () -> T) {
        let id = ObjectIdentifier(type)
        if singletons[id] == nil {
            singletons[id] = factory()
        }
        services[id] = { [weak self] in
            return self?.singletons[id] as! T
        }
    }
    
    func resolve<T>(_ type: T.Type) -> T {
        let id = ObjectIdentifier(type)
        guard let factory = services[id] as? () -> T else {
            fatalError("Service \(type) not registered")
        }
        return factory()
    }
    
    func registerServices() {
        registerSingleton(ConfigurationManaging.self) { 
            UserDefaultsConfigManager() 
        }
        
        register(TextInputDetecting.self) { 
            AccessibilityTextInputDetector()
        }
        
        register(IndicatorRendering.self) { 
            CoreAnimationIndicatorRenderer()
        }
        
        register(CommandProcessing.self) { 
            CommandProcessor(
                configManager: self.resolve(ConfigurationManaging.self)
            )
        }
        
        register(CommunicationHandling.self) {
            StdinStdoutHandler(
                processor: self.resolve(CommandProcessing.self)
            )
        }
        
        register(HealthMonitoring.self) {
            HealthMonitor()
        }
    }
}