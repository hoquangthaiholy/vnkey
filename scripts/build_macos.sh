#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
TAURI_DIR="$WORKSPACE_ROOT/Sources"

ACTION="${1:-build}"

if [ "$ACTION" = "dmg" ]; then
    ACTION="build-installer"
fi

case "$ACTION" in
    build|build-installer|install|clean|uninstall) ;;
    *)
    echo "Usage: $0 [build|build-installer|install|clean|uninstall]"
    echo ""
    echo "Actions:"
    echo "  build           Build the application bundle (.app) (default)"
    echo "  build-installer Build the application bundle and disk image (.dmg)"
    echo "  install         Build and install /Applications/VNKey.app"
    echo "  clean           Remove Cargo, frontend, and copied build artifacts"
    echo "  uninstall       Remove /Applications/VNKey.app"
    exit 1
    ;;
esac

run_privileged() {
    if [ -w /Applications ]; then
        "$@"
    else
        sudo "$@"
    fi
}

if [ "$ACTION" = "uninstall" ]; then
    echo "=== Uninstalling VNKey ==="
    killall VNKey 2>/dev/null || true
    if [ -e /Applications/VNKey.app ]; then
        run_privileged rm -rf /Applications/VNKey.app
    fi
    echo "=== Uninstall finished ==="
    exit 0
fi

if [ "$ACTION" = "clean" ]; then
    echo "=== Cleaning build artifacts ==="
    if [ -d "$TAURI_DIR/src-tauri" ]; then
        cd "$TAURI_DIR/src-tauri"
        cargo clean
    fi
    cd "$TAURI_DIR"
    rm -rf build node_modules .svelte-kit
    rm -rf "$WORKSPACE_ROOT/.build"
    echo "=== Clean finished ==="
    exit 0
fi

echo "=== Building VNKey Tauri for macOS ($ACTION) ==="
command -v npm >/dev/null || { echo "Error: npm is required."; exit 1; }
command -v cargo >/dev/null || { echo "Error: Rust/Cargo is required."; exit 1; }

cd "$TAURI_DIR"
npm ci
npm run check

# Always build a universal binary (arm64 + x86_64) so the same .app runs on
# both Apple Silicon and Intel Macs.
TARGET_FLAG="--target universal-apple-darwin"
TARGET_DIR="universal-apple-darwin/release"
ARCH="universal"

BUNDLES="app"
if [ "$ACTION" = "build-installer" ]; then
    BUNDLES="app,dmg"
fi

# Load environment variables from .env if present
if [ -f "$TAURI_DIR/.env" ]; then
    echo "Loading environment variables from $TAURI_DIR/.env"
    while IFS= read -r line || [ -n "$line" ]; do
        if [[ ! "$line" =~ ^# ]] && [[ "$line" =~ = ]]; then
            key=$(echo "$line" | cut -d'=' -f1)
            val=$(echo "$line" | cut -d'=' -f2-)
            val="${val%\"}"
            val="${val#\"}"
            val="${val%\'}"
            val="${val#\'}"
            export "$key=$val"
        fi
    done < "$TAURI_DIR/.env"
fi

rm -rf "$TAURI_DIR/src-tauri/target/$TARGET_DIR/bundle/macos/VNKey.app"
if [ "$ACTION" = "build-installer" ]; then
    rm -rf "$TAURI_DIR/src-tauri/target/$TARGET_DIR/bundle/dmg"
fi

npm run tauri build -- $TARGET_FLAG --bundles "$BUNDLES"

APP_PATH="$TAURI_DIR/src-tauri/target/$TARGET_DIR/bundle/macos/VNKey.app"
if [ ! -d "$APP_PATH" ]; then
    echo "Error: expected application bundle was not produced: $APP_PATH"
    exit 1
fi
codesign --force --deep --sign - "$APP_PATH"
codesign --verify --deep --strict --verbose=2 "$APP_PATH"

BUILD_OUT_DIR="$WORKSPACE_ROOT/.build"
mkdir -p "$BUILD_OUT_DIR"
echo "=== Copying macOS build artifacts to $BUILD_OUT_DIR ==="
rm -rf "$BUILD_OUT_DIR/VNKey.app"

# Copy the app bundle
cp -R "$APP_PATH" "$BUILD_OUT_DIR/"

VERSION=$(node -p "require('./package.json').version")
TAR_NAME="VNKey_${VERSION}_${ARCH}.tar.gz"

echo "=== Compressing VNKey.app to $TAR_NAME ==="
rm -f "$BUILD_OUT_DIR"/VNKey_*.tar.gz
tar -czf "$BUILD_OUT_DIR/$TAR_NAME" -C "$BUILD_OUT_DIR" VNKey.app
if [ "$ACTION" = "build-installer" ]; then
    find "$TAURI_DIR/src-tauri/target/$TARGET_DIR/bundle/dmg" -maxdepth 1 -type f -name '*.dmg' -exec cp {} "$BUILD_OUT_DIR/" \;
fi

if [ "$ACTION" = "install" ]; then
    echo "=== Installing VNKey.app to /Applications ==="
    echo "Closing currently running VNKey app..."
    osascript -e 'quit app "VNKey"' 2>/dev/null || true
    sleep 1
    killall VNKey 2>/dev/null || true
    sleep 1
    
    echo "Replacing /Applications/VNKey.app..."
    if [ -e /Applications/VNKey.app ]; then
        if [ -w /Applications/VNKey.app ]; then
            rm -rf /Applications/VNKey.app || sudo rm -rf /Applications/VNKey.app
        else
            sudo rm -rf /Applications/VNKey.app
        fi
    fi
    
    if [ -w /Applications ]; then
        ditto "$APP_PATH" /Applications/VNKey.app || sudo ditto "$APP_PATH" /Applications/VNKey.app
    else
        sudo ditto "$APP_PATH" /Applications/VNKey.app
    fi
    
    echo "Opening new VNKey app..."
    open /Applications/VNKey.app
    echo "=== Installation finished ==="
fi

echo ""
echo "=== Build finished ==="
echo "Application bundle & artifacts copied to: $BUILD_OUT_DIR"
