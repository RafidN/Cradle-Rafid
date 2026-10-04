#!/usr/bin/env bash
# Launch a headless server and several windowed clients on this machine for netcode testing.
# Usage: tools/run_local.sh [clients=2] [added_rtt_ms=150] [loss_percent=5] [jitter_ms=20]
# Set GODOT to override the Godot binary. Ctrl+C stops everything.
set -euo pipefail

GODOT="${GODOT:-/Users/rafidn/Downloads/Godot.app/Contents/MacOS/Godot}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CLIENTS="${1:-2}"
LATENCY="${2:-150}"
LOSS="${3:-5}"
JITTER="${4:-20}"

trap 'kill $(jobs -p) 2>/dev/null || true' EXIT

"$GODOT" --path "$ROOT" --headless -- --server &
sleep 1

for i in $(seq 1 "$CLIENTS"); do
  "$GODOT" --path "$ROOT" --resolution 800x450 --position "$((40 + (i - 1) * 820)),80" -- \
    --connect=127.0.0.1 --name="Artist$i" --latency="$LATENCY" --jitter="$JITTER" --loss="$LOSS" &
done

wait
