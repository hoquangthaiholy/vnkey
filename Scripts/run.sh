#!/bin/bash
# Build lại, thoát bản đang chạy và mở bản mới. Thêm --settings để mở luôn cửa sổ Cài đặt.
set -euo pipefail
cd "$(dirname "$0")/.."
./Scripts/build-app.sh | tail -1
pkill -f "VNKey.app/Contents/MacOS/VNKey" || true
sleep 1
if [ "${1:-}" = "--settings" ]; then open build/VNKey.app --args --settings; else open build/VNKey.app; fi
sleep 2
pgrep -f "VNKey.app/Contents/MacOS/VNKey" >/dev/null && echo "VNKey đang chạy" || { echo "VNKey KHÔNG chạy"; exit 1; }
tail -1 "$HOME/Library/Logs/VNKey.log" 2>/dev/null | cut -c1-160 || true
