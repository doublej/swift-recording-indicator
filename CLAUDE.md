# TranscriptionIndicator - Swift macOS Application Plan (Updated)

This document replaces the earlier draft. It integrates caret anchoring via Accessibility, a Core Animation first approach, robust stdin/stdout lifecycle handling, and a complete README scope.

---

## 1. Architecture Overview

**Application type**: Background macOS app driven over stdin/stdout with a visual overlay  
**Frameworks**: AppKit + Core Animation (SwiftUI optional for settings UI later)  
**Communication**: Newline-delimited JSON over stdin/stdout (UTF-8)  
**Deployment**: LSUIElement app bundle for proper TCC identity, codesigning, and notarization. Still runnable from a parent process via stdin.  
**Compatibility**: macOS 12 and newer  
**Security**: Sandbox compatible. Uses macOS Accessibility entitlement by user consent.  
**Goal**: Show a subtle indicator anchored to the text caret while text input is active, with fallbacks.

---

## 2. Core Components

### 2.1 Communication System
- **StdinReader**: DispatchIO based, line oriented, UTF-8, handles partial frames, detects EOF.
- **StdoutWriter**: Serial queue, bounded buffer to avoid blocking parent, JSON encoding with newline framing.
- **CommandProcessor**: Validates schema version, correlates responses using `id`, routes to subsystems, provides structured errors.
- **Protocol**: Requests and responses include `id` and `v` (schema version).
- **Lifecycle**:
  - On stdin EOF: auto hide, then terminate.
  - On idle timeout: auto hide. Exit only if `exitOnIdle` is true.

### 2.2 Text Input Detection
- **Primary**: Accessibility observer using `AXObserver` for system wide focus changes and selected text changes.
  - Notifications: `kAXFocusedUIElementChangedNotification`, and when available on focused element `kAXSelectedTextChangedNotification`.
  - Caret rectangle detection:
    - Prefer `kAXSelectedTextRange` with `kAXBoundsForRangeParameterizedAttribute`.
    - Fallback to element frame (`kAXFrame`) with heuristics.
    - Skip secure fields.
- **Secondary fallback**: Cursor location via Quartz events when caret is unavailable.
- **Field editor heuristic**: `NSApplication.shared.keyWindow?.firstResponder is NSTextView` is advisory only, not sole source.
- **Performance**: Event driven. No polling. Cache last good anchor rect to reduce churn on rapid notifications.
- **Permissions**: Detect missing Accessibility access. Provide guided prompt to open System Settings at the correct pane.

### 2.3 Visual Indicator System
- **Window**: Non-activating `NSPanel`, borderless, transparent, click-through.
  - `level = .statusBar`
  - `collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]`
  - `ignoresMouseEvents = true`, `isOpaque = false`, `hasShadow = false`
- **Rendering**: Core Animation first.
  - Shapes: circle, ring, orb via `CAShapeLayer`, pulse ring via `CAReplicatorLayer`.
  - Optional effects: Core Image for glow. Metal reserved for future custom shaders if needed.
- **Positioning**: Anchored to caret rect when available, else to cursor. Configurable offset and `screenEdgePadding`.

### 2.4 Animation States and Transitions
- **States**: Off → In → Idle → Out → Off
- **In**: Spring scale and fade in.
- **Idle**: Breathing effect at stable 60 fps using CA, not a custom display link.
- **Out**: Ease out fade and scale.
- **Coalescing rules**:
  - `show` during `In`: continue to `Idle`, ignore duplicate.
  - `show` during `Idle`: update config live without jank.
  - `hide` during `In` or `Idle`: transition to `Out` immediately.
- **Timing**: Configurable durations with defaults.

### 2.5 Configuration System
- **Format**: JSON with schema version `v = 1`.
- **Validation**: Types, ranges, color parsing, optional fields with defaults.
- **Persistence**: UserDefaults for user facing visuals (shape, colors, size, opacity, offsets, mode, secure field policy). Transient runtime state (visibility, last anchor) not persisted.
- **Hot reload**: Apply updates immediately. Disable implicit animations during live property changes to avoid visual snap.

