# TranscriptionIndicator Security Implementation Guide

## Overview

This guide provides step-by-step instructions for implementing the security enhancements identified in the comprehensive security audit. Follow these steps in order to ensure proper security hardening.

## Phase 1: Immediate Security Fixes (Priority: CRITICAL)

### 1.1 Replace Stdin/Stdout with XPC Service

**Why**: Direct stdin/stdout communication allows any process to inject commands. XPC provides secure inter-process communication with caller verification.

**Implementation Steps**:

1. Create XPC Service target in Xcode:
   ```bash
   # In Package.swift, add new target
   .target(
       name: "TranscriptionIndicatorXPC",
       dependencies: ["TranscriptionIndicator"],
       path: "Sources/XPCService"
   )
   ```

2. Configure Info.plist for XPC service:
   ```xml
   <key>MachServices</key>
   <dict>
       <key>com.transcription.indicator.xpc</key>
       <true/>
   </dict>
   <key>XPCService</key>
   <dict>
       <key>ServiceType</key>
       <string>Application</string>
       <key>RunLoopType</key>
       <string>dispatch_main</string>
   </dict>
   ```

3. Update main app to use XPC client:
   ```swift
   // Replace StdinStdoutHandler with:
   let xpcClient = TranscriptionIndicatorXPCClient()
   try await xpcClient.showIndicator(config: config)
   ```

4. Set up proper code signing:
   ```bash
   codesign --force --sign "Developer ID Application: Your Name" \
            --entitlements XPCService.entitlements \
            TranscriptionIndicatorXPC.xpc
   ```

### 1.2 Implement Enhanced Secure Field Detection

**Why**: Current implementation only checks subrole, which can miss secure fields.

**Implementation**:

1. Replace existing `isSecureField` method with the enhanced version from `SecurityEnhancements.swift`
2. Add comprehensive checks:
   - Subrole check
   - Password attribute check
   - Parent window context
   - Value pattern analysis
   - Security traits

3. Test with various password managers and secure input fields

### 1.3 Add Security Audit Logging

**Why**: No current tracking of what accessibility data is accessed.

**Implementation**:

1. Add audit logging to all AX API calls:
   ```swift
   private func logAccessibilityAccess(element: AXUIElement, attribute: CFString, success: Bool) {
       os_signpost(.event, log: auditLogger,
                   name: "AXAccess",
                   "app=%{public}@ attr=%{public}@ success=%{public}@",
                   appName, attribute as String, success ? "true" : "false")
   }
   ```

2. Configure log retention:
   ```swift
   // In Info.plist
   <key>OSLogPreferences</key>
   <dict>
       <key>com.transcription.indicator</key>
       <dict>
           <key>DEFAULT-OPTIONS</key>
           <dict>
               <key>Level</key>
               <string>Info</string>
               <key>Persist</key>
               <string>Default</string>
           </dict>
       </dict>
   </dict>
   ```

## Phase 2: Input Validation Hardening (Priority: HIGH)

### 2.1 Implement JSON Structure Validation

**Implementation**:

1. Add `validateJSONStructure` method before JSON decoding
2. Check for:
   - Maximum nesting depth (5 levels)
   - Total key count (50 max)
   - Array length limits (100 max)
   - Total message size (already implemented at 8KB)

### 2.2 Add Unicode Normalization

**Implementation**:

1. Normalize all string inputs:
   ```swift
   let normalized = input.precomposedStringWithCanonicalMapping
   ```

2. Check for dangerous Unicode characters:
   - Zero-width characters
   - Directional override characters
   - Control characters

### 2.3 Implement Message Authentication

**Implementation**:

1. Generate shared secret on first run:
   ```swift
   let secret = SymmetricKey(size: .bits256)
   // Store in Keychain
   ```

2. Add HMAC to all messages:
   ```swift
   let signature = HMAC<SHA256>.authenticationCode(for: messageData, using: secretKey)
   ```

3. Verify on receipt with timestamp validation

