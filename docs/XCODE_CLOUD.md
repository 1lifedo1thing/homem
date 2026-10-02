# Xcode Cloud

## Active workflows — 3 October 2026

All three platforms use the private [iebb/homem](https://github.com/iebb/homem) repository, `master`, the checked-in `Homem.xcodeproj`, and automatic signing for Kitta Ltd (`7P8CLHDH5G`). Workflows start on pushes to `master` and can be started manually. Superseded builds are automatically canceled. The environment is pinned to **Xcode 27 (27A266a)** and **macOS Golden Gate 27 (26A428)**, with clean builds.

| Workflow | Shared scheme | Required tests | Archive |
| --- | --- | --- | --- |
| [Homem iOS CI](https://appstoreconnect.apple.com/teams/cbaca10a-f696-4d2b-959e-0d3fa1b23452/xcode-cloud/products/13960BE0-6304-4C11-A080-C67D06BE2E79/workflows/A3B8E4E8-2CBF-49A8-83E3-6E20DFFE1DA3) | `Homem` | iPhone 17 Pro / iOS 27 | iOS device |
| [Homem visionOS CI](https://appstoreconnect.apple.com/teams/cbaca10a-f696-4d2b-959e-0d3fa1b23452/xcode-cloud/products/13960BE0-6304-4C11-A080-C67D06BE2E79/workflows/8c7000f3-3994-4b58-a2fc-23680009593c) | `HomemVision` | Apple Vision Pro / visionOS 27 | visionOS device |
| [Homem macOS CI](https://appstoreconnect.apple.com/teams/cbaca10a-f696-4d2b-959e-0d3fa1b23452/xcode-cloud/products/13960BE0-6304-4C11-A080-C67D06BE2E79/workflows/d5b424ea-87cb-46c4-8fb9-bb7bcc3394cc) | `HomemCatalyst` | Mac Catalyst / selected macOS | Mac Catalyst |

Archives are App Store eligible. App Review submission and release remain manual. All platforms deliver successful archives to **Homem Internal** (three testers). The existing iOS external TestFlight post-action is also retained. Cloud's shared product build counter was advanced from 59 to **68**, above the locally uploaded Mac build 67. Future local uploads must likewise stay ahead of the latest Cloud build number.

The Cloud product is `13960BE0-6304-4C11-A080-C67D06BE2E79`, associated with [Homem (6812852139)](https://appstoreconnect.apple.com/apps/6812852139/distribution). [The workflow snapshot](xcode-cloud/workflows.json) records the public API configuration; TestFlight post-actions and the product build counter are managed in App Store Connect.

## Worker preparation

The generated project, shared schemes, and pinned `Package.resolved` are committed. Cloud builds do not require XcodeGen. When changing `project.yml`, regenerate and commit the resulting project.

- `ci_post_clone.sh` checks iOS and visionOS icons, camera/microphone purpose strings, and localization coverage. It permits SwiftTerm's pinned version-metadata build plugin in the disposable worker.
- `ci_pre_xcodebuild.sh` starts the loopback HTTP/SSE/WebSocket fixture for `test-without-building`, waits for readiness, and fails if startup fails.
- `ci_post_xcodebuild.sh` stops the fixture. Both `fixture-server.py` and its `ui_fixture.py` dependency are linked into `ci_scripts` for the separate test environment.
- Integration tests fail if the fixture is unavailable in Cloud. UI tests use the real sign-in and transport against this local fixture. No production credentials are needed.

Apple references: [workflow reference](https://developer.apple.com/documentation/xcode/xcode-cloud-workflow-reference), [custom build scripts](https://developer.apple.com/documentation/xcode/writing-custom-build-scripts), [environment variables](https://developer.apple.com/documentation/xcode/environment-variable-reference), [setting the next build number](https://developer.apple.com/documentation/xcode/setting-the-next-build-number-for-xcode-cloud-builds).

## Setup verification

All three workflow configurations were read back from Apple's API with required `TEST` and `ARCHIVE` actions and the correct shared schemes. Local icon, privacy-string, and localization preflights passed (741 localized strings), as did the fixture startup, UI endpoint, and shutdown hooks. New Cloud build results are recorded separately after execution.

## Historical iOS validation

The first workflow was created on 17 September 2026. Build 1 from `7273dd7` passed simulator tests and the iOS archive. Build 58 from `b77dc85` later completed archive and TestFlight distribution. These historical results do not certify the new three-platform configuration.

## Distribution repair — 17 September 2026

Cloud builds passed compilation, tests, signing, and IPA export but failed during App Store Connect preparation. Xcode’s `ContentDelivery.log` exposed the actual server rejection for Build 3: **ITMS-90683**, missing `NSCameraUsageDescription`. The prebuilt WebRTC framework references `AVCaptureDevice` and related camera APIs; Apple requires a purpose string even though Homem only receives remote desktop video and does not capture the camera.

`Homem/Info.plist` now includes a truthful camera description. The Cloud post-clone preflight checks that both camera and microphone descriptions are present and nonempty. No camera capture or permission request was added.

Commit `3fd5c51` also changed the 1024px marketing icon to RGB without an alpha channel and added an icon preflight. That packaging correction did not fix the processing rejection; builds 3 and 4 still failed because of the missing camera declaration. Standalone validation and upload succeeded, but those results did not mean Apple’s subsequent processing accepted the app.

The workflow is pinned to Xcode 26.6 (17F113), the installed local toolchain. Its main/pull-request triggers and internal-only TestFlight preparation remain intact. The pin was a diagnostic step before the processing error was identified, not a proven fix. Build 5, started before the camera declaration was added, received the same ITMS-90683 rejection on Xcode 26.6. Its remaining work was canceled after the corrected build started.

The direct upload also warned that the prebuilt WebRTC framework lacks a dSYM (UUID `4C4C4496-5555-3144-A149-A7E882FEE780`). This was not the blocking rejection. No credentials or private delivery logs are stored in this repository.

[Build 6](https://appstoreconnect.apple.com/teams/cbaca10a-f696-4d2b-959e-0d3fa1b23452/xcode-cloud/products/13960BE0-6304-4C11-A080-C67D06BE2E79/builds/9d70dbc7-be88-4334-aadb-bd12fef922f9/summary), from commit `74af148`, passed the simulator test and archive actions. App Store Connect processing completed successfully, confirming the privacy-metadata fix. [TestFlight 1.0.0 (6)](https://appstoreconnect.apple.com/teams/cbaca10a-f696-4d2b-959e-0d3fa1b23452/apps/6812852139/testflight/ios/5e8ae4ea-28f4-4536-b332-0cc0e9b9453c) currently shows **Missing Compliance**. The owner subsequently requested `ITSAppUsesNonExemptEncryption = false`. That Boolean declaration is now included in `Homem/Info.plist` for future uploads; it does not retroactively change Build 6. The replacement build must finish processing before tester availability can be confirmed.
