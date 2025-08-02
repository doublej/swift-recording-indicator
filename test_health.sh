#!/bin/bash

# Simple health check test for TranscriptionIndicator
# This script demonstrates the health check functionality

APP_PATH="./.build/arm64-apple-macosx/debug/TranscriptionIndicator"

echo "Testing TranscriptionIndicator Health Check"
echo "=========================================="
echo

if [[ ! -f "$APP_PATH" ]]; then
    echo "Error: App binary not found. Building..."
    swift build > /dev/null 2>&1
    if [[ $? -ne 0 ]]; then
        echo "Build failed!"
        exit 1
    fi
fi

echo "Sending health check command..."
echo 'Command: {"id":"test1","v":1,"command":"health"}'
echo

# Create a background process that will terminate the app after a short delay
(
    sleep 2
    pkill -f TranscriptionIndicator > /dev/null 2>&1
) &

# Send health command and capture output
echo '{"id":"test1","v":1,"command":"health"}' | $APP_PATH 2>&1 | head -20

echo
echo "Test completed. Note: App requires Accessibility permissions for full functionality."