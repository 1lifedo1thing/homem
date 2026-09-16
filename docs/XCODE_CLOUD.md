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

**Status: active.** The app record and workflow were created in Kitta Ltd on 17 September 2026. The first build from commit `7273dd7` passed both its required simulator test action and iOS archive action.

- App Store Connect app: [Homem (6812852139)](https://appstoreconnect.apple.com/apps/6812852139/distribution)
- Cloud product: `13960BE0-6304-4C11-A080-C67D06BE2E79`
- Workflow: [Homem CI](https://appstoreconnect.apple.com/teams/cbaca10a-f696-4d2b-959e-0d3fa1b23452/xcode-cloud/products/13960BE0-6304-4C11-A080-C67D06BE2E79/workflows/A3B8E4E8-2CBF-49A8-83E3-6E20DFFE1DA3)
- Starts on changes to `main` and pull requests from any source branch targeting `main`, with automatic cancellation of superseded builds.
- Environment: Xcode 26.6 (17F113), compatible latest-release macOS (Tahoe 26.5.1 when pinned); clean builds.
- Required simulator test action: Homem scheme, iPhone 17 Pro, latest OS included with the selected Xcode.
- iOS archive action: Homem scheme, distribution preparation set to **TestFlight (Internal Testing Only)**.
- [Build 1](https://appstoreconnect.apple.com/teams/cbaca10a-f696-4d2b-959e-0d3fa1b23452/xcode-cloud/products/13960BE0-6304-4C11-A080-C67D06BE2E79/builds/de595d62-2229-4007-967b-c338080cd2f8) passed tests and archive.

Build 1 successfully fetched the primary repository, resolved every package dependency (including WebRTC), checked the project/workflow configuration, and ran the Cloud preparation hooks. The iOS archive succeeded with zero errors and warnings. The separate test worker also started its local transport fixture successfully. Public package dependencies required no additional repository grant. The required test action subsequently passed.

## TestFlight

The workflow now includes a **TestFlight Internal Testing - iOS** post-action using the Archive - iOS artifact. Successful builds are delivered to [Homem Internal](https://appstoreconnect.apple.com/apps/6812852139/testflight/groups/926f0163-0a4e-41e4-b3b6-2eb289f969c3). The group has automatic distribution enabled for local Xcode uploads as well; Cloud delivery is handled by the workflow post-action.

[Build 2](https://appstoreconnect.apple.com/teams/cbaca10a-f696-4d2b-959e-0d3fa1b23452/xcode-cloud/products/13960BE0-6304-4C11-A080-C67D06BE2E79/builds/ef5e32b1-31e1-42a8-ae48-45333fc42bcc/summary) was started after enabling TestFlight. Upload, Apple processing, and tester availability are separate stages; workflow activation alone does not mean the build is installable. The internal group currently has three members configured in App Store Connect.

No external/public distribution, App Store submission, paid compute subscription, or export-compliance declaration has been configured.

Apple references: [First workflow](https://developer.apple.com/documentation/xcode/configuring-your-first-xcode-cloud-workflow), [custom build scripts](https://developer.apple.com/documentation/xcode/writing-custom-build-scripts), [Cloud environment variables](https://developer.apple.com/documentation/xcode/environment-variable-reference).

## Distribution repair — 17 September 2026

Cloud builds passed compilation, tests, signing, and IPA export but failed during App Store Connect preparation. Xcode’s `ContentDelivery.log` exposed the actual server rejection for Build 3: **ITMS-90683**, missing `NSCameraUsageDescription`. The prebuilt WebRTC framework references `AVCaptureDevice` and related camera APIs; Apple requires a purpose string even though Homem only receives remote desktop video and does not capture the camera.

`Homem/Info.plist` now includes a truthful camera description. The Cloud post-clone preflight checks that both camera and microphone descriptions are present and nonempty. No camera capture or permission request was added.

Commit `3fd5c51` also changed the 1024px marketing icon to RGB without an alpha channel and added an icon preflight. That packaging correction did not fix the processing rejection; builds 3 and 4 still failed because of the missing camera declaration. Standalone validation and upload succeeded, but those results did not mean Apple’s subsequent processing accepted the app.

The workflow is pinned to Xcode 26.6 (17F113), the installed local toolchain. Its main/pull-request triggers and internal-only TestFlight preparation remain intact. The pin was a diagnostic step before the processing error was identified, not a proven fix. Build 5, started before the camera declaration was added, received the same ITMS-90683 rejection on Xcode 26.6. Its remaining work was canceled after the corrected build started.

The direct upload also warned that the prebuilt WebRTC framework lacks a dSYM (UUID `4C4C4496-5555-3144-A149-A7E882FEE780`). This was not the blocking rejection. No credentials or private delivery logs are stored in this repository.

[Build 6](https://appstoreconnect.apple.com/teams/cbaca10a-f696-4d2b-959e-0d3fa1b23452/xcode-cloud/products/13960BE0-6304-4C11-A080-C67D06BE2E79/builds/9d70dbc7-be88-4334-aadb-bd12fef922f9/summary), from commit `74af148`, passed the simulator test and archive actions. App Store Connect processing completed successfully, confirming the privacy-metadata fix. [TestFlight 1.0.0 (6)](https://appstoreconnect.apple.com/teams/cbaca10a-f696-4d2b-959e-0d3fa1b23452/apps/6812852139/testflight/ios/5e8ae4ea-28f4-4536-b332-0cc0e9b9453c) currently shows **Missing Compliance**. The encryption questionnaire identifies standard encryption in the embedded WebRTC library and asks whether the app will be distributed in France; that distribution decision is pending the owner. No answer has been submitted and the build is not yet installable.
