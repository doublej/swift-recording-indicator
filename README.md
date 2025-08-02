# TranscriptionIndicator

A high-performance macOS application that displays visual indicators anchored to text input carets system-wide. Built with modern Swift concurrency, Core Animation, and robust security practices.

## Features

- **System-wide text caret detection** using Accessibility APIs
- **Visual indicators** with customizable shapes, colors, and animations  
- **High-performance rendering** with Core Animation and Metal-ready architecture
- **Secure communication** via stdin/stdout JSON protocol with comprehensive input validation
- **Actor-based concurrency** for thread-safe operation
- **Memory and CPU monitoring** with automatic resource management
- **Comprehensive error handling** with structured logging
- **Accessibility-first design** with secure field detection and privacy protection

## Requirements

- macOS 12.0 or later
- Xcode 14.0 or later (for building)
- Swift 5.9 or later
- Accessibility permission (granted via System Preferences)

## Quick Start

### Building

```bash
# Clone and build
git clone <repository-url>
cd TranscriptionIndicator

# Build release version
./Scripts/build.sh

# Build and run tests
./Scripts/build.sh --test
```

### Basic Usage

```bash
# Check accessibility permissions
./release/TranscriptionIndicator --check-permissions

# Run the application
./release/TranscriptionIndicator

# Test with harness
./Tools/harness.sh ./release/TranscriptionIndicator
```

## Accessibility Permissions

TranscriptionIndicator requires accessibility permission to detect text input fields system-wide.

1. Open **System Preferences** → **Security & Privacy** → **Privacy** → **Accessibility**
2. Click the lock icon and enter your password
3. Click **+** and add TranscriptionIndicator
4. Ensure the checkbox is checked

> **Privacy Note**: TranscriptionIndicator only detects caret positions and never reads actual text content. Secure fields (password inputs) are automatically excluded based on policy settings.

## Communication Protocol

Commands are sent via stdin as newline-delimited JSON. Responses are returned via stdout.

### Command Format

```json
{
  "id": "unique-request-id",
  "v": 1,
  "command": "command-name",
  "config": { /* optional configuration */ }
}
```

### Basic Commands

**Show Indicator:**
```json
{"id":"1","v":1,"command":"show","config":{"shape":"circle","size":20,"colors":{"primary":"#FF0000"}}}
```

**Hide Indicator:**
```json
{"id":"2","v":1,"command":"hide"}
```

**Health Check:**
```json
{"id":"3","v":1,"command":"health"}
```

**Update Configuration:**
```json
{"id":"4","v":1,"command":"config","config":{"offset":{"x":10,"y":-10}}}
```

### Response Format

```json
{
  "id": "request-id",
  "status": "ok|error|alive",
  "message": "descriptive message",
  "timestamp": "2025-01-02T10:30:00Z",
  "pid": 12345,
  "code": "ERROR_CODE"
}
```

## Configuration

### Indicator Configuration

```json
{
  "v": 1,
  "mode": "caret|cursor",
  "visibility": "auto|forceOn|forceOff", 
  "shape": "circle|ring|orb|custom",
  "colors": {
    "primary": "#FF0000",
    "secondary": "#FF8888",
    "alphaPrimary": 1.0,
    "alphaSecondary": 0.7
  },
  "size": 20,
  "opacity": 0.9,
  "offset": {"x": 0, "y": -10},
  "screenEdgePadding": 8,
  "secureFieldPolicy": "hide|dim|allow",
  "animations": {
    "inDuration": 0.25,
    "outDuration": 0.18,
    "breathingCycle": 1.8
  },
  "health": {
    "interval": 30,
    "timeout": 75
  }
}
```

### Configuration Options

| Option | Type | Description |
|--------|------|-------------|
| `mode` | string | Detection mode: `caret` (accessibility) or `cursor` (mouse position) |
| `shape` | string | Visual shape: `circle`, `ring`, `orb`, or `custom` |
| `size` | number | Indicator size in pixels (10-50 recommended) |
| `opacity` | number | Transparency (0.0-1.0) |
| `offset` | object | Position offset from caret `{x, y}` |
| `secureFieldPolicy` | string | Behavior on password fields: `hide`, `dim`, or `allow` |

## Animation States

The indicator transitions through four states:

1. **Off** → **In** (spring scale + fade in)
2. **In** → **Idle** (breathing effect)  
3. **Idle** → **Out** (fade + scale out)
4. **Out** → **Off** (hidden)

Animation timing is fully configurable via the `animations` configuration object.

## Performance

### Optimizations

