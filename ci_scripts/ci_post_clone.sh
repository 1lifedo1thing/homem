#!/bin/bash
set -euo pipefail

# App Store Connect rejects the legacy 1024px marketing icon if the PNG has an
# alpha channel, even when every pixel is opaque. Catch it before archiving.
repo_dir="$(cd "$(dirname "$0")/.." && pwd)"
icon="$repo_dir/Homem/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon.png"
icon_info="$(sips -g hasAlpha -g pixelWidth -g pixelHeight "$icon")"
if ! grep -q 'hasAlpha: no' <<< "$icon_info" ||
   ! grep -q 'pixelWidth: 1024$' <<< "$icon_info" ||
   ! grep -q 'pixelHeight: 1024$' <<< "$icon_info"; then
  echo 'error: AppIcon.png must be a 1024x1024 PNG without an alpha channel.' >&2
  exit 1
fi
echo 'App Store icon preflight passed.'

# SwiftTerm's pinned build tool plugin generates version metadata. Cloud workers
# cannot display Xcode's interactive plugin approval dialog. This preference is
# scoped to Apple's disposable worker; never change the local developer machine.
if [[ "${CI_XCODE_CLOUD:-}" == "TRUE" ]]; then
  defaults write com.apple.dt.Xcode IDESkipPackagePluginFingerprintValidatation -bool YES
fi

# Build the checked-in project and Package.resolved directly; no XcodeGen or
# automatic dependency upgrades are needed on the cloud worker.
