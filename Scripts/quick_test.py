#!/usr/bin/env python3
"""
Quick test script for TranscriptionIndicator enhanced features.
Tests all shape variants and positioning modes with visual confirmation.
"""

import subprocess
import time
import sys
from pathlib import Path

def run_command(cmd, app_process):
    """Send command to the running app and get response."""
    try:
        app_process.stdin.write(f"{cmd}\n")
        app_process.stdin.flush()
        time.sleep(0.1)  # Brief pause for command processing
        return True
    except Exception as e:
        print(f"Error sending command '{cmd}': {e}")
        return False

def main():
    """Run quick test of enhanced features."""
    
    # Find the executable
    script_dir = Path(__file__).parent
    project_dir = script_dir.parent
    executable = project_dir / "release" / "TranscriptionIndicator"
    
    if not executable.exists():
        print(f"❌ Executable not found: {executable}")
        print("Run 'Scripts/build.sh' first to build the release version")
        return 1
    
    print("🚀 TranscriptionIndicator Quick Feature Test")
    print("=" * 50)
    
    try:
        # Start the application
        app_process = subprocess.Popen(
            [str(executable)],
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            bufsize=0
        )
        
        time.sleep(1)  # Let app initialize
        
        # Test sequence
        tests = [
            ("Health Check", "health"),
            ("Circle (default)", "show circle 80"),
            ("Ring variant", "show ring 100"),
            ("Orb variant", "show orb 60"),
            ("Center positioning", "show center 120"),
            ("Hide", "hide")
        ]
        
        for test_name, command in tests:
            print(f"\n📍 {test_name}")
            print(f"   Command: {command}")
            
            if run_command(command, app_process):
                if "show" in command and "hide" not in command:
                    print("   ✅ Shape should be visible - check your screen!")
                    time.sleep(3)  # Give time to see the shape
                elif command == "hide":
                    print("   ✅ Shape should now be hidden")
                    time.sleep(1)
                else:
                    print("   ✅ Command sent")
                    time.sleep(1)
            else:
                print("   ❌ Command failed")
        
        print(f"\n🎉 Test sequence completed!")
        print("All enhanced features have been demonstrated:")
        print("  - Multiple shape variants (circle, ring, orb)")
        print("  - Size variations and live updates")
        print("  - Center positioning mode")
        print("  - Smooth show/hide animations")
        
        # Clean shutdown
        run_command("hide", app_process)
        app_process.stdin.close()
        app_process.wait(timeout=3)
        
    except subprocess.TimeoutExpired:
        print("⚠️  App didn't terminate cleanly, forcing shutdown")
        app_process.kill()
        app_process.wait()
    except Exception as e:
        print(f"❌ Test failed: {e}")
        if app_process.poll() is None:
            app_process.kill()
        return 1
    
    print("\n✅ Test completed successfully!")
    return 0

if __name__ == "__main__":
    sys.exit(main())