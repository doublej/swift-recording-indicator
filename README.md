# TranscriptionIndicator

A lightweight macOS application that displays customizable visual indicators on screen. Perfect for showing recording status, transcription state, or any other visual feedback needs.

## Features

- **Multiple Shapes**: Circle, square, and triangle indicators
- **Customizable Colors**: Named colors (red, blue, green, etc.) and hex codes (#FF0000)
- **Variable Sizes**: Adjustable size from 10-200 pixels
- **Countdown Timer**: Auto-close after specified duration
- **Keepalive System**: Send periodic signals to prevent auto-close
- **Single Instance**: Automatically prevents multiple instances from running
- **Cross-platform Integration**: Python client library for easy integration
- **Lightweight**: Minimal resource usage with simple, reliable architecture

## Quick Start

### Build the Application

```bash
Scripts/build.sh
```

### Basic Usage

```bash
# Show a red circle
echo "show" | release/TranscriptionIndicator

# Show with 10-second countdown (auto-close)
echo "show 10" | release/TranscriptionIndicator

# Hide the indicator
echo "hide" | release/TranscriptionIndicator

# Set shape, color, and size
echo "shape square" | release/TranscriptionIndicator
echo "color blue" | release/TranscriptionIndicator
echo "size 80" | release/TranscriptionIndicator

# Set countdown timer
echo "countdown 30" | release/TranscriptionIndicator

# Send keepalive signal (resets countdown)
echo "keepalive" | release/TranscriptionIndicator
```

### Python Integration

```python
from Scripts.transcription_indicator import TranscriptionIndicator

# Initialize the client
indicator = TranscriptionIndicator()

# Configure and show indicator with 30-second countdown
indicator.configure_and_show(shape="circle", color="red", size=60, duration=30)

# Send keepalive to reset countdown
indicator.send_keepalive()

# Hide when done
indicator.hide()
```

### Run the Demo

```bash
python3 Scripts/demo.py
```

## Commands

| Command | Description | Example |
|---------|-------------|---------|
| `show [seconds]` | Display the indicator (with optional countdown) | `echo "show 30" \| release/TranscriptionIndicator` |
| `hide` | Hide the indicator | `echo "hide" \| release/TranscriptionIndicator` |
| `shape <type>` | Set shape (circle, square, triangle) | `echo "shape triangle" \| release/TranscriptionIndicator` |
| `color <value>` | Set color (name or hex) | `echo "color #FF00FF" \| release/TranscriptionIndicator` |
| `size <pixels>` | Set size (10-200 pixels) | `echo "size 100" \| release/TranscriptionIndicator` |
| `countdown <seconds>` | Set auto-close countdown (1-3600s) | `echo "countdown 60" \| release/TranscriptionIndicator` |
| `keepalive` | Reset countdown timer | `echo "keepalive" \| release/TranscriptionIndicator` |

### Available Colors

**Named Colors**: red, green, blue, yellow, orange, purple, white, black, cyan, magenta

**Hex Colors**: Any standard 6-digit hex color (e.g., `#FF0000`, `#00FF00`, `#0000FF`)

## Project Structure

```
TranscriptionIndicator/
├── Sources/                    # Swift source code
│   ├── TranscriptionIndicator/ # Main application
│   ├── Communication/          # Command processing
│   └── Core/                   # Core functionality
├── Scripts/                    # Build and integration scripts
│   ├── transcription_indicator.py  # Python client library
│   ├── demo.py                 # Enhanced demonstration
│   ├── build.sh                # Build script
│   ├── test.sh                 # Test runner
│   └── examples/               # Integration examples
├── Tests/                      # Unit tests
└── release/                    # Built application
```

## Architecture

The application follows a simplified, reliable architecture:

- **Single Instance Manager**: Prevents multiple app instances using file locking
- **Command Processor**: Handles shape, color, size, show/hide commands
- **Simple UI**: Direct NSWindow/NSView manipulation for maximum compatibility
- **Shell Integration**: Works seamlessly with shell commands and Python scripts

## Development

### Build Requirements

- macOS 12.0+
- Swift 5.9+
- Xcode command line tools

### Building

```bash
# Build release version
Scripts/build.sh

# Build and run tests
Scripts/build.sh --test

# Run tests only
swift test
```

### Testing

```bash
# Run Swift unit tests
swift test

# Run integration tests
Scripts/test.sh

# Run Python demo
python3 Scripts/demo.py
```

## Integration Examples

### Basic Python Integration

```python
from Scripts.transcription_indicator import TranscriptionIndicator

class MyApp:
    def __init__(self):
        self.indicator = TranscriptionIndicator()
    
    def start_recording(self):
        self.indicator.set_color("red")
        self.indicator.set_shape("circle")
        self.indicator.show()
    
    def stop_recording(self):
        self.indicator.hide()
```

### Shell Script Integration

```bash
#!/bin/bash
INDICATOR="release/TranscriptionIndicator"

# Start recording indication
echo "color red" | $INDICATOR
echo "shape circle" | $INDICATOR
echo "show" | $INDICATOR

# Your recording logic here
sleep 5

# Stop indication
echo "hide" | $INDICATOR
```

## Configuration

The application requires no configuration files. All settings are applied via commands and persist until the application exits.

### Entitlements

The app includes proper sandboxing and security entitlements. No special permissions are required beyond standard app execution.

## Troubleshooting

### Common Issues

1. **App not found**: Run `Scripts/build.sh` to build the application
2. **No visual indicator**: Ensure the app has appropriate permissions and try different colors/sizes
3. **Multiple instances**: The single instance system prevents this automatically
4. **Python import errors**: Ensure you're running from the project root directory

### Debug Mode

```bash
# Run with verbose output
echo "show" | release/TranscriptionIndicator 2>&1

# Check if app is running
ps aux | grep TranscriptionIndicator
```

## License

This project is provided as-is for educational and development purposes.

## Contributing

1. Follow Swift Package Manager conventions
2. Maintain the simplified architecture
3. Add tests for new functionality
4. Update documentation for API changes

## Changelog

### Current Version
- Added shape, color, and size commands
- Improved Python client library
- Enhanced single instance management
- Consolidated script organization
- Added comprehensive documentation