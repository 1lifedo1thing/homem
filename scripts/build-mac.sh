#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
# Use the configured development team. Ad-hoc signing cannot access the app's Keychain.
xcodebuild -project Homem.xcodeproj -scheme HomemMac \
  -destination 'platform=macOS' \
  -derivedDataPath build-mac -skipPackagePluginValidation \
  -allowProvisioningUpdates -allowProvisioningDeviceRegistration build
