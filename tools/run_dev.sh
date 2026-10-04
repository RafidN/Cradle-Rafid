#!/usr/bin/env bash
# Online development setup: the backend (embedded Postgres, no Docker needed), a game
# server registered with it, and client windows that open on the login screen.
# Usage: tools/run_dev.sh [clients=1]
# Set GODOT to override the Godot binary. Ctrl+C or closing any window stops everything.
# Saved accounts live in backend/data/; delete that folder to start fresh.
set -euo pipefail

GODOT="${GODOT:-/Users/rafidn/Downloads/Godot.app/Contents/MacOS/Godot}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CLIENTS="${1:-1}"
BACKEND_URL="http://127.0.0.1:8080"

PIDS=()
cleanup() { kill "${PIDS[@]}" 2>/dev/null || true; }
trap cleanup EXIT INT TERM

if [ ! -d "$ROOT/backend/node_modules" ]; then
  (cd "$ROOT/backend" && npm install)
fi
(cd "$ROOT/backend" && exec npx tsx src/main.ts) &
PIDS+=($!)
for _ in $(seq 1 40); do
  curl -s "$BACKEND_URL/health" >/dev/null && break
  sleep 0.5
done

"$GODOT" --path "$ROOT" --headless -- --server --backend="$BACKEND_URL" --shard-id=dev --shard-name="Dev Shard" &
PIDS+=($!)
sleep 1

for i in $(seq 1 "$CLIENTS"); do
  "$GODOT" --path "$ROOT" --resolution 1280x720 --position "$((40 + (i - 1) * 60)),$((60 + (i - 1) * 60))" -- \
    --backend="$BACKEND_URL" &
  PIDS+=($!)
done

# Stop everything as soon as any process exits. (Polls: macOS bash 3.2 has no `wait -n`.)
while true; do
  for pid in "${PIDS[@]}"; do
    kill -0 "$pid" 2>/dev/null || exit 0
  done
  sleep 1
done
