#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
OUT="${TMPDIR:-/tmp}/vnkey-engine-corpus-test"
FLAGS="-O2"

if [ "${SANITIZE:-0}" = "1" ]; then
  FLAGS="-O1 -g -fsanitize=address,undefined"
fi

clang++ -std=c++14 $FLAGS \
  "$ROOT/Tests/EngineCorpusTest.cpp" \
  "$ROOT/Sources/src-tauri/engine/Engine.cpp" \
  "$ROOT/Sources/src-tauri/engine/EnglishDictionary.cpp" \
  "$ROOT/Sources/src-tauri/engine/Macro.cpp" \
  "$ROOT/Sources/src-tauri/engine/Vietnamese.cpp" \
  "$ROOT/Sources/src-tauri/engine/SmartSwitchKey.cpp" \
  "$ROOT/Sources/src-tauri/engine/ConvertTool.cpp" \
  -o "$OUT"

"$OUT"
