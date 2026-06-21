#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
TAURI_DIR="$WORKSPACE_ROOT/Sources"

echo "=== Building VNKey Tauri for Linux ==="
command -v npm >/dev/null || { echo "Error: npm is required."; exit 1; }
command -v cargo >/dev/null || { echo "Error: Rust/Cargo is required."; exit 1; }
command -v g++ >/dev/null || { echo "Error: g++ is required."; exit 1; }

cd "$TAURI_DIR"
npm ci
npm run check
npm run tauri build

BUILD_OUT_DIR="$WORKSPACE_ROOT/.build"
mkdir -p "$BUILD_OUT_DIR"
echo "=== Copying Linux build artifacts to $BUILD_OUT_DIR ==="
if [ -d "$TAURI_DIR/src-tauri/target/release/bundle/deb" ]; then
    cp "$TAURI_DIR/src-tauri/target/release/bundle/deb"/*.deb "$BUILD_OUT_DIR/" 2>/dev/null || true
fi
if [ -d "$TAURI_DIR/src-tauri/target/release/bundle/appimage" ]; then
    cp "$TAURI_DIR/src-tauri/target/release/bundle/appimage"/*.AppImage "$BUILD_OUT_DIR/" 2>/dev/null || true
fi

echo ""
echo "=== Build finished ==="
echo "Artifacts copied to: $BUILD_OUT_DIR"
