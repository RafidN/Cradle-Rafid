#!/usr/bin/env bash
# Runs a game server and gives it a graceful shutdown. Godot can't catch SIGTERM, so on
# SIGTERM/SIGINT this sends "shutdown" to the server's localhost admin port; the server
# then warns players, saves everyone and quits. Used by the server container and the
# dev launchers.
#
# Usage: tools/server_entrypoint.sh <godot binary> [godot args...] -- --server [--port=N] [--admin-port=N] ...
# Env: SHUTDOWN_WAIT (seconds to wait for a clean exit before killing, default 20).
set -uo pipefail

PORT=7777
ADMIN_PORT=""
for arg in "$@"; do
  case "$arg" in
    --port=*) PORT="${arg#--port=}" ;;
    --admin-port=*) ADMIN_PORT="${arg#--admin-port=}" ;;
  esac
done
ADMIN_PORT="${ADMIN_PORT:-$((PORT + 1000))}"

"$@" &
SERVER=$!

graceful_stop() {
  echo "[entrypoint] Stop requested; asking the server on admin port $ADMIN_PORT to save and quit"
  if ! { exec 3<>"/dev/tcp/127.0.0.1/$ADMIN_PORT" && echo "shutdown" >&3; } 2>/dev/null; then
    echo "[entrypoint] Admin port unreachable; stopping the server directly"
    kill -TERM "$SERVER" 2>/dev/null
  fi
  for _ in $(seq 1 "${SHUTDOWN_WAIT:-20}"); do
    kill -0 "$SERVER" 2>/dev/null || exit 0
    sleep 1
  done
  echo "[entrypoint] Server didn't exit in time; killing it"
  kill -KILL "$SERVER" 2>/dev/null
  exit 1
}
trap graceful_stop TERM INT

wait "$SERVER"
