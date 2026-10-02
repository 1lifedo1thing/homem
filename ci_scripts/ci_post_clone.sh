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

# visionOS upload validation requires a 2x background rendition. Validate every
# layer so a successful local asset-catalog compile cannot hide a missing scale.
python3 - "$repo_dir" <<'PY'
import json, pathlib, struct, sys
stack = pathlib.Path(sys.argv[1]) / 'Homem/Resources/Assets.xcassets/AppIconVision.solidimagestack'
for layer in ('Front', 'Middle', 'Back'):
    imageset = stack / f'{layer}.solidimagestacklayer/Content.imageset'
    entries = json.loads((imageset / 'Contents.json').read_text())['images']
    image = next((item for item in entries if item.get('scale') == '2x' and item.get('filename')), None)
    if image is None:
        raise SystemExit(f'error: visionOS {layer} icon layer requires a 2x image.')
    data = (imageset / image['filename']).read_bytes()
    if data[:8] != b'\x89PNG\r\n\x1a\n' or struct.unpack('>II', data[16:24]) != (1024, 1024):
        raise SystemExit(f'error: visionOS {layer} icon must be a 1024x1024 PNG at 2x.')
print('visionOS layered icon preflight passed.')
PY

# Apple's processing scans embedded SDKs too. WebRTC references camera APIs even
# though Homem's desktop viewer only receives video (ITMS-90683).
for usage_key in NSCameraUsageDescription NSMicrophoneUsageDescription; do
  usage_text="$(/usr/libexec/PlistBuddy -c "Print :$usage_key" "$repo_dir/Homem/Info.plist")"
  if [[ -z "$usage_text" ]]; then
    echo "error: Homem/Info.plist must include a nonempty $usage_key." >&2
    exit 1
  fi
done
echo 'Privacy purpose string preflight passed.'

python3 "$repo_dir/scripts/check-localizations.py"

# SwiftTerm's pinned build tool plugin generates version metadata. Cloud workers
# cannot display Xcode's interactive plugin approval dialog. This preference is
# scoped to Apple's disposable worker; never change the local developer machine.
if [[ "${CI_XCODE_CLOUD:-}" == "TRUE" ]]; then
  defaults write com.apple.dt.Xcode IDESkipPackagePluginFingerprintValidatation -bool YES
fi

# Build the checked-in project and Package.resolved directly; no XcodeGen or
# automatic dependency upgrades are needed on the cloud worker.
