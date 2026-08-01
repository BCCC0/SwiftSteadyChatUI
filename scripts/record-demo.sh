#!/bin/bash
# record-demo.sh — record the three demo videos by driving the recording-only
# UI tests. Each test ends on a settled "hold" frame; we trim the app-launch
# preamble and the app-termination tail so the video ends elegantly.
#
# Usage:
#   ./scripts/record-demo.sh                 # record all three demos
#   ./scripts/record-demo.sh demo1           # record one: demo1|demo2|demo3
#   OUT_DIR=/tmp/demos ./scripts/record-demo.sh   # custom output dir
#
# Requires: xcodegen, xcrun, ffmpeg, a booted iPhone 17 simulator.

set -euo pipefail

cd "$(git rev-parse --show-toplevel)"

SAMPLE_DIR="Examples/SwiftSteadyChatUISample"
SAMPLE_PROJECT="$SAMPLE_DIR/SwiftSteadyChatUISample.xcodeproj"
DESTINATION="platform=iOS Simulator,name=iPhone 17"
OUT_DIR="${OUT_DIR:-/tmp/demos}"
mkdir -p "$OUT_DIR"

# simctl recordVideo only writes the mp4's moov trailer (finalizing the file and
# releasing the capture session) when stopped with SIGINT. A SIGTERM/kill leaves
# a stuck "Host recording is already in progress" session — clear any strays.
clear_stuck_recorders() {
  local pid
  for pid in $(pgrep -f "simctl io .*recordVideo" 2>/dev/null); do
    kill -INT "$pid" 2>/dev/null || true
  done
  sleep 1
}

# macOS ships bash 3.2, which has no associative arrays (`declare -A` is invalid
# there), so map demo key → test name with a case statement instead.
test_name_for() {
  case "$1" in
    demo1) echo "testDemo1StreamingLongReply" ;;
    demo2) echo "testDemo2KeyboardPushUpAndDismiss" ;;
    demo3) echo "testDemo3ScrolledKeyboardNoPushUp" ;;
    *)     return 1 ;;
  esac
}

# Trim 2.5s of app-launch preamble and 1.5s of app-termination tail.
trim_video() {
  local src="$1" dst="$2"
  local dur
  dur=$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$src")
  local end
  end=$(awk -v d="$dur" -v t="1.5" 'BEGIN { print d - t }')
  ffmpeg -y -v error -ss 2.5 -to "$end" -i "$src" -c copy "$dst"
}

build_once() {
  echo "▶ Building sample + demo test bundle (once)..."
  xcodegen generate --spec "$SAMPLE_DIR/project.yml"
  xcodebuild build-for-testing \
    -project "$SAMPLE_PROJECT" \
    -scheme SwiftSteadyChatUISampleDemo \
    -destination "$DESTINATION" \
    -skipMacroValidation
}

record_one() {
  local key="$1"
  local test_name
  test_name=$(test_name_for "$key") || { echo "❌ unknown demo '$key'" >&2; exit 1; }
  local raw="$OUT_DIR/raw-$key.mp4"
  local final="$OUT_DIR/$key.mp4"

  echo "▶ Recording $key ($test_name)..."
  clear_stuck_recorders
  rm -f "$raw"   # recordVideo refuses to overwrite an existing file; remove any stale raw
  xcrun simctl io booted recordVideo --codec h264 "$raw" &
  local rec_pid=$!
  sleep 1   # let the recorder start cleanly

  xcodebuild test-without-building \
    -project "$SAMPLE_PROJECT" \
    -scheme SwiftSteadyChatUISampleDemo \
    -destination "$DESTINATION" \
    -only-testing:"SwiftSteadyChatUISampleDemoUITests/DemoRecordingTests/$test_name" \
    -skipMacroValidation || {
      kill "$rec_pid" 2>/dev/null || true
      echo "❌ $key test failed — raw video left at $raw" >&2
      exit 1
    }

  sleep 1   # let the final held frame be captured
  kill -INT "$rec_pid" 2>/dev/null || true   # SIGINT finalizes the mp4 (moov trailer)
  wait "$rec_pid" 2>/dev/null || true

  echo "▶ Trimming $key..."
  trim_video "$raw" "$final"
  rm -f "$raw"
  echo "✓ $key → $final"
}

build_once

if [ $# -ge 1 ]; then
  test_name_for "$1" >/dev/null 2>&1 || { echo "Usage: $0 [demo1|demo2|demo3]" >&2; exit 1; }
  record_one "$1"
else
  for key in demo1 demo2 demo3; do
    record_one "$key"
  done
fi

echo "All recordings done → $OUT_DIR/"
ls -lh "$OUT_DIR"/*.mp4
