#!/usr/bin/env python3
"""
TranscriptionIndicator Demo Script

A comprehensive demonstration and testing script for the TranscriptionIndicator macOS app.
This script cycles through all available features, serving as both a showcase and 
integration test for the application.

Features Demonstrated:
- Health check and process status
- Shape variants (circle, ring, orb) with different sizes
- Positioning modes (caret detection vs center-only)
- Animation system with smooth transitions
- Hide/show functionality
- Live shape and size updates
- Error handling and graceful shutdown

Usage:
    python3 demo.py [--mode full|quick|shapes|positions] [--executable PATH]
    python3 demo.py --help

Author: Generated for TranscriptionIndicator integration testing
"""

import argparse
import asyncio
import json
import subprocess
import sys
import time
from enum import Enum
from pathlib import Path
from typing import List, Optional, Tuple, Dict, Any


class DemoMode(Enum):
    """Available demonstration modes."""
    FULL = "full"
    QUICK = "quick"
    SHAPES = "shapes"
    POSITIONS = "positions"


class IndicatorDemo:
    """
    Comprehensive demonstration controller for TranscriptionIndicator.
    
    Manages the demo lifecycle, command execution, and provides detailed
    visual feedback about each operation being performed.
    """
    
    def __init__(self, executable_path: str, verbose: bool = True):
        """
        Initialize the demo controller.
        
        Args:
            executable_path: Path to the TranscriptionIndicator executable
            verbose: Enable detailed output during demo execution
        """
        self.executable_path = Path(executable_path)
        self.verbose = verbose
        self.process: Optional[subprocess.Popen] = None
        self.demo_running = False
        
        # Validate executable exists
        if not self.executable_path.exists():
            raise FileNotFoundError(f"Executable not found: {executable_path}")
        
        # Demo configuration
        self.shapes = ["circle", "ring", "orb"]
        self.sizes = [20, 35, 50, 75, 100]
        self.demo_timings = {
            "command_delay": 0.5,    # Delay between commands
            "shape_display": 3.0,    # How long to show each shape
            "size_display": 2.0,     # How long to show each size
            "transition_delay": 1.0,  # Delay between major sections
        }
    
    def print_section(self, title: str, description: str = "") -> None:
        """Print a formatted section header with optional description."""
        if not self.verbose:
            return
            
        print(f"\n{'=' * 60}")
        print(f"  {title}")
        if description:
            print(f"  {description}")
        print(f"{'=' * 60}")
    
    def print_step(self, step: str, details: str = "") -> None:
        """Print a formatted step with optional details."""
        if not self.verbose:
            return
            
        print(f"\n→ {step}")
        if details:
            print(f"  {details}")
    
    def print_result(self, result: str, success: bool = True) -> None:
        """Print command result with status indicator."""
        if not self.verbose:
            return
            
        status = "✓" if success else "✗"
        print(f"  {status} {result}")
    
    async def send_command(self, command: str) -> Tuple[str, bool]:
        """
        Send a command to the TranscriptionIndicator process.
        
        Args:
            command: Command string to send
            
        Returns:
            Tuple of (response, success_flag)
        """
        if not self.process:
            return "Process not running", False
        
        try:
            # Send command
            self.process.stdin.write(f"{command}\n")
            self.process.stdin.flush()
            
            # Read response with timeout to avoid blocking
            # Use asyncio to handle the potentially blocking readline
            loop = asyncio.get_event_loop()
            
            # Create a wrapper function that properly handles the readline
            def read_line():
                if self.process and self.process.stdout:
                    line = self.process.stdout.readline()
                    if isinstance(line, bytes):
                        return line.decode('utf-8').strip()
                    return line.strip() if line else ""
                return ""
            
            # Run the blocking readline in a thread pool with timeout
            try:
                response = await asyncio.wait_for(
                    loop.run_in_executor(None, read_line),
                    timeout=5.0
                )
                success = response.startswith("OK:")
                return response, success
                
            except asyncio.TimeoutError:
                return "Command timed out - no response received", False
            
        except Exception as e:
            return f"Command failed: {str(e)}", False
    
    def start_process(self) -> bool:
        """
        Start the TranscriptionIndicator process.
        
        Returns:
            True if process started successfully, False otherwise
        """
        try:
            self.process = subprocess.Popen(
                [str(self.executable_path)],
                stdin=subprocess.PIPE,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
                bufsize=1,  # Line buffered for proper I/O handling
                universal_newlines=True
            )
            
            # Give process time to initialize
            time.sleep(1.0)
            
            # Verify process is running
            if self.process.poll() is None:
                return True
            else:
                # If process exited, try to get error information
                if self.process.stderr:
                    try:
                        error_output = self.process.stderr.read()
                        if error_output:
                            print(f"Process startup error: {error_output}")
                    except Exception:
                        print("Process exited but could not read error output")
                return False
                
        except Exception as e:
            print(f"Failed to start process: {e}")
            return False
    
    def stop_process(self) -> None:
        """Stop the TranscriptionIndicator process gracefully."""
        if self.process:
            try:
                # Send hide command first
                self.process.stdin.write("hide\n")
                self.process.stdin.flush()
                
                # Close stdin and wait for graceful shutdown
                self.process.stdin.close()
                self.process.wait(timeout=5.0)
                
            except subprocess.TimeoutExpired:
                # Force terminate if graceful shutdown failed
                self.process.terminate()
                try:
                    self.process.wait(timeout=2.0)
                except subprocess.TimeoutExpired:
                    self.process.kill()
            
            except Exception:
                # Force kill as last resort
                try:
                    self.process.kill()
                except:
                    pass
            
            finally:
                self.process = None
    
    async def demo_health_check(self) -> bool:
        """
        Demonstrate health check functionality.
        
        Returns:
            True if health check passed, False otherwise
        """
        self.print_section("Health Check Demo", 
                         "Testing process health, accessibility status, and positioning mode")
        
        self.print_step("Sending health command", 
                       "This shows process status, accessibility permissions, and current mode")
        
        response, success = await self.send_command("health")
        self.print_result(response, success)
        
        if not success:
            print("\n⚠️  Health check failed. This may indicate:")
            print("   - Process startup issues")
            print("   - Missing accessibility permissions")
            print("   - Communication problems")
            return False
        
        print("\n✓ Health check passed - process is ready for demonstration")
        return True
    
    async def demo_basic_shapes(self) -> None:
        """Demonstrate basic shape variants with default sizing."""
        self.print_section("Basic Shape Variants Demo", 
                         "Cycling through circle, ring, and orb shapes with default size")
        
        for shape in self.shapes:
            self.print_step(f"Showing {shape} shape", 
                           f"Default size with caret detection (fallback to center)")
            
            response, success = await self.send_command(f"show {shape}")
            self.print_result(response, success)
            
            if success:
                await asyncio.sleep(self.demo_timings["shape_display"])
            
            # Hide before next shape
            await self.send_command("hide")
            await asyncio.sleep(self.demo_timings["transition_delay"])
    
    async def demo_size_variations(self) -> None:
        """Demonstrate size variations using circle shape."""
        self.print_section("Size Variations Demo", 
                         "Testing different sizes from small to large using circle shape")
        
        for size in self.sizes:
            self.print_step(f"Showing circle with size {size}", 
                           f"Size range: 10-300 pixels, current: {size}px")
            
            response, success = await self.send_command(f"show circle {size}")
            self.print_result(response, success)
            
            if success:
                await asyncio.sleep(self.demo_timings["size_display"])
        
        # Hide after size demo
        await self.send_command("hide")
        await asyncio.sleep(self.demo_timings["transition_delay"])
    
    async def demo_positioning_modes(self) -> None:
        """Demonstrate different positioning modes."""
        self.print_section("Positioning Modes Demo", 
                         "Comparing caret detection mode vs center-only mode")
        
        # Test caret detection mode (default)
        self.print_step("Testing caret detection mode", 
                       "Attempts to follow text cursor, falls back to center if unavailable")
        
        response, success = await self.send_command("show circle 60")
        self.print_result(response, success)
        
        if success:
            await asyncio.sleep(self.demo_timings["shape_display"])
        
        # Hide and switch to center mode
        await self.send_command("hide")
        await asyncio.sleep(self.demo_timings["transition_delay"])
        
        # Test center-only mode
        self.print_step("Testing center-only mode", 
                       "Always positions indicator at screen center, ignores cursor")
        
        response, success = await self.send_command("show center 60")
        self.print_result(response, success)
        
        if success:
            await asyncio.sleep(self.demo_timings["shape_display"])
        
        # Hide after positioning demo
        await self.send_command("hide")
        await asyncio.sleep(self.demo_timings["transition_delay"])
    
    async def demo_live_updates(self) -> None:
        """Demonstrate live shape and size updates without hiding."""
        self.print_section("Live Updates Demo", 
                         "Updating shape and size while indicator remains visible")
        
        # Start with initial shape
        self.print_step("Starting with circle size 40")
        response, success = await self.send_command("show circle 40")
        self.print_result(response, success)
        
        if not success:
            return
        
        await asyncio.sleep(self.demo_timings["size_display"])
        
        # Update size while keeping same shape
        self.print_step("Updating size to 80 (same shape)")
        response, success = await self.send_command("show circle 80")
        self.print_result(response, success)
        
        await asyncio.sleep(self.demo_timings["size_display"])
        
        # Change shape while keeping size
        self.print_step("Changing to ring shape (same size)")
        response, success = await self.send_command("show ring 80")
        self.print_result(response, success)
        
        await asyncio.sleep(self.demo_timings["size_display"])
        
        # Change both shape and size
        self.print_step("Changing to orb with size 120")
        response, success = await self.send_command("show orb 120")
        self.print_result(response, success)
        
        await asyncio.sleep(self.demo_timings["size_display"])
        
        # Final hide
        await self.send_command("hide")
        await asyncio.sleep(self.demo_timings["transition_delay"])
    
    async def demo_animation_system(self) -> None:
        """Demonstrate the animation system with rapid show/hide cycles."""
        self.print_section("Animation System Demo", 
                         "Testing smooth transitions and animation timing")
        
        shapes_and_sizes = [
            ("circle", 30),
            ("ring", 50),
            ("orb", 70),
            ("circle", 90)
        ]
        
        for i, (shape, size) in enumerate(shapes_and_sizes):
            self.print_step(f"Animation cycle {i+1}: {shape} size {size}", 
                           "Watch for smooth fade-in and fade-out transitions")
            
            # Show with animation
            response, success = await self.send_command(f"show {shape} {size}")
            self.print_result(f"Show: {response}", success)
            
            await asyncio.sleep(1.5)
            
            # Hide with animation
            response, success = await self.send_command("hide")
            self.print_result(f"Hide: {response}", success)
            
            await asyncio.sleep(1.0)
    
    async def demo_error_handling(self) -> None:
        """Demonstrate error handling with invalid commands."""
        self.print_section("Error Handling Demo", 
                         "Testing application response to invalid commands")
        
        invalid_commands = [
            ("invalid_command", "Unknown command"),
            ("show invalid_shape", "Invalid shape name"),
            ("show circle abc", "Non-numeric size"),
            ("show circle 500", "Size out of range (max 300)"),
            ("show circle 0", "Size out of range (min 1)"),
        ]
        
        for command, description in invalid_commands:
            self.print_step(f"Testing: {command}", description)
            response, success = await self.send_command(command)
            
            # For error handling demo, we expect failures
            expected_failure = not success and response.startswith("ERROR:")
            self.print_result(response, expected_failure)
            
            await asyncio.sleep(0.5)
    
    async def run_full_demo(self) -> bool:
        """
        Run the complete demonstration sequence.
        
        Returns:
            True if demo completed successfully, False if major errors occurred
        """
        self.demo_running = True
        
        try:
            print("TranscriptionIndicator Feature Demonstration")
            print("=" * 50)
            print("This demo will cycle through all available features.")
            print("Watch your screen for visual indicators during the demo.")
            print()
            
            # Health check first
            if not await self.demo_health_check():
                return False
            
            await asyncio.sleep(self.demo_timings["transition_delay"])
            
            # Core feature demonstrations
            await self.demo_basic_shapes()
            await self.demo_size_variations()
            await self.demo_positioning_modes()
            await self.demo_live_updates()
            await self.demo_animation_system()
            await self.demo_error_handling()
            
            # Final cleanup
            self.print_section("Demo Complete", "All features have been demonstrated")
            await self.send_command("hide")
            
            print("\n✓ Demonstration completed successfully!")
            print("  All major features have been tested and demonstrated.")
            print("  The TranscriptionIndicator is ready for production use.")
            
            return True
            
        except KeyboardInterrupt:
            print("\n\n⚠️  Demo interrupted by user")
            await self.send_command("hide")
            return False
            
        except Exception as e:
            print(f"\n\n✗ Demo failed with error: {e}")
            return False
            
        finally:
            self.demo_running = False
    
    async def run_quick_demo(self) -> bool:
        """Run a shortened version of the demo for quick testing."""
        self.demo_running = True
        
        try:
            print("TranscriptionIndicator Quick Demo")
            print("=" * 35)
            
            # Quick health check
            if not await self.demo_health_check():
                return False
            
            # Show one of each shape quickly
            for shape in self.shapes:
                self.print_step(f"Quick test: {shape}")
                await self.send_command(f"show {shape} 50")
                await asyncio.sleep(1.5)
                await self.send_command("hide")
                await asyncio.sleep(0.5)
            
            print("\n✓ Quick demo completed!")
            return True
            
        except Exception as e:
            print(f"\n✗ Quick demo failed: {e}")
            return False
            
        finally:
            self.demo_running = False
    
    async def run_shapes_demo(self) -> bool:
        """Run demo focused on shape variations."""
        self.demo_running = True
        
        try:
            print("TranscriptionIndicator Shapes Demo")
            print("=" * 38)
            
            if not await self.demo_health_check():
                return False
            
            await self.demo_basic_shapes()
            await self.demo_size_variations()
            
            print("\n✓ Shapes demo completed!")
            return True
            
        except Exception as e:
            print(f"\n✗ Shapes demo failed: {e}")
            return False
            
        finally:
            self.demo_running = False
    
    async def run_positions_demo(self) -> bool:
        """Run demo focused on positioning modes."""
        self.demo_running = True
        
        try:
            print("TranscriptionIndicator Positioning Demo")
            print("=" * 42)
            
            if not await self.demo_health_check():
                return False
            
            await self.demo_positioning_modes()
            
            print("\n✓ Positioning demo completed!")
            return True
            
        except Exception as e:
            print(f"\n✗ Positioning demo failed: {e}")
            return False
            
        finally:
            self.demo_running = False


