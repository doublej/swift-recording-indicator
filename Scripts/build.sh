#!/bin/bash

# Build script for TranscriptionIndicator

set -e

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="$PROJECT_DIR/.build"
RELEASE_DIR="$PROJECT_DIR/release"

echo "TranscriptionIndicator Build Script"
echo "Project: $PROJECT_DIR"
echo ""

# Clean previous builds
echo "Cleaning previous builds..."
rm -rf "$BUILD_DIR"
rm -rf "$RELEASE_DIR"
mkdir -p "$RELEASE_DIR"

cd "$PROJECT_DIR"

# Build the project
echo "Building TranscriptionIndicator..."
swift build --configuration release

# Copy the executable
echo "Copying executable..."
cp "$BUILD_DIR/release/TranscriptionIndicator" "$RELEASE_DIR/"

# Create app bundle structure
echo "Creating app bundle..."
APP_BUNDLE="$RELEASE_DIR/TranscriptionIndicator.app"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

# Copy executable to bundle
cp "$RELEASE_DIR/TranscriptionIndicator" "$APP_BUNDLE/Contents/MacOS/"

# Copy Info.plist
cp "$PROJECT_DIR/Resources/Info.plist" "$APP_BUNDLE/Contents/"

# Create entitlements for signing
cp "$PROJECT_DIR/Resources/Entitlements.plist" "$RELEASE_DIR/"

# Copy scripts
echo "Copying scripts..."
cp -r "$PROJECT_DIR/Scripts" "$RELEASE_DIR/"

echo ""
echo "Build completed successfully!"
echo "Executable: $RELEASE_DIR/TranscriptionIndicator"
echo "App Bundle: $APP_BUNDLE"
echo "Scripts: $RELEASE_DIR/Scripts/"
echo ""

# Run basic tests if requested
if [[ "$1" == "--test" ]]; then
    echo "Running tests..."
    swift test
    echo "Tests completed!"
    echo ""
fi

# Check if we can sign the app
if command -v codesign &> /dev/null; then
    echo "Code signing information:"
    echo "Available identities:"
    security find-identity -v -p codesigning | head -5
    echo ""
    echo "To sign the app, run:"
    echo "  codesign --deep --force --verify --verbose --sign \"Developer ID Application: Your Name\" \"$APP_BUNDLE\""
    echo ""
else
    echo "Warning: codesign not available"
fi

echo "Build artifacts:"
ls -la "$RELEASE_DIR"