#!/usr/bin/env bash
# Launch a headless server and several windowed clients on this machine for netcode testing.
# Usage: tools/run_local.sh [clients=2] [added_rtt_ms=150] [loss_percent=5] [jitter_ms=20]
# Set GODOT to override the Godot binary. Ctrl+C or closing any window stops everything.
set -euo pipefail

GODOT="${GODOT:-/Users/rafidn/Downloads/Godot.app/Contents/MacOS/Godot}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CLIENTS="${1:-2}"
LATENCY="${2:-150}"
LOSS="${3:-5}"
JITTER="${4:-20}"

PIDS=()
cleanup() { kill "${PIDS[@]}" 2>/dev/null || true; }
trap cleanup EXIT INT TERM

"$GODOT" --path "$ROOT" --headless -- --server &
PIDS+=($!)
sleep 1

for i in $(seq 1 "$CLIENTS"); do
  "$GODOT" --path "$ROOT" --resolution 800x450 --position "$((40 + (i - 1) * 820)),80" -- \
    --connect=127.0.0.1 --name="Practitioner$i" --latency="$LATENCY" --jitter="$JITTER" --loss="$LOSS" &
  PIDS+=($!)
done

# Stop everything as soon as any process exits (e.g. a client window is closed).
# (Polls because macOS ships bash 3.2, which has no `wait -n`.)
while true; do
  for pid in "${PIDS[@]}"; do
    kill -0 "$pid" 2>/dev/null || exit 0
  done
  sleep 1
done
