#!/bin/bash
set -euo pipefail

# SwiftTerm's pinned build tool plugin generates version metadata. Cloud workers
# cannot display Xcode's interactive plugin approval dialog. This preference is
# scoped to Apple's disposable worker; never change the local developer machine.
if [[ "${CI_XCODE_CLOUD:-}" == "TRUE" ]]; then
  defaults write com.apple.dt.Xcode IDESkipPackagePluginFingerprintValidatation -bool YES
fi

# Build the checked-in project and Package.resolved directly; no XcodeGen or
# automatic dependency upgrades are needed on the cloud worker.
