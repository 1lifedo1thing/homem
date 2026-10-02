#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
python3 scripts/fixture-server.py > /tmp/homem-vision-fixture.log 2>&1 &
fixture_pid=$!
trap 'kill "$fixture_pid" 2>/dev/null || true' EXIT
xcodebuild -project Homem.xcodeproj -scheme HomemVision \
  -destination "${HOMEM_VISION_TEST_DESTINATION:-platform=visionOS Simulator,name=Apple Vision Pro}" \
  -derivedDataPath build -skipPackagePluginValidation -parallel-testing-enabled NO test
