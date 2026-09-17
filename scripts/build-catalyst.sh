#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
# Use the configured development team. Ad-hoc signing cannot access the app's Keychain.
xcodebuild -project Homem.xcodeproj -scheme HomemCatalyst \
  -destination 'platform=macOS,variant=Mac Catalyst,arch=arm64' \
  -derivedDataPath build-catalyst -skipPackagePluginValidation \
  -allowProvisioningUpdates -allowProvisioningDeviceRegistration build