- **Event-driven architecture** - No polling, only responds to system notifications
- **Rate limiting** - Accessibility notifications throttled to ~60fps  
- **Memory efficient** - Automatic cleanup and resource management
- **Core Animation** - Hardware-accelerated rendering with minimal CPU usage
- **Actor isolation** - Thread-safe concurrency without locks

### Monitoring

Use the built-in performance monitoring:

```bash
# Enable verbose logging
VERBOSE=1 ./TranscriptionIndicator

# Performance statistics in logs
# Use Console.app with subsystem: com.transcription.indicator
```

Performance targets:
- Caret detection: < 4ms average
- Animation transitions: 60fps smooth
- Memory usage: < 50MB typical
- CPU usage: < 5% average

## Troubleshooting

### Indicator Not Visible

1. **Check accessibility permission**: `./TranscriptionIndicator --check-permissions`
2. **Try force visibility**: `{"command":"config","config":{"visibility":"forceOn"}}`
3. **Verify window level**: Ensure no screen recording software is interfering
4. **Check logs**: Use Console.app with subsystem filter

### Jittery Position

1. **Enable caret caching**: Default behavior includes position debouncing
2. **Check app compatibility**: Some apps provide unstable accessibility data
3. **Adjust throttling**: Increase `notificationThrottle` in detector if needed

### High CPU Usage

1. **Verify no display link**: Core Animation only, no custom refresh loops
2. **Check rate limiting**: Should be throttled to ~60fps maximum
3. **Monitor performance**: Use Instruments or built-in performance logging

### JSON Errors

1. **Validate format**: Ensure newline-delimited, valid UTF-8
2. **Include required fields**: `id`, `v`, `command` are mandatory
3. **Check limits**: Commands limited to 8KB, rate limited to 100/minute

### Secure Fields

If indicator appears on password fields:
```json
{"command":"config","config":{"secureFieldPolicy":"hide"}}
```

## Security

### Input Validation

- All JSON input is validated and size-limited
- Rate limiting prevents abuse (100 requests/minute)
- Comprehensive error handling with structured codes
- No arbitrary code execution or file system access

### Privacy Protection

- **No text reading**: Only caret positions are detected
- **Secure field detection**: Automatic hiding on password inputs
- **Minimal data**: No text content is ever stored or transmitted  
- **Local operation**: No network communication required

### Sandboxing

The application is designed for App Sandbox compatibility:

- Minimal entitlements (accessibility, user-selected files)
- No network access by default
- Restricted file system access
- Hardened runtime with library validation

## Development

### Project Structure

```
Sources/
├── TranscriptionIndicator/    # Main executable
├── Core/                     # Protocols, errors, utilities
├── Communication/            # stdin/stdout handling  
├── Detection/               # Accessibility integration
├── UI/                     # Windows, views, animations
├── Configuration/          # Settings management
└── Health/                # Monitoring and lifecycle

Tests/                      # Unit tests
Tools/                     # Test harness and utilities  
Scripts/                   # Build and deployment
Resources/                 # Info.plist, entitlements
```

### Building from Source

```bash
# Debug build
swift build

# Release build  
swift build --configuration release

# Run tests
swift test

# Generate Xcode project
swift package generate-xcodeproj
```

### Contributing

1. Follow Swift API Design Guidelines
2. Maintain test coverage above 80%
3. Use structured logging with privacy considerations
4. Validate all external input
5. Document security implications

## Code Signing and Distribution

### Development Signing

```bash
# Sign with development certificate
codesign --deep --force --verify --verbose \
  --sign "Apple Development: Your Name" \
  --entitlements Resources/Entitlements.plist \
  release/TranscriptionIndicator.app
```

### Distribution Signing

```bash
# Sign with Developer ID for distribution
codesign --deep --force --verify --verbose \
  --sign "Developer ID Application: Your Name" \
  --entitlements Resources/Entitlements.plist \
  release/TranscriptionIndicator.app

# Notarize (requires Apple Developer account)
xcrun notarytool submit release/TranscriptionIndicator.app.zip \
  --keychain-profile "notary-profile" --wait

# Staple notarization
xcrun stapler staple release/TranscriptionIndicator.app
```

## License

[Add your license here]

## Support

For issues and questions:

1. Check this README and troubleshooting section
2. Review system requirements and accessibility permissions  
3. Check Console.app logs with subsystem filter: `com.transcription.indicator`
4. File detailed issue reports with system information and logs

---

**Version**: 1.0.0  
**Compatibility**: macOS 12.0+  
**Architecture**: Universal (Intel + Apple Silicon)