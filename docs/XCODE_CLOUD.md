# Xcode Cloud

## Project and source control

- Repository: [iebb/homem](https://github.com/iebb/homem) (private)
- Default branch: `main`
- Project: `Homem.xcodeproj`
- Shared scheme: `Homem`
- Bundle identifier: `ad.neko.homem`
- Apple Developer organization: **Kitta Ltd**
- Team identifier: `7P8CLHDH5G`
- Signing: Automatic

The generated Xcode project and pinned `Package.resolved` are committed. Cloud builds do not require XcodeGen. If project configuration changes locally, run `xcodegen generate` and commit the resulting project alongside `project.yml`.

## Worker preparation

- `ci_post_clone.sh` permits SwiftTerm's pinned version-metadata build plugin in the disposable Xcode Cloud worker. It does not change the local developer's Xcode preferences. Review dependency changes before accepting a new plugin version.
- `ci_pre_xcodebuild.sh` starts the loopback HTTP/SSE/WebSocket fixture during `test-without-building`, waits for readiness, and fails if startup fails.
- `ci_post_xcodebuild.sh` stops that fixture after tests. The fixture script is linked into `ci_scripts` so Apple includes it in the separate test environment.
- Integration tests fail, rather than skip, if the fixture is unavailable in Xcode Cloud. No production credentials or server are needed.

The pre/post hooks and native networking smoke check have passed locally. The app's earlier simulator checks are recorded in [VALIDATION.md](VALIDATION.md).

## Apple-side workflow

**Status: active.** The app record and workflow were created in Kitta Ltd on 17 September 2026. The first build was started from commit `7273dd7`; its result must be checked separately from workflow activation.

- App Store Connect app: [Homem (6812852139)](https://appstoreconnect.apple.com/apps/6812852139/distribution)
- Cloud product: `13960BE0-6304-4C11-A080-C67D06BE2E79`
- Workflow: [Homem CI](https://appstoreconnect.apple.com/teams/cbaca10a-f696-4d2b-959e-0d3fa1b23452/xcode-cloud/products/13960BE0-6304-4C11-A080-C67D06BE2E79/workflows/A3B8E4E8-2CBF-49A8-83E3-6E20DFFE1DA3)
- Starts on changes to `main` and pull requests from any source branch targeting `main`, with automatic cancellation of superseded builds.
- Environment: Latest Release Xcode and macOS (Xcode 27 / macOS 27 when configured); clean builds.
- Required simulator test action: Homem scheme, iPhone 17 Pro, latest OS included with the selected Xcode.
- iOS archive action: Homem scheme, distribution preparation set to None.
- [Build 1](https://appstoreconnect.apple.com/teams/cbaca10a-f696-4d2b-959e-0d3fa1b23452/xcode-cloud/products/13960BE0-6304-4C11-A080-C67D06BE2E79/builds/de595d62-2229-4007-967b-c338080cd2f8) was accepted and queued.

Xcode's onboarding showed an optional access warning for the public `stasel/WebRTC` dependency. The primary repository is connected, and App Store Connect lists no additional private repositories. Dependency resolution still needs to be confirmed by the first build. The authorization link generated in Xcode is account-specific; opening it under a different Apple account produces “Request is for another user.”

No TestFlight testers, automatic external distribution, App Store submission, paid compute subscription, or export-compliance declaration is configured by these repository scripts.

Apple references: [First workflow](https://developer.apple.com/documentation/xcode/configuring-your-first-xcode-cloud-workflow), [custom build scripts](https://developer.apple.com/documentation/xcode/writing-custom-build-scripts), [Cloud environment variables](https://developer.apple.com/documentation/xcode/environment-variable-reference).
