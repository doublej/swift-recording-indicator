#!/bin/bash

# TranscriptionIndicator Test Harness
# Sends JSON commands to the app and displays responses

set -e

APP_PATH="${1:-./TranscriptionIndicator}"
VERBOSE="${VERBOSE:-0}"

if [[ ! -f "$APP_PATH" ]]; then
    echo "Error: App not found at $APP_PATH"
    echo "Usage: $0 [path-to-app]"
    echo "       VERBOSE=1 $0 [path-to-app]"
    exit 1
fi

echo "TranscriptionIndicator Test Harness"
echo "App: $APP_PATH"
echo "Use Ctrl+C to exit"
echo ""

# Create a named pipe for bidirectional communication
PIPE_DIR=$(mktemp -d)
REQUEST_PIPE="$PIPE_DIR/requests"
RESPONSE_PIPE="$PIPE_DIR/responses"

mkfifo "$REQUEST_PIPE"
mkfifo "$RESPONSE_PIPE"

cleanup() {
    echo ""
    echo "Cleaning up..."
    
    if [[ -n "$APP_PID" ]]; then
        kill "$APP_PID" 2>/dev/null || true
    fi
    
    rm -rf "$PIPE_DIR"
    exit 0
}

trap cleanup INT TERM

# Start the app
echo "Starting TranscriptionIndicator..."
"$APP_PATH" < "$REQUEST_PIPE" > "$RESPONSE_PIPE" &
APP_PID=$!

# Monitor responses in background
(
    while read -r response; do
        if [[ "$VERBOSE" == "1" ]]; then
            echo "← $response" | jq . 2>/dev/null || echo "← $response"
        else
            echo "$response" | jq -r '.status // "unknown"' 2>/dev/null || echo "Response: $response"
        fi
    done < "$RESPONSE_PIPE"
) &
RESPONSE_PID=$!

# Helper function to send JSON command
send_command() {
    local cmd="$1"
    if [[ "$VERBOSE" == "1" ]]; then
        echo "→ $cmd"
    fi
    echo "$cmd" > "$REQUEST_PIPE"
    sleep 0.1
}

# Wait for app to start
sleep 1

echo "App started (PID: $APP_PID)"
echo ""

# Test basic commands
echo "Running basic tests..."

echo "1. Health check"
send_command '{"id":"test1","v":1,"command":"health"}'

echo "2. Show indicator (circle)"
send_command '{"id":"test2","v":1,"command":"show","config":{"shape":"circle","size":20,"colors":{"primary":"#FF0000"},"opacity":0.9}}'

sleep 2

echo "3. Update config (ring)"
send_command '{"id":"test3","v":1,"command":"config","config":{"shape":"ring","size":25,"colors":{"primary":"#00FF00","secondary":"#008800"}}}'

sleep 2

echo "4. Hide indicator"
send_command '{"id":"test4","v":1,"command":"hide"}'

sleep 1

echo "5. Invalid command test"
send_command '{"id":"test5","v":1,"command":"invalid"}'

echo "6. Invalid JSON test"
send_command '{"invalid json'

echo ""
echo "Basic tests completed. Starting interactive mode..."
echo "Enter JSON commands (or 'quit' to exit):"

# Interactive mode
while true; do
    read -r -p "> " input
    
    if [[ "$input" == "quit" || "$input" == "exit" ]]; then
        break
    fi
    
    if [[ "$input" == "help" ]]; then
        cat << 'EOF'
Available commands:

Health check:
{"id":"h1","v":1,"command":"health"}

Show indicator:
{"id":"s1","v":1,"command":"show","config":{"shape":"circle","size":20}}

Hide indicator:
{"id":"h1","v":1,"command":"hide"}

Update config:
{"id":"c1","v":1,"command":"config","config":{"offset":{"x":10,"y":-10}}}

Shapes: circle, ring, orb
Colors: #FF0000, #00FF00, #0000FF, etc.
Size: 10-50 recommended
Opacity: 0.0-1.0

EOF
        continue
    fi
    
    if [[ -n "$input" ]]; then
        send_command "$input"
    fi
done

cleanup