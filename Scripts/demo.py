#!/usr/bin/env python3
"""
Simple demo script for the simplified TranscriptionIndicator.

This demonstrates the basic functionality:
- Start the app
- Send 'show' command to display red circle
- Wait 3 seconds
- Send 'hide' command to hide the circle
- Exit
"""

import subprocess
import time
import sys
import os

def main():
    # Path to the app executable
    app_path = os.path.join(os.path.dirname(__file__), "..", "release", "TranscriptionIndicator")
    
    if not os.path.exists(app_path):
        print("ERROR: TranscriptionIndicator not found at:", app_path)
        print("Please build the app first using Scripts/build.sh")
        sys.exit(1)
    
    print("Starting TranscriptionIndicator demo...")
    
    # Start the app
    process = subprocess.Popen(
        [app_path],
        stdin=subprocess.PIPE,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        bufsize=0
    )
    
    try:
        # Show the circle
        print("Sending 'show' command...")
        process.stdin.write("show\n")
        process.stdin.flush()
        
        # Read response
        response = process.stdout.readline().strip()
        print("Response:", response)
        
        # Wait to see the circle
        print("Circle should be visible for 3 seconds...")
        time.sleep(3)
        
        # Hide the circle
        print("Sending 'hide' command...")
        process.stdin.write("hide\n")
        process.stdin.flush()
        
        # Read response
        response = process.stdout.readline().strip()
        print("Response:", response)
        
        print("Demo complete! Circle should now be hidden.")
        
    except Exception as e:
        print("ERROR:", e)
    finally:
        # Close stdin to let the app exit
        process.stdin.close()
        process.wait()

if __name__ == "__main__":
    main()