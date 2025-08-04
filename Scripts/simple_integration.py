#!/usr/bin/env python3
"""
Simple TranscriptionIndicator Integration
Demonstrates the working shell approach that shows visible shapes.
"""

import subprocess
import time
from pathlib import Path

def show_shape(shape, size=100):
    """Show a shape using the working shell method."""
    executable = Path(__file__).parent.parent / "release" / "TranscriptionIndicator"
    cmd = f'echo "show {shape} {size}" | {executable}'
    
    print(f"Showing {shape} (size {size})")
    # Run in background so it doesn't block
    subprocess.Popen(cmd, shell=True)
    
def hide_all():
    """Hide all shapes."""
    executable = Path(__file__).parent.parent / "release" / "TranscriptionIndicator"
    cmd = f'echo "hide" | {executable}'
    subprocess.Popen(cmd, shell=True)

def main():
    """Simple demo that actually shows visible shapes."""
    print("Simple TranscriptionIndicator Demo")
    print("=" * 35)
    
    # Demo sequence - each shape will be visible
    shapes = [("circle", 80), ("ring", 100), ("orb", 60)]
    
    for shape, size in shapes:
        show_shape(shape, size)
        time.sleep(3)  # Let you see the shape
        
    print("Demo complete - shapes should be visible!")
    print("Run 'pkill TranscriptionIndicator' to clean up")

if __name__ == "__main__":
    main()