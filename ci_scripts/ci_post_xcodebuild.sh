#!/bin/bash
set -euo pipefail
if [[ "${CI_XCODEBUILD_ACTION:-}" == "test-without-building" ]]; then
  state_dir="${TMPDIR:-/tmp}/homem-cloud-fixture"
  if [[ -f "$state_dir/server.pid" ]]; then
    kill "$(cat "$state_dir/server.pid")" 2>/dev/null || true
    rm -f "$state_dir/server.pid"
  fi
fi