## Phase 3: Sandboxing and Entitlements (Priority: HIGH)

### 3.1 Update Entitlements

**Implementation**:

1. Remove unnecessary entitlements:
   ```xml
   <!-- Remove these -->
   <key>com.apple.security.network.client</key>
   <key>com.apple.security.files.user-selected.read-write</key>
   ```

2. Add required exceptions:
   ```xml
   <key>com.apple.security.temporary-exception.mach-lookup.global-name</key>
   <array>
       <string>com.apple.accessibility.AXBackingStore</string>
   </array>
   ```

### 3.2 Enable Hardened Runtime

**Implementation**:

1. In build settings:
   ```
   ENABLE_HARDENED_RUNTIME = YES
   ```

2. Disable dangerous runtime features:
   ```xml
   <key>com.apple.security.cs.disable-library-validation</key>
   <false/>
   <key>com.apple.security.cs.allow-jit</key>
   <false/>
   ```

## Phase 4: Memory Safety (Priority: MEDIUM)

### 4.1 Implement Layer Lifecycle Management

**Implementation**:

1. Track all created layers:
   ```swift
   private var activeLayers: Set<CALayer> = []
   ```

2. Implement cleanup on dealloc:
   ```swift
   deinit {
       activeLayers.forEach { layer in
           layer.removeAllAnimations()
           layer.removeFromSuperlayer()
       }
   }
   ```

### 4.2 Add Memory Pressure Handling

**Implementation**:

1. Monitor memory pressure:
   ```swift
   let source = DispatchSource.makeMemoryPressureSource(eventMask: [.warning, .critical])
   ```

2. Clear caches on pressure:
   ```swift
   source.setEventHandler {
       self.clearNonEssentialData()
   }
   ```

## Phase 5: Runtime Integrity (Priority: MEDIUM)

### 5.1 Implement Code Signature Verification

**Implementation**:

1. Verify on startup:
   ```swift
   func verifyCodeSignature() throws {
       let code = SecCodeSelf()
       // Verify against embedded requirements
   }
   ```

2. Check for debugger:
   ```swift
   func isDebuggerAttached() -> Bool {
       // Check P_TRACED flag
   }
   ```

## Testing and Validation

### Security Test Suite

Run all security tests:
```bash
swift test --filter SecurityEnhancementsTests
swift test --filter SecurityValidatorTests
```

### Manual Testing Checklist

- [ ] Test with various password managers
- [ ] Verify secure fields are always hidden
- [ ] Test XPC connection rejection for unsigned apps
- [ ] Verify rate limiting works
- [ ] Test with malformed JSON inputs
- [ ] Check memory usage under load
- [ ] Verify audit logs are generated

### Security Scanning

1. Run static analysis:
   ```bash
   xcrun swiftlint analyze --compiler-log-path build.log
   ```

2. Check dependencies:
   ```bash
   swift package audit
   ```

3. Scan for hardcoded secrets:
   ```bash
   gitleaks detect --source .
   ```

## Deployment Checklist

Before releasing:

- [ ] All Priority 1 fixes implemented
- [ ] Security tests pass
- [ ] Code signed with Developer ID
- [ ] Notarized by Apple
- [ ] Entitlements minimal and justified
- [ ] Audit logging enabled
- [ ] Rate limiting active
- [ ] XPC service properly sandboxed
- [ ] Privacy manifest included
- [ ] Security documentation updated

## Monitoring and Incident Response

### Log Monitoring

Monitor for:
- Failed authentication attempts
- Rate limit violations
- Unexpected accessibility access patterns
- Memory pressure events

### Security Updates

1. Subscribe to security advisories
2. Implement secure update mechanism
3. Plan for emergency patches
4. Document security contact info

## Conclusion

Following this implementation guide will significantly improve the security posture of TranscriptionIndicator. Prioritize Phase 1 fixes before any production deployment, then work through subsequent phases based on your threat model and deployment timeline.