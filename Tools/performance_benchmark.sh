#!/bin/bash

# TranscriptionIndicator Performance Benchmark Script
# Tests various performance scenarios and generates report

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
INDICATOR_PATH="${1:-./TranscriptionIndicator}"
TEST_DURATION=30
RAPID_FIRE_COUNT=1000
REPORT_FILE="performance_report_$(date +%Y%m%d_%H%M%S).txt"

echo -e "${GREEN}TranscriptionIndicator Performance Benchmark${NC}"
echo "============================================"
echo "Binary: $INDICATOR_PATH"
echo "Duration: ${TEST_DURATION}s per test"
echo "Report: $REPORT_FILE"
echo

# Check if binary exists
if [ ! -x "$INDICATOR_PATH" ]; then
    echo -e "${RED}Error: TranscriptionIndicator binary not found or not executable${NC}"
    echo "Usage: $0 [path_to_TranscriptionIndicator]"
    exit 1
fi

# Start report
{
    echo "TranscriptionIndicator Performance Benchmark Report"
    echo "Generated: $(date)"
    echo "System: $(uname -a)"
    echo "CPU: $(sysctl -n machdep.cpu.brand_string)"
    echo "Memory: $(sysctl -n hw.memsize | awk '{print $1/1024/1024/1024 " GB"}')"
    echo
} > "$REPORT_FILE"

# Function to monitor process
monitor_process() {
    local pid=$1
    local duration=$2
    local label=$3
    
    echo -e "${YELLOW}Monitoring $label for ${duration}s...${NC}"
    
    local cpu_samples=()
    local mem_samples=()
    local start_time=$(date +%s)
    
    while [ $(($(date +%s) - start_time)) -lt $duration ]; do
        if ps -p $pid > /dev/null; then
            # Get CPU and memory usage
            local stats=$(ps -p $pid -o %cpu,rss | tail -1)
            local cpu=$(echo $stats | awk '{print $1}')
            local mem=$(echo $stats | awk '{print $2}')
            
            cpu_samples+=($cpu)
            mem_samples+=($mem)
            
            sleep 0.5
        else
            echo -e "${RED}Process terminated unexpectedly${NC}"
            return 1
        fi
    done
    
    # Calculate statistics
    local cpu_avg=$(IFS=+; echo "scale=2; (${cpu_samples[*]}) / ${#cpu_samples[@]}" | bc)
    local mem_avg=$(IFS=+; echo "scale=0; (${mem_samples[*]}) / ${#mem_samples[@]}" | bc)
    local mem_mb=$(echo "scale=2; $mem_avg / 1024" | bc)
    
    echo "  Average CPU: ${cpu_avg}%"
    echo "  Average Memory: ${mem_mb} MB"
    
    {
        echo "Test: $label"
        echo "  Duration: ${duration}s"
        echo "  Samples: ${#cpu_samples[@]}"
        echo "  Average CPU: ${cpu_avg}%"
        echo "  Average Memory: ${mem_mb} MB"
        echo
    } >> "$REPORT_FILE"
}

# Test 1: Startup Performance
echo -e "${GREEN}Test 1: Startup Performance${NC}"
START_TIME=$(date +%s%N)
echo '{"id":"startup","v":1,"command":"health"}' | timeout 5 "$INDICATOR_PATH" > /dev/null 2>&1
END_TIME=$(date +%s%N)
STARTUP_TIME=$(echo "scale=3; ($END_TIME - $START_TIME) / 1000000000" | bc)
echo "  Startup time: ${STARTUP_TIME}s"
{
    echo "Test: Startup Performance"
    echo "  Startup time: ${STARTUP_TIME}s"
    echo
} >> "$REPORT_FILE"