### 2.6 Health and Lifecycle
- **Health command**: Respond immediately with `status`, `timestamp`, `pid`, `v`.
- **Keepalive**: If configured `health.timeout` elapses with no commands or health pings, auto hide only. Do not exit unless stdin is closed or `exitOnIdle` is true.
- **Recovery**: On parent death detected by EOF: hide then exit gracefully.

### 2.7 Packaging and Distribution
- **Bundle**: LSUIElement set to avoid Dock and Cmd+Tab.
- **Codesigning**: Developer ID Application.  
- **Notarization**: Stapled for distribution.  
- **App Store**: Not targeted due to global overlay and AX reliance.

---

## 3. File Structure

TranscriptionIndicator/
├── README.md                         # Build, usage, protocol, permissions, troubleshooting
├── Package.swift                     # Swift Package Manager
├── Sources/
│   ├── App.swift                     # Main entry point
│   ├── Communication/
│   │   ├── StdinHandler.swift        # DispatchIO line reader, EOF handling
│   │   ├── StdoutWriter.swift        # Structured responses with correlation ids
│   │   └── Commands.swift            # Command routing, schema versioning, error codes
│   ├── Detection/
│   │   ├── TextInputDetector.swift   # AXObserver, caret rect extraction, caching
│   │   └── AccessibilityHelper.swift # Permission checks, attribute helpers
│   ├── UI/
│   │   ├── IndicatorWindow.swift     # Non-activating NSPanel
│   │   ├── AnimationController.swift # State machine and CA animations
│   │   └── ShapeLayers.swift         # CAShapeLayer builders, glow CI pipeline
│   ├── Configuration/
│   │   └── Config.swift              # Codable config, validation, persistence
│   └── Health/
│       └── HealthMonitor.swift       # Keepalive timers and status
├── Resources/
│   └── Shaders/                      # Optional Metal shaders for future effects
├── Tools/
│   └── harness.sh                    # Test harness to send JSON lines to the app
└── Scripts/
├── codesign_notarize.sh          # Distribution helper
└── ci_headless_tests.sh          # CI-friendly tests with mocked AX

---

## 4. Communication Protocol

**Transport**: Newline-delimited JSON. Each message on a single line. UTF-8.  
**Common fields**: `id` (string), `v` (int, current 1), `command` (string).

### 4.1 Commands

