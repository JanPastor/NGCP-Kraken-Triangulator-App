#!/usr/bin/env python3
"""
launcher.py — KrakenSDR Triangulator Launcher
================================================
Entry point for the PyInstaller-packaged executable.

Responsibilities:
  1. Resolve paths correctly whether running from source or from a
     PyInstaller frozen bundle (sys._MEIPASS).
  2. Start the Flask backend server with all background threads.
  3. Automatically open the operator's default browser to the dashboard.

Usage (development):
    python launcher.py

Usage (packaged):
    Double-click KrakenSDR-Triangulator.exe
"""

import os
import sys

# ── Path Resolution ──────────────────────────────────────────────────────────
# PyInstaller extracts bundled data files to a temporary directory stored in
# sys._MEIPASS. For non-frozen (development) runs, use the script's own
# directory as the base.
if getattr(sys, 'frozen', False):
    # Running as a PyInstaller bundle
    BUNDLE_DIR = sys._MEIPASS
else:
    # Running as a normal Python script
    BUNDLE_DIR = os.path.dirname(os.path.abspath(__file__))

# The server resolves BASE_DIR from its own __file__ location.
# We need to ensure the server module can be imported.
sys.path.insert(0, BUNDLE_DIR)

# Change working directory so relative paths in the server resolve correctly.
os.chdir(BUNDLE_DIR)


def main():
    """Launch the KrakenSDR Triangulator server and open the browser."""
    print("=" * 60)
    print("  KrakenSDR Triangulator v1.7.0")
    print("  NGCP Signal Verification Tool")
    print("=" * 60)
    print(f"  Bundle directory: {BUNDLE_DIR}")
    print(f"  Working directory: {os.getcwd()}")
    print()

    # Import and start the server — this call blocks until the server is
    # shut down (via the Settings > Shutdown button or Ctrl+C).
    from server.kraken_server import start_server
    start_server(open_browser=True)


if __name__ == "__main__":
    main()