# Test 2: Idle CPU Usage
echo -e "${GREEN}Test 2: Idle CPU Usage (breathing animation)${NC}"
{
    echo '{"id":"show","v":1,"command":"show","config":{"shape":"circle","size":20,"animations":{"breathingCycle":1.8}}}'
    sleep $TEST_DURATION
    echo '{"id":"hide","v":1,"command":"hide"}'
} | "$INDICATOR_PATH" > /dev/null 2>&1 &
PID=$!
sleep 1  # Let it start
monitor_process $PID $((TEST_DURATION - 2)) "Idle Animation"
wait $PID 2>/dev/null || true

# Test 3: Rapid Position Updates
echo -e "${GREEN}Test 3: Rapid Position Updates${NC}"
{
    echo '{"id":"show2","v":1,"command":"show","config":{"mode":"cursor"}}'
    sleep 1
    
    # Send rapid position updates
    for i in $(seq 1 $RAPID_FIRE_COUNT); do
        x=$((100 + i % 500))
        y=$((100 + i % 300))
        echo '{"id":"pos'$i'","v":1,"command":"config","config":{"offset":{"x":'$x',"y":'$y'}}}'
        # Small delay to simulate realistic updates
        sleep 0.001
    done
    
    sleep 2
    echo '{"id":"hide2","v":1,"command":"hide"}'
} | "$INDICATOR_PATH" > /dev/null 2>&1 &
PID=$!
sleep 1  # Let it start
monitor_process $PID 10 "Rapid Updates"
wait $PID 2>/dev/null || true

# Test 4: Shape Transitions
echo -e "${GREEN}Test 4: Shape Transitions${NC}"
{
    shapes=("circle" "ring" "orb")
    echo '{"id":"show3","v":1,"command":"show"}'
    
    for i in $(seq 1 100); do
        shape=${shapes[$((i % 3))]}
        echo '{"id":"shape'$i'","v":1,"command":"config","config":{"shape":"'$shape'"}}'
        sleep 0.1
    done
    
    echo '{"id":"hide3","v":1,"command":"hide"}'
} | "$INDICATOR_PATH" > /dev/null 2>&1 &
PID=$!
sleep 1  # Let it start
monitor_process $PID 12 "Shape Transitions"
wait $PID 2>/dev/null || true

# Test 5: Memory Stress Test
echo -e "${GREEN}Test 5: Memory Stress Test${NC}"
{
    echo '{"id":"show4","v":1,"command":"show"}'
    
    # Create many show/hide cycles
    for i in $(seq 1 50); do
        echo '{"id":"hide'$i'","v":1,"command":"hide"}'
        echo '{"id":"show'$i'","v":1,"command":"show","config":{"shape":"circle","size":'$((20 + i % 30))'}}'
    done
    
    sleep 5
    echo '{"id":"hide_final","v":1,"command":"hide"}'
} | "$INDICATOR_PATH" > /dev/null 2>&1 &
PID=$!
sleep 1  # Let it start
monitor_process $PID 15 "Memory Stress"
wait $PID 2>/dev/null || true

# Test 6: Performance Statistics
echo -e "${GREEN}Test 6: Extracting Performance Statistics${NC}"
{
    echo '{"id":"show5","v":1,"command":"show"}'
    sleep 2
    
    # Simulate some activity
    for i in $(seq 1 20); do
        echo '{"id":"update'$i'","v":1,"command":"config","config":{"opacity":'$(echo "scale=2; 0.5 + $i * 0.02" | bc)'}}'
        sleep 0.1
    done
    
    # Get health check with stats
    echo '{"id":"health_stats","v":1,"command":"health"}'
    sleep 1
    echo '{"id":"hide5","v":1,"command":"hide"}'
} | "$INDICATOR_PATH" 2>&1 | grep -A 20 "Performance Statistics" >> "$REPORT_FILE" || true

echo
echo -e "${GREEN}Benchmark Complete!${NC}"
echo "Report saved to: $REPORT_FILE"
echo
echo "Summary:"
tail -20 "$REPORT_FILE" | grep -E "(Average CPU|Average Memory|Startup time)" || true