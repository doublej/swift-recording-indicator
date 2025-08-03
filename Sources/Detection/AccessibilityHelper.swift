import Foundation
import ApplicationServices
import Logging

final class AccessibilityHelper {
    private static let logger = Logger(label: "accessibility.helper")
    
    static func checkPermissions() -> Bool {
        return AXIsProcessTrusted()
    }
    
    static func requestPermissions() -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }
    
    static func getSystemWideElement() -> AXUIElement {
        return AXUIElementCreateSystemWide()
    }
    
    static func getFocusedElement() async -> AXUIElement? {
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInteractive).async {
                let systemElement = getSystemWideElement()
                var focusedElement: CFTypeRef?
                
                let result = AXUIElementCopyAttributeValue(
                    systemElement,
                    String.axFocusedUIElement as CFString,
                    &focusedElement
                )
                
                if result == .success, let element = focusedElement {
                    continuation.resume(returning: (element as! AXUIElement))
                } else {
                    logger.debug("Failed to get focused element: \(result.rawValue)")
                    continuation.resume(returning: nil)
                }
            }
        }
    }
    
    static func getElementRole(_ element: AXUIElement) async -> String? {
        return await getStringAttribute(element, String.axRole as CFString)
    }
    
    static func getElementSubrole(_ element: AXUIElement) async -> String? {
        return await getStringAttribute(element, String.axSubrole as CFString)
    }
    
    static func getElementFrame(_ element: AXUIElement) async -> CGRect? {
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInteractive).async {
                var value: CFTypeRef?
                let result = AXUIElementCopyAttributeValue(element, String.axFrame as CFString, &value)
                
                guard result == .success,
                      let axValue = value,
                      CFGetTypeID(axValue) == AXValueGetTypeID() else {
                    continuation.resume(returning: nil)
                    return
                }
                
                var rect = CGRect.zero
                guard AXValueGetValue(axValue as! AXValue, .cgRect, &rect) else {
                    continuation.resume(returning: nil)
                    return
                }
                
                continuation.resume(returning: rect)
            }
        }
    }
    
    static func getSelectedTextRange(_ element: AXUIElement) async -> CFRange? {
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInteractive).async {
                var value: CFTypeRef?
                let result = AXUIElementCopyAttributeValue(element, String.axSelectedTextRange as CFString, &value)
                
                guard result == .success,
                      let axValue = value,
                      CFGetTypeID(axValue) == AXValueGetTypeID() else {
                    continuation.resume(returning: nil)
                    return
                }
                
                var range = CFRange()
                guard AXValueGetValue(axValue as! AXValue, .cfRange, &range) else {
                    continuation.resume(returning: nil)
                    return
                }
                
                continuation.resume(returning: range)
            }
        }
    }
    
    static func getBoundsForRange(_ element: AXUIElement, range: CFTypeRef) async -> CGRect? {
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInteractive).async {
                var bounds: CFTypeRef?
                let result = AXUIElementCopyParameterizedAttributeValue(
                    element,
                    String.axBoundsForRange as CFString,
                    range,
                    &bounds
                )
                
                guard result == .success,
                      let axValue = bounds,
                      CFGetTypeID(axValue) == AXValueGetTypeID() else {
                    continuation.resume(returning: nil)
                    return
                }
                
                var rect = CGRect.zero
                guard AXValueGetValue(axValue as! AXValue, .cgRect, &rect) else {
                    continuation.resume(returning: nil)
                    return
                }
                
                continuation.resume(returning: rect)
            }
        }
    }
    
    static func isElementSecure(_ element: AXUIElement) async -> Bool {
        guard let subrole = await getElementSubrole(element) else {
            return false
        }
        
        return subrole == String.axSecureTextField
    }
    
    static func isElementTextInput(_ element: AXUIElement) async -> Bool {
        guard let role = await getElementRole(element) else {
            return false
        }
        
        let textRoles = [
            String.axTextField,
            String.axTextArea,
            String.axComboBox,
            String.axStaticText
        ]
        
        return textRoles.contains(role)
    }
    
    private static func getStringAttribute(_ element: AXUIElement, _ attribute: CFString) async -> String? {
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInteractive).async {
                var value: CFTypeRef?
                let result = AXUIElementCopyAttributeValue(element, attribute, &value)
                
                if result == .success, let stringValue = value as? String {
                    continuation.resume(returning: stringValue)
                } else {
                    continuation.resume(returning: nil)
                }
            }
        }
    }
    
    static func debugElementInfo(_ element: AXUIElement) async -> [String: Any] {
        var info: [String: Any] = [:]
        
        if let role = await getElementRole(element) {
            info["role"] = role
        }
        
        if let subrole = await getElementSubrole(element) {
            info["subrole"] = subrole
        }
        
        if let frame = await getElementFrame(element) {
            info["frame"] = NSStringFromRect(frame)
        }
        
        if let range = await getSelectedTextRange(element) {
            info["selectedRange"] = "location: \(range.location), length: \(range.length)"
        }
        
        info["isTextInput"] = await isElementTextInput(element)
        info["isSecure"] = await isElementSecure(element)
        
        return info
    }
}