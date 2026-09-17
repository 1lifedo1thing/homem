#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
output=$(mktemp -d /tmp/homem-wire.XXXXXX)
trap 'rm -rf "$output"' EXIT
swiftc -parse-as-library -target "$(uname -m)-apple-macosx14.0" \
  Homem/Core/Localization.swift Homem/Core/JSONValue.swift Homem/Core/DemoServer.swift \
  Homem/Core/Credentials.swift Homem/Core/APIClient.swift Homem/Core/OfficialSession.swift Homem/Core/ChatRuntime.swift \
  scripts/WireSmoke.swift -o "$output/wire-smoke"
"$output/wire-smoke"
