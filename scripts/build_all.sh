#!/bin/bash
set -e

# Resolve the absolute path of the scripts directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

OS_NAME="$(uname -s)"

echo "Detecting host operating system... $OS_NAME"

case "$OS_NAME" in
    Darwin)
        echo "Launching macOS build..."
        "$SCRIPT_DIR/build_macos.sh"
        ;;
    Linux)
        echo "Launching Linux build..."
        "$SCRIPT_DIR/build_linux.sh"
        ;;
    CYGWIN*|MINGW32*|MSYS*|MINGW*)
        echo "Launching Windows build..."
        cmd.exe /c "$SCRIPT_DIR/build_windows.bat"
        ;;
    *)
        echo "Error: Unsupported operating system: $OS_NAME"
        exit 1
        ;;
esac