```json
{"id":"1","v":1,"command":"show","config":{"shape":"circle","colors":{"primary":"#FF0000"},"size":20}}

{"id":"2","v":1,"command":"hide"}

{"id":"3","v":1,"command":"health"}

{"id":"4","v":1,"command":"config","config":{"offset":{"x":10,"y":-10}}}

4.2 Responses

{"id":"1","status":"ok","message":"Indicator shown"}

{"id":"3","status":"alive","timestamp":"2025-01-02T10:30:00Z","pid":12345,"v":1}

{"id":"4","status":"error","code":"INVALID_CONFIG","message":"offset.y must be a number"}

Error codes: INVALID_COMMAND, INVALID_CONFIG, UNSUPPORTED_VERSION, PERMISSION_DENIED, INTERNAL_ERROR.

Versioning: If v is missing or unsupported, respond with UNSUPPORTED_VERSION and provide supported:[1].

⸻

5. Text Input Detection Strategy

5.1 Primary: Accessibility observer with caret anchoring
  • Register a single AXObserver on the system element.
  • On focus change: resolve focused UI element, determine if text-like and not secure.
  • Caret rectangle resolution strategy:
  1.  If element supports kAXSelectedTextRange and kAXBoundsForRangeParameterizedAttribute, compute bounds for the current selection start.
  2.  Else use kAXInsertionPointLineNumber where available with line metrics if exposed.
  3.  Else fall back to the element frame plus offset heuristic.
  • Cache last valid caret rect and timestamp. Throttle updates to avoid overdraw.

5.2 Fallback: Cursor anchoring
  • Use NSEvent.mouseLocation transformed to screen coordinates.
  • Apply screenEdgePadding and configured offset.

5.3 Advisory: Field editor pattern

For AppKit apps where available:

let isTextInputActive = NSApplication.shared.keyWindow?.firstResponder is NSTextView

Use as a hint only.

⸻

6. Visuals and Animations

6.1 Window configuration

let panel = NSPanel(contentRect: .zero,
                    styleMask: [.borderless, .nonactivatingPanel],
                    backing: .buffered,
                    defer: false)
panel.level = .statusBar
panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
panel.ignoresMouseEvents = true
panel.isOpaque = false
panel.hasShadow = false
panel.backgroundColor = .clear

6.2 Core Animation implementations
  • Breathing effect:

let breathing = CAKeyframeAnimation(keyPath: "transform.scale")
breathing.values = [1.0, 1.2, 1.0]
breathing.keyTimes = [0, 0.5, 1.0]
breathing.duration = 2.0
breathing.repeatCount = .infinity

  • Spring appear:

let spring = CASpringAnimation(keyPath: "transform.scale")
spring.fromValue = 0.8
spring.toValue = 1.0
spring.damping = 10
spring.initialVelocity = 5
spring.mass = 1
spring.stiffness = 150
spring.duration = spring.settlingDuration

  • Pulse ring: Shape layer duplicated via CAReplicatorLayer with staggered opacity and scale.

6.3 Optional effects
  • Glow: Core Image bloom on a rasterized circle layer.
  • Metal: Reserved for future shaders such as distance field glow. Not required for v1.

⸻

7. Configuration Schema (v1)

{
  "v": 1,
  "mode": "caret | cursor",
  "visibility": "auto | forceOn | forceOff",
  "shape": "circle | ring | orb | custom",
  "colors": {
    "primary": "#FF0000",
    "secondary": "#FF8888",
    "alphaPrimary": 1.0,
    "alphaSecondary": 0.7,
    "colorSpace": "sRGB"
  },
  "size": 20,
  "opacity": 0.9,
  "offset": { "x": 0, "y": -10 },
  "screenEdgePadding": 8,
  "secureFieldPolicy": "hide | dim | allow",
  "animations": {
    "inDuration": 0.25,
    "outDuration": 0.18,
    "breathingCycle": 1.8,
    "timing": "easeInOut"
  },
  "health": {
    "interval": 30,
    "timeout": 75
  },
  "exitOnIdle": false
}

Validation rules:
  • size > 0, 0 <= opacity <= 1, alpha* in [0,1].
  • Colors parsed as hex with or without alpha. Default color space sRGB.
  • screenEdgePadding >= 0.

⸻

8. Performance Optimizations
  • Event driven AX observer only. No periodic polling.
  • Use CA implicit animations where possible. Avoid continuous CADisplayLink.
  • Prebuild and reuse layers per shape. Toggle visibility instead of recreating.
  • Cache last anchor rect and only reposition when rect or screen changes.
  • Avoid layout on every AX event; coalesce updates on a short debounce (~16 ms).
  • Use os_signpost for timing of event handling and animation transitions.

⸻

9. Error Handling
  • Structured errors with codes and messages.
  • Invalid commands: do not crash. Log to unified logging with privacy markers.
  • Permission denial: respond PERMISSION_DENIED and provide an action hint.
  • AX failures: degrade to cursor mode automatically if mode is caret and fallback allowed.
  • On communication failure or EOF: auto hide, flush logs, exit.

⸻

10. Testing Strategy
  • Unit tests: Config parsing, validation, command routing, response correlation.
  • Integration tests: Harness that sends JSON lines and asserts responses and state transitions.
  • AX mocking: Headless test shim that simulates focus and selection changes.
  • Performance: Measure time from AX event to reposition complete. Target under 4 ms on average hardware.
  • Memory: Leak checks during long idle cycles.
  • Permission flows: Fresh user on a clean VM to validate TCC prompts and guidance.

⸻

11. README.md Scope and Outline

The repository includes a comprehensive README. Minimum sections:
  1.  Overview and supported macOS versions.
  2.  Requirements: Xcode, Swift toolchain, SDKs.
  3.  Build and run with SwiftPM.
  4.  Granting Accessibility permission with screenshots and steps.
  5.  Usage over stdin/stdout with copy paste commands.
  6.  JSON protocol and schema with defaults.
  7.  Animation states and visuals with short clips or GIFs.
  8.  Troubleshooting: overlay not visible, high CPU, JSON errors, permissions.
  9.  Performance guidance.
  10. Testing instructions.
  11. Versioning and changelog.
  12. License and contribution guidelines.

⸻

12. Implementation Steps
  1.  Project skeleton: SwiftPM package inside LSUIElement app bundle. Add targets and minimal AppDelegate.
  2.  Communication: Implement DispatchIO line reader with EOF detection. Add writer and correlation ids.
  3.  Window: Create non-activating panel visible across Spaces and full screen. Draw a static circle via CAShapeLayer.
  4.  Animations: Implement In, Idle breathing, Out using CA.
  5.  AX Detection: Build AXObserver plumbing. Resolve caret rect. Implement secure field policy.
  6.  Positioning: Anchor to caret, apply offsets and edge padding. Fallback to cursor when needed.
  7.  Config system: Codable types, validation, defaults, persistence. Apply with implicit animations disabled where appropriate.
  8.  Health: Implement health reply with pid and timestamp. Idle timeout hides only.
  9.  Errors and logging: Error codes, unified logging, developer diagnostics.
  10. README v1: Include build, permission, CLI usage, protocol, troubleshooting.
  11. Tools: Provide harness.sh for local testing.
  12. CI headless tests: Mock AX events and run protocol tests.
  13. Packaging: Codesign and notarize scripts. Smoke test on a clean machine.

⸻

13. Communication Examples

Show indicator

{"id":"s1","v":1,"command":"show","config":{"mode":"caret","visibility":"auto","shape":"ring","colors":{"primary":"#00E0FF","secondary":"#0080FF80"},"size":18,"opacity":0.9,"offset":{"x":0,"y":-12},"screenEdgePadding":8,"secureFieldPolicy":"hide","animations":{"inDuration":0.25,"outDuration":0.18,"breathingCycle":1.8},"health":{"interval":30,"timeout":75},"exitOnIdle":false}}

Update configuration

{"id":"c7","v":1,"command":"config","config":{"offset":{"x":10,"y":-10}}}

Hide indicator

{"id":"h1","v":1,"command":"hide"}

Health check

{"id":"hc1","v":1,"command":"health"}

Typical responses

{"id":"s1","status":"ok","message":"Indicator shown"}
{"id":"hc1","status":"alive","timestamp":"2025-08-02T09:30:00Z","pid":12345,"v":1}
{"id":"c7","status":"error","code":"INVALID_CONFIG","message":"offset.y must be a number"}


⸻

  . Troubleshooting Quick Reference
  • Overlay not visible: Check Accessibility permission. Try visibility:"forceOn". Verify window level not overshadowed by screen recording overlays.
  • Jittery position: Enable caret caching and debounce. Verify AX provides stable rects in the target app.
  • High CPU: Ensure no display link is active. CA animations only.
  • JSON errors: Ensure newline delimited messages, valid UTF-8, include id and v.
  • Secure fields: If the indicator appears on password fields, set secureFieldPolicy:"hide".

⸻

  . Notes on Future Work
  • Optional Metal shaders for advanced glow with distance fields.
  • Named pipe or UNIX domain socket transport for high volume integrations.
  • SwiftUI preferences panel for non-technical users.

⸻

## Agent Assignments and Implementation Guidance

The following specialized agents have been assigned to this project with comprehensive recommendations:

### 1. Legacy Modernizer Agent
**Focus**: Swift and macOS modernization
**Key Recommendations**:
- Migrate to Swift Concurrency (async/await, actors) replacing DispatchIO callbacks
- Implement Observable Framework for state management on macOS 14+
- Use Swift Testing framework with structured assertions
- Leverage Swift 5.9+ features (parameter packs, macros, if/switch expressions)
- Protocol-oriented design for better testability and modularity
- Actor-based thread safety with @MainActor coordination
- Modern error handling with structured LocalizedError types

### 2. Backend Architect Agent
**Focus**: Application architecture and maintainability
**Key Recommendations**:
- Service container pattern for dependency injection and testability
- Protocol-based module boundaries with clear separation of concerns
- Actor-based concurrency architecture for thread-safe state management
- Result-based error handling for critical paths with recovery patterns
- Performance monitoring integration using os_signpost
- Memory-efficient Core Animation with resource cleanup
- Structured package organization following Swift best practices

### 3. macOS Developer Agent
**Focus**: macOS-specific optimizations and system integration
**Key Recommendations**:
- LSUIElement lifecycle management with proper activation policies
- Optimized NSPanel configuration for overlay windows (level: .screenSaver - 1)
- Robust AXObserver implementation with rate limiting and background processing
- Multi-display and Space change handling with proper notifications
- Core Animation performance tuning with layer-backed views and precise timing
- TCC compliance with proper Info.plist and entitlements configuration
- Cross-space and full-screen compatibility with advanced window behaviors

### 4. Security Auditor Agent
**Focus**: Security hardening and compliance
**Critical Security Issues Identified**:
- Privilege escalation risk from direct stdin/stdout communication
- JSON injection vulnerabilities requiring input validation
- Accessibility API abuse potential for data harvesting
- Insufficient sandboxing and missing entitlements
- Window spoofing risks at StatusBar level

**Priority Security Measures**:
1. Implement XPC Service architecture for privilege separation
2. Enable App Sandbox with minimal required entitlements
3. Add comprehensive input validation with size limits and rate limiting
4. Implement secure field detection with multiple validation checks
5. Use Hardened Runtime with library validation
6. Create security audit trails for Accessibility API usage
7. Add privacy controls with consent UI and automatic data purging

### Implementation Priority Matrix

**Phase 1 (Foundation)**:
1. Project skeleton with Swift Package Manager structure
2. Security hardening (sandbox, entitlements, input validation)
3. Actor-based communication system with async/await
4. Basic window management with proper macOS integration

**Phase 2 (Core Features)**:
1. Accessibility observer with robust error handling
2. Core Animation system with performance optimization
3. Configuration management with validation and persistence
4. Health monitoring with proper lifecycle management

**Phase 3 (Polish & Production)**:
1. Comprehensive testing with mocked Accessibility APIs
2. Performance monitoring and memory management
3. Codesigning and notarization scripts
4. Documentation and troubleshooting guides

### Architectural Patterns to Implement

**Service Container Pattern**:
```swift
@MainActor
final class ServiceContainer {
    func register<T>(_ type: T.Type, factory: @escaping () -> T)
    func resolve<T>(_ type: T.Type) -> T
}
```

**Actor-Based State Management**:
```swift
actor TextInputDetector: TextInputDetecting {
    let caretRectPublisher: AsyncStream<CGRect?>
    func startDetection() async throws
}

@MainActor
class AppCoordinator: ObservableObject {
    @Published private(set) var isActive = false
    @Published private(set) var currentConfig: IndicatorConfig?
}
```

**Security-First Design**:
```swift
enum TranscriptionIndicatorError: LocalizedError, Codable {
    case invalidCommand(String)
    case permissionDenied(permission: String)
    case invalidConfig(field: String, reason: String)
}
```

### Testing Strategy Integration

**Unit Testing with Swift Testing**:
- Protocol-based mocking for all system integrations
- Actor isolation testing for concurrency safety
- Configuration validation testing with invalid inputs
- Performance testing with signpost measurements

**Integration Testing**:
- Harness-based JSON protocol testing
- Mocked Accessibility API event simulation
- Animation state transition verification
- Cross-space and multi-display scenarios

**Security Testing**:
- Input validation fuzzing
- Permission boundary testing
- Memory safety verification
- Privilege escalation prevention

This comprehensive agent assignment ensures the TranscriptionIndicator will be built as a modern, secure, and performant Swift macOS application following current best practices across architecture, security, and platform-specific optimization.

