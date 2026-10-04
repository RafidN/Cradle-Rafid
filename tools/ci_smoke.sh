#!/usr/bin/env bash
# Smoke test for CI: an offline server and two bots play for 20 s. Fails if the bots
# never join, nobody lands a hit, or any script error appears.
# Usage: tools/ci_smoke.sh [godot binary]
set -uo pipefail

GODOT="${1:-godot}"
LOGS="$(mktemp -d)"
"$GODOT" --headless --path . -- --server --log-hits > "$LOGS/server.log" 2>&1 &
PIDS=($!)
sleep 3
for name in SmokeA SmokeB; do
  "$GODOT" --headless --path . -- --connect=127.0.0.1 --name="$name" --bot > "$LOGS/$name.log" 2>&1 &
  PIDS+=($!)
done
sleep 20
kill "${PIDS[@]}" 2>/dev/null
wait 2>/dev/null

joined=$(grep -c " joined " "$LOGS/server.log" || true)
hits=$(grep -c " -> " "$LOGS/server.log" || true)
errors=$(cat "$LOGS"/*.log | grep -c "SCRIPT ERROR" || true)
echo "joined: $joined, hits: $hits, script errors: $errors"
if [ "$joined" -lt 2 ] || [ "$hits" -lt 1 ] || [ "$errors" -gt 0 ]; then
  for f in "$LOGS"/*.log; do echo "=== $f"; tail -40 "$f"; done
  exit 1
fi