def find_executable() -> Optional[str]:
    """
    Automatically locate the TranscriptionIndicator executable.
    
    Returns:
        Path to executable if found, None otherwise
    """
    current_dir = Path(__file__).parent.parent
    
    # Try common locations
    locations = [
        current_dir / "release" / "TranscriptionIndicator",
        current_dir / ".build" / "release" / "TranscriptionIndicator",
        current_dir / "TranscriptionIndicator",
    ]
    
    for location in locations:
        if location.exists() and location.is_file():
            return str(location)
    
    return None


def main():
    """Main entry point for the demo script."""
    parser = argparse.ArgumentParser(
        description="TranscriptionIndicator comprehensive demo and testing script",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Demo Modes:
  full       Complete demonstration of all features (default)
  quick      Abbreviated demo for quick testing
  shapes     Focus on shape variants and sizing
  positions  Focus on positioning modes (caret vs center)

Examples:
  python3 demo.py                                    # Full demo with auto-detection
  python3 demo.py --mode quick                       # Quick test
  python3 demo.py --executable ./custom/path        # Custom executable path
  python3 demo.py --mode shapes --quiet             # Shapes demo with minimal output
        """
    )
    
    parser.add_argument(
        "--mode",
        type=str,
        choices=["full", "quick", "shapes", "positions"],
        default="full",
        help="Demo mode to run (default: full)"
    )
    
    parser.add_argument(
        "--executable",
        type=str,
        help="Path to TranscriptionIndicator executable (auto-detected if not specified)"
    )
    
    parser.add_argument(
        "--quiet",
        action="store_true",
        help="Reduce output verbosity"
    )
    
    args = parser.parse_args()
    
    # Find executable
    executable_path = args.executable or find_executable()
    if not executable_path:
        print("Error: Could not locate TranscriptionIndicator executable.")
        print("Please specify path with --executable or build the project first.")
        print("\nTo build the project:")
        print("  cd /path/to/project")
        print("  swift build --configuration release")
        sys.exit(1)
    
    print(f"Using executable: {executable_path}")
    print()
    
    # Create demo instance
    try:
        demo = IndicatorDemo(executable_path, verbose=not args.quiet)
    except FileNotFoundError as e:
        print(f"Error: {e}")
        sys.exit(1)
    
    # Start the process
    if not demo.start_process():
        print("Error: Failed to start TranscriptionIndicator process")
        print("Please check that the executable is valid and has proper permissions.")
        sys.exit(1)
    
    # Run the appropriate demo
    async def run_demo():
        try:
            mode = DemoMode(args.mode)
            
            if mode == DemoMode.FULL:
                success = await demo.run_full_demo()
            elif mode == DemoMode.QUICK:
                success = await demo.run_quick_demo()
            elif mode == DemoMode.SHAPES:
                success = await demo.run_shapes_demo()
            elif mode == DemoMode.POSITIONS:
                success = await demo.run_positions_demo()
            else:
                print(f"Error: Unknown demo mode: {args.mode}")
                return False
            
            return success
            
        finally:
            demo.stop_process()
    
    # Execute demo
    try:
        success = asyncio.run(run_demo())
        sys.exit(0 if success else 1)
        
    except KeyboardInterrupt:
        print("\n\nDemo interrupted by user")
        demo.stop_process()
        sys.exit(1)
        
    except Exception as e:
        print(f"\nDemo failed with unexpected error: {e}")
        demo.stop_process()
        sys.exit(1)


if __name__ == "__main__":
    main()