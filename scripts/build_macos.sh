#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
TAURI_DIR="$WORKSPACE_ROOT/Sources"

ACTION="${1:-build}" # default is build

if [ "$ACTION" != "build" ] && [ "$ACTION" != "clean" ] && [ "$ACTION" != "dmg" ] && [ "$ACTION" != "install" ]; then
    echo "Usage: $0 [build|clean|dmg|install]"
    echo ""
    echo "Actions:"
    echo "  build   : Build application bundle (.app) (default)"
    echo "  clean   : Clean all build artifacts and node_modules"
    echo "  dmg     : Build application bundle and disk image (.dmg)"
    echo "  install : Build, terminate running VNKey app, replace /Applications/VNKey.app, and run it"
    exit 1
fi

if [ "$ACTION" = "clean" ]; then
    echo "=== Cleaning build artifacts ==="
    if [ -d "$TAURI_DIR/src-tauri" ]; then
        cd "$TAURI_DIR/src-tauri"
        cargo clean
    fi
    cd "$TAURI_DIR"
    rm -rf build node_modules .svelte-kit
    echo "=== Clean finished ==="
    exit 0
fi

echo "=== Building VNKey Tauri for macOS ($ACTION) ==="
command -v npm >/dev/null || { echo "Error: npm is required."; exit 1; }
command -v cargo >/dev/null || { echo "Error: Rust/Cargo is required."; exit 1; }

cd "$TAURI_DIR"
npm ci
npm run check

BUNDLES="app"
if [ "$ACTION" = "dmg" ]; then
    BUNDLES="app,dmg"
fi

npm run tauri build -- --bundles "$BUNDLES"

APP_PATH="$TAURI_DIR/src-tauri/target/release/bundle/macos/VNKey.app"
codesign --force --deep --sign - "$APP_PATH"
codesign --verify --deep --strict "$APP_PATH"

if [ "$ACTION" = "install" ]; then
    echo "=== Installing VNKey.app to /Applications ==="
    echo "Closing currently running VNKey app..."
    killall VNKey || true
    sleep 1
    
    echo "Replacing /Applications/VNKey.app..."
    rm -rf /Applications/VNKey.app
    cp -R "$APP_PATH" /Applications/
    
    echo "Opening new VNKey app..."
    open /Applications/VNKey.app
    echo "=== Installation finished ==="
fi

echo ""
echo "=== Build finished ==="
echo "Application: $APP_PATH"
if [ "$ACTION" = "dmg" ]; then
    echo "DMG folder: $TAURI_DIR/src-tauri/target/release/bundle/dmg"
fi
