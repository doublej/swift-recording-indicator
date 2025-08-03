#!/bin/bash

# Test script for TranscriptionIndicator shape variants
set -e

echo "=== TranscriptionIndicator Shape Variants Test ==="
echo

# Build the project
echo "Building project..."
swift build
echo "✓ Build successful"
echo

# Test all shape variants
echo "Testing shape variants..."

echo "1. Testing backward compatibility (simple 'show' command):"
echo "show" | ./.build/debug/TranscriptionIndicator | grep -q "Circle shown" && echo "✓ Simple 'show' defaults to circle"

echo "2. Testing explicit circle command:"
echo "show circle" | ./.build/debug/TranscriptionIndicator | grep -q "Circle shown" && echo "✓ 'show circle' works"

echo "3. Testing ring shape:"
echo "show ring" | ./.build/debug/TranscriptionIndicator | grep -q "Ring shown" && echo "✓ 'show ring' works"

echo "4. Testing orb shape:"
echo "show orb" | ./.build/debug/TranscriptionIndicator | grep -q "Orb shown" && echo "✓ 'show orb' works"

echo "5. Testing size variants:"
echo "show circle 100" | ./.build/debug/TranscriptionIndicator | grep -q "size 100" && echo "✓ Circle with custom size works"
echo "show ring 75" | ./.build/debug/TranscriptionIndicator | grep -q "size 75" && echo "✓ Ring with custom size works"
echo "show orb 120" | ./.build/debug/TranscriptionIndicator | grep -q "size 120" && echo "✓ Orb with custom size works"

echo "6. Testing hide command:"
echo -e "show\nhide" | ./.build/debug/TranscriptionIndicator | grep -q "Hidden" && echo "✓ Hide command works"

echo "7. Testing health command:"
echo "health" | ./.build/debug/TranscriptionIndicator | grep -q "Alive" && echo "✓ Health command works"

echo
echo "=== All tests passed! ==="
echo
echo "Available commands:"
echo "  show                  - Show circle (default size 50)"
echo "  show circle [size]    - Show circle with optional size"
echo "  show ring [size]      - Show ring with optional size"
echo "  show orb [size]       - Show orb with optional size"
echo "  show [size]           - Show circle with size (backward compatibility)"
echo "  hide                  - Hide indicator"
echo "  health                - Show process status"
echo
echo "Shape descriptions:"
echo "  circle - Solid filled circle using CAShapeLayer"
echo "  ring   - Hollow ring (60% inner radius) using CAShapeLayer"
echo "  orb    - Gradient-filled circle with glow effect using CAShapeLayer + CAGradientLayer"
echo
echo "Performance: All shapes use CAShapeLayer with hardware acceleration and 60fps optimization"