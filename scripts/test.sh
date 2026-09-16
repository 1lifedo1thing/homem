#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
python3 scripts/fixture-server.py > /tmp/homem-fixture.log 2>&1 &
fixture_pid=$!
trap 'kill "$fixture_pid" 2>/dev/null || true' EXIT
xcodebuild -project Homem.xcodeproj -scheme Homem \
  -destination "${HOMEM_TEST_DESTINATION:-platform=iOS Simulator,name=iPhone 17 Pro}" \
  -derivedDataPath build -skipPackagePluginValidation -parallel-testing-enabled NO test
