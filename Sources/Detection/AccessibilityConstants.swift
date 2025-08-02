import Foundation
import ApplicationServices

// Accessibility constants that might not be available in all SDK versions
extension String {
    static let axFocusedUIElement = "AXFocusedUIElement"
    static let axRole = "AXRole"
    static let axSubrole = "AXSubrole"
    static let axFrame = "AXFrame"
    static let axSelectedTextRange = "AXSelectedTextRange"
    static let axBoundsForRange = "AXBoundsForRange"
    
    // Roles
    static let axTextField = "AXTextField"
    static let axTextArea = "AXTextArea"
    static let axComboBox = "AXComboBox"
    static let axStaticText = "AXStaticText"
    
    // Subroles
    static let axSecureTextField = "AXSecureTextField"
}