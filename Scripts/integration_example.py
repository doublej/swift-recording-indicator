#!/usr/bin/env python3
"""
TranscriptionIndicator Integration Example

A minimal example showing how to integrate TranscriptionIndicator into your application.
This demonstrates the basic pattern for controlling visual recording indicators.

Requirements:
- TranscriptionIndicator executable in your PATH or specify full path
- Python 3.7+
"""

import subprocess
import sys
import time
from pathlib import Path
from typing import Optional


class TranscriptionIndicator:
    """Simple wrapper for TranscriptionIndicator executable."""
    
    def __init__(self, executable_path: Optional[str] = None):
        """
        Initialize the indicator controller.
        
        Args:
            executable_path: Path to TranscriptionIndicator executable.
                           If None, assumes it's in PATH or uses default location.
        """
        if executable_path:
            self.executable_path = Path(executable_path)
        else:
            # Try common locations
            default_path = Path(__file__).parent.parent / "release" / "TranscriptionIndicator"
            if default_path.exists():
                self.executable_path = default_path
            else:
                self.executable_path = Path("TranscriptionIndicator")
        
        self.process: Optional[subprocess.Popen] = None
    
    def start(self) -> bool:
        """
        Start the TranscriptionIndicator process.
        
        Returns:
            True if started successfully, False otherwise.
        """
        if self.process and self.process.poll() is None:
            return True  # Already running
        
        if not self.executable_path.exists():
            print(f"Error: TranscriptionIndicator executable not found at {self.executable_path}")
            print("Please ensure the executable is built and available.")
            return False
            
        # Start ONE process that we'll send multiple commands to
        self.process = subprocess.Popen(
            [str(self.executable_path)],
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            text=True,
            bufsize=1
        )
        time.sleep(0.5)  # Let it start
        return self.process.poll() is None
    
    def send_command(self, command: str) -> bool:
        """
        Send a command using shell execution (the method that shows visible shapes).
        
        Args:
            command: Command to send (e.g., "show circle", "hide")
            
        Returns:
            True if command was sent successfully, False otherwise.
        """
        # Use the shell execution method that actually shows visible shapes
        cmd = f'echo "{command}" | {self.executable_path}'
        subprocess.run(cmd, shell=True, timeout=10)
        return True
    
    def show_circle(self, size: int = 50) -> bool:
        """Show a circle indicator."""
        return self.send_command(f"show circle {size}")
    
    def show_ring(self, size: int = 50) -> bool:
        """Show a ring indicator."""
        return self.send_command(f"show ring {size}")
    
    def show_orb(self, size: int = 50) -> bool:
        """Show an orb indicator."""
        return self.send_command(f"show orb {size}")
    
    def hide(self) -> bool:
        """Hide the indicator."""
        return self.send_command("hide")
    
    def check_health(self) -> bool:
        """Check if the indicator is responsive."""
        return self.send_command("health")
    
    def stop(self):
        """Stop the TranscriptionIndicator process."""
        if self.process:
            self.hide()  # Hide any visible indicators
            time.sleep(0.1)
            self.process.stdin.close()
            self.process.wait()
            self.process = None


def demo_basic_usage():
    """Demonstrate basic usage patterns."""
    print("TranscriptionIndicator Integration Demo")
    print("=" * 40)
    
    # Initialize the indicator
    indicator = TranscriptionIndicator()
    
    # Start the process
    print("Starting TranscriptionIndicator...")
    if not indicator.start():
        print("Failed to start TranscriptionIndicator")
        return
    
    print("✓ TranscriptionIndicator started")
    
    try:
        # Demonstrate different shapes
        shapes = [
            ("circle", 60),
            ("ring", 70),
            ("orb", 50)
        ]
        
        for shape, size in shapes:
            # First hide any existing shape
            indicator.hide()
            time.sleep(0.5)  # Wait for hide to complete
            
            print(f"Showing {shape} (size {size})...")
            
            if shape == "circle":
                indicator.show_circle(size)
            elif shape == "ring":
                indicator.show_ring(size)
            elif shape == "orb":
                indicator.show_orb(size)
            
            time.sleep(2.0)  # Display for 2 seconds
        
        # Hide the indicator
        print("Hiding indicator...")
        indicator.hide()
        time.sleep(1.0)
        
        print("✓ Demo completed successfully")
        
    except KeyboardInterrupt:
        print("\nDemo interrupted by user")
    except Exception as e:
        print(f"Demo error: {e}")
    finally:
        # Always clean up
        print("Stopping TranscriptionIndicator...")
        indicator.stop()
        print("✓ Stopped")


def example_integration_pattern():
    """Show how to integrate into a larger application."""
    print("\nIntegration Pattern Example")
    print("=" * 30)
    
    # This is how you would integrate into your application
    class MyRecordingApp:
        def __init__(self):
            self.indicator = TranscriptionIndicator()
            self.is_recording = False
        
        def start_app(self):
            """Initialize the app and indicator."""
            if not self.indicator.start():
                raise RuntimeError("Failed to start visual indicator")
            print("App initialized")
        
        def start_recording(self):
            """Start recording and show indicator."""
            if not self.is_recording:
                print("Starting recording...")
                self.indicator.show_circle(60)  # Show recording indicator
                self.is_recording = True
                print("Recording started - indicator visible")
        
        def stop_recording(self):
            """Stop recording and hide indicator."""
            if self.is_recording:
                print("Stopping recording...")
                self.indicator.hide()  # Hide indicator
                self.is_recording = False
                print("Recording stopped - indicator hidden")
        
        def shutdown(self):
            """Clean shutdown."""
            if self.is_recording:
                self.stop_recording()
            self.indicator.stop()
            print("App shutdown complete")
    
    # Example usage
    app = MyRecordingApp()
    
    try:
        app.start_app()
        
        # Simulate recording workflow
        app.start_recording()
        time.sleep(2.0)  # Simulate some recording time
        app.stop_recording()
        
        print("✓ Integration example completed")
        
    except Exception as e:
        print(f"Integration example error: {e}")
    finally:
        app.shutdown()


if __name__ == "__main__":
    """Run the integration examples."""
    try:
        # Run basic demo
        demo_basic_usage()
        
        # Show integration pattern
        example_integration_pattern()
        
    except KeyboardInterrupt:
        print("\nExiting...")
        sys.exit(0)
    except Exception as e:
        print(f"Fatal error: {e}")
        sys.exit(1)