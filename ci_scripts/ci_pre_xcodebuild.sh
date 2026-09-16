#!/bin/bash
set -euo pipefail

if [[ "${CI_XCODEBUILD_ACTION:-}" != "test-without-building" ]]; then
  exit 0
fi

script_dir=$(cd "$(dirname "$0")" && pwd)
state_dir="${TMPDIR:-/tmp}/homem-cloud-fixture"
mkdir -p "$state_dir"
nohup python3 "$script_dir/fixture-server.py" > "$state_dir/server.log" 2>&1 &
fixture_pid=$!
printf '%s\n' "$fixture_pid" > "$state_dir/server.pid"

for attempt in {1..30}; do
  if ! kill -0 "$fixture_pid" 2>/dev/null; then
    cat "$state_dir/server.log"
    exit 1
  fi
  if curl --noproxy '*' --fail --silent http://127.0.0.1:18765/health > /dev/null; then
    echo "Homem local HTTP/WebSocket/SSE fixture is ready."
    exit 0
  fi
  sleep 1
done
kill "$fixture_pid" 2>/dev/null || true
echo "Homem fixture did not become ready." >&2
exit 1
