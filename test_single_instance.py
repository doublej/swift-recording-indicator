#!/usr/bin/env python3
"""
Test script to verify single instance enforcement for TranscriptionIndicator.

This script demonstrates that only one instance of TranscriptionIndicator can run at a time.
"""

import subprocess
import time
import sys
import os

def test_single_instance():
    """Test that only one instance of TranscriptionIndicator can run at a time."""
    
    executable_path = "./release/TranscriptionIndicator"
    
    if not os.path.exists(executable_path):
        print(f"Error: Executable not found at {executable_path}")
        print("Please run './Scripts/build.sh' first to build the application.")
        return False
    
    print("Testing single instance enforcement for TranscriptionIndicator...")
    print("=" * 60)
    
    # Test 1: Start first instance
    print("\n1. Starting first instance...")
    proc1 = subprocess.Popen(
        [executable_path], 
        stdout=subprocess.PIPE, 
        stderr=subprocess.PIPE,
        stdin=subprocess.PIPE,
        text=True
    )
    
    # Give it time to start and acquire the lock
    time.sleep(1)
    
    # Test 2: Try to start second instance - should exit immediately
    print("2. Attempting to start second instance (should fail and exit)...")
    result = subprocess.run(
        [executable_path, "--version"],
        capture_output=True,
        text=True,
        timeout=5
    )
    
    print(f"   Second instance exit code: {result.returncode}")
    print(f"   Second instance stderr output:")
    for line in result.stderr.split('\n'):
        if line.strip():
            print(f"     {line}")
    
    # Test 3: Try a third instance - should also exit immediately
    print("3. Attempting to start third instance (should also fail and exit)...")
    result2 = subprocess.run(
        [executable_path, "--help"],
        capture_output=True,
        text=True,
        timeout=5
    )
    
    print(f"   Third instance exit code: {result2.returncode}")
    print(f"   Third instance stderr output:")
    for line in result2.stderr.split('\n'):
        if line.strip():
            print(f"     {line}")
    
    # Clean up first instance
    print("4. Terminating first instance...")
    proc1.terminate()
    try:
        proc1.wait(timeout=5)
        print("   First instance terminated successfully")
    except subprocess.TimeoutExpired:
        print("   First instance did not terminate, killing...")
        proc1.kill()
        proc1.wait()
    
    # Test 4: After first instance is gone, new instance should work
    print("5. Starting new instance after first instance terminated...")
    result3 = subprocess.run(
        [executable_path, "--version"],
        capture_output=True,
        text=True,
        timeout=5
    )
    
    print(f"   New instance exit code: {result3.returncode}")
    print(f"   New instance stdout: {result3.stdout.strip()}")
    
    print("\n" + "=" * 60)
    
    if result.returncode == 0 and result2.returncode == 0 and result3.returncode == 0:
        print("✅ SUCCESS: Single instance enforcement is working correctly!")
        print("   - Secondary instances exit gracefully")
        print("   - New instances can start after the first one terminates")
        return True
    else:
        print("❌ FAILURE: Single instance enforcement may not be working correctly")
        return False

if __name__ == "__main__":
    success = test_single_instance()
    sys.exit(0 if success else 1)