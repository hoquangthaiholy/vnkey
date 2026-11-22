#!/bin/bash
# Chạy test engine. Plugin macro của swift-testing trong Command Line Tools thỉnh thoảng không nạp được
# ở lần build đầu ("plugin for module 'TestingMacros' not found"): thử lại tối đa 3 lần.
cd "$(dirname "$0")/.."
for attempt in 1 2 3; do
    out=$(swift test "$@" 2>&1)
    if echo "$out" | grep -q "Test run with"; then
        echo "$out" | grep -E "✘|↳   |Test run with"
        echo "$out" | grep -q "Test run with .* passed" && exit 0 || exit 1
    fi
    echo "$out" | grep -q "TestingMacros" || { echo "$out" | grep -E "error" | head -20; exit 1; }
done
echo "Không build được test sau 3 lần (plugin TestingMacros)."; exit 1
