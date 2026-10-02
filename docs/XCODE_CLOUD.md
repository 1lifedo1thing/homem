# Xcode Cloud

## Active workflows — 3 October 2026

All three platforms use the private [iebb/homem](https://github.com/iebb/homem) repository, `master`, the checked-in `Homem.xcodeproj`, and automatic signing for Kitta Ltd (`7P8CLHDH5G`). Workflows start on pushes to `master` and can be started manually. Superseded builds are automatically canceled. The environment is pinned to **Xcode 27 (27A266a)** and **macOS Golden Gate 27 (26A428)**, with clean builds.

| Workflow | Shared scheme | Required tests | Archive |
| --- | --- | --- | --- |
| [Homem iOS CI](https://appstoreconnect.apple.com/teams/cbaca10a-f696-4d2b-959e-0d3fa1b23452/xcode-cloud/products/13960BE0-6304-4C11-A080-C67D06BE2E79/workflows/A3B8E4E8-2CBF-49A8-83E3-6E20DFFE1DA3) | `Homem` | iPhone 17 Pro / iOS 27 | iOS device |
| [Homem visionOS CI](https://appstoreconnect.apple.com/teams/cbaca10a-f696-4d2b-959e-0d3fa1b23452/xcode-cloud/products/13960BE0-6304-4C11-A080-C67D06BE2E79/workflows/8c7000f3-3994-4b58-a2fc-23680009593c) | `HomemVision` | Apple Vision Pro / visionOS 27 | visionOS device |
| [Homem macOS CI](https://appstoreconnect.apple.com/teams/cbaca10a-f696-4d2b-959e-0d3fa1b23452/xcode-cloud/products/13960BE0-6304-4C11-A080-C67D06BE2E79/workflows/d5b424ea-87cb-46c4-8fb9-bb7bcc3394cc) | `HomemMac` | Native Mac / selected macOS | Native Mac |

Archives are App Store eligible. App Review submission and release remain manual. All platforms deliver successful archives to **Homem Internal** (three testers). The existing iOS external TestFlight post-action is also retained. Cloud's shared product build counter was advanced to **102**, above the locally uploaded standalone Mac build **101**. Future local uploads must likewise stay ahead of the latest Cloud build number.

The Cloud product is `13960BE0-6304-4C11-A080-C67D06BE2E79`, associated with [Homem (6812852139)](https://appstoreconnect.apple.com/apps/6812852139/distribution). [The workflow snapshot](xcode-cloud/workflows.json) records the public API configuration; TestFlight post-actions and the product build counter are managed in App Store Connect.

## Worker preparation

The generated project, shared schemes, and pinned `Package.resolved` are committed. Cloud builds do not require XcodeGen. When changing `project.yml`, regenerate and commit the resulting project.

- `ci_post_clone.sh` checks iOS, visionOS, and native macOS icons, camera/microphone purpose strings, and localization coverage. It permits SwiftTerm's pinned version-metadata build plugin in the disposable worker.
- `ci_pre_xcodebuild.sh` starts the loopback HTTP/SSE/WebSocket fixture for `test-without-building`, waits for readiness, and fails if startup fails.
- `ci_post_xcodebuild.sh` stops the fixture. Both `fixture-server.py` and its `ui_fixture.py` dependency are linked into `ci_scripts` for the separate test environment.
- Integration tests fail if the fixture is unavailable in Cloud. UI tests use the real sign-in and transport against this local fixture. No production credentials are needed.

Apple references: [workflow reference](https://developer.apple.com/documentation/xcode/xcode-cloud-workflow-reference), [custom build scripts](https://developer.apple.com/documentation/xcode/writing-custom-build-scripts), [environment variables](https://developer.apple.com/documentation/xcode/environment-variable-reference), [setting the next build number](https://developer.apple.com/documentation/xcode/setting-the-next-build-number-for-xcode-cloud-builds).

## Setup verification

All three workflow configurations were read back from Apple's API with required `TEST` and `ARCHIVE` actions and the correct shared schemes. Local icon, privacy-string, and localization preflights passed (741 localized strings), as did the fixture startup, UI endpoint, and shutdown hooks. New Cloud build results are recorded separately after execution.

## Initial three-platform runs — 3 October 2026

The first runs from `9f073cc` completed with failures. Required tests remained enabled, and TestFlight post-actions were skipped after their failures.

| Platform | Run | Archive | Test |
| --- | --- | --- | --- |
| iOS | [70](https://appstoreconnect.apple.com/teams/cbaca10a-f696-4d2b-959e-0d3fa1b23452/xcode-cloud/products/13960BE0-6304-4C11-A080-C67D06BE2E79/builds/cbbaa597-0ec9-4d05-a021-1c4e86955026/summary) | Succeeded | 136 passed, 6 failed |
| macOS | [69](https://appstoreconnect.apple.com/teams/cbaca10a-f696-4d2b-959e-0d3fa1b23452/xcode-cloud/products/13960BE0-6304-4C11-A080-C67D06BE2E79/builds/662a9015-f044-4b9f-93e3-3f13e3aa64da/summary) | Succeeded | App launch failed |
| visionOS | [68](https://appstoreconnect.apple.com/teams/cbaca10a-f696-4d2b-959e-0d3fa1b23452/xcode-cloud/products/13960BE0-6304-4C11-A080-C67D06BE2E79/builds/ce9c0437-61d4-41f0-a0b2-dd2b2b96df37/summary) | Failed during App Store Connect preparation | 132 passed, 3 failed |

- iOS failures were the three localization flows, theme persistence after relaunch, creating a memory, and expanding tool activity. The localization helper searched for an English sign-in label; the relaunch kept the onboarding reset flag; the memory test queried an unlabeled multiline field; the activity test expected a heading absent from the expanded view. The UI branch repairs those selectors, gives multiline schema fields accessible labels, removes the reset flag after fixture sign-in, and checks the expanded fixture output.
- Mac test logs show ad hoc “Sign to Run Locally” signing and launch failures (`RBSRequestErrorDomain` 5 / `NSPOSIXErrorDomain` 163). This app's restricted Keychain access groups need a development signing identity/profile for test execution. Local development-signed Mac builds launch successfully. A successful Cloud distribution archive does not certify Cloud's test app signing. Apple documents that [restricted Keychain access-group claims require an authorizing provisioning profile](https://developer.apple.com/documentation/xcode/creating-distribution-signed-code-for-the-mac). No Keychain entitlements or required tests were removed to hide this failure.
- visionOS test failures were account switching, independent chat selections, and opening Desktop after Terminal. The local UI review reproduced the last failure as overlapping windows; the new placement passed that test locally. The archive compiled and exported, then failed during App Store Connect preparation. Its delivery log also contains an App Store Connect authentication error, but it does not establish a specific server rejection. Account-switch and independent-selection failures still require a passing rerun.

Targeted local runs on the UI branch passed five affected iOS flows (Chinese, Spanish, theme persistence, memory/schedule navigation, and expanded tool activity). Japanese still requires a passing rerun: its sign-in scrolling correction compiled, but simulator installation stalled before the final test executed. The extra three-test visionOS rerun likewise stalled in installation before executing any tests. The completed two-test visionOS native-window run passed. See the [UI review](ui/2026-10-03/README.md) for the exact scope.

These results do not yet certify the workflows for unattended TestFlight delivery. Private signing keys and delivery logs are not committed to the repository.

## Historical iOS validation

The first workflow was created on 17 September 2026. Build 1 from `7273dd7` passed simulator tests and the iOS archive. Build 58 from `b77dc85` later completed archive and TestFlight distribution. These historical results do not certify the new three-platform configuration.

## Distribution repair — 17 September 2026

Cloud builds passed compilation, tests, signing, and IPA export but failed during App Store Connect preparation. Xcode’s `ContentDelivery.log` exposed the actual server rejection for Build 3: **ITMS-90683**, missing `NSCameraUsageDescription`. The prebuilt WebRTC framework references `AVCaptureDevice` and related camera APIs; Apple requires a purpose string even though Homem only receives remote desktop video and does not capture the camera.

`Homem/Info.plist` now includes a truthful camera description. The Cloud post-clone preflight checks that both camera and microphone descriptions are present and nonempty. No camera capture or permission request was added.

Commit `3fd5c51` also changed the 1024px marketing icon to RGB without an alpha channel and added an icon preflight. That packaging correction did not fix the processing rejection; builds 3 and 4 still failed because of the missing camera declaration. Standalone validation and upload succeeded, but those results did not mean Apple’s subsequent processing accepted the app.

The workflow is pinned to Xcode 26.6 (17F113), the installed local toolchain. Its main/pull-request triggers and internal-only TestFlight preparation remain intact. The pin was a diagnostic step before the processing error was identified, not a proven fix. Build 5, started before the camera declaration was added, received the same ITMS-90683 rejection on Xcode 26.6. Its remaining work was canceled after the corrected build started.

The direct upload also warned that the prebuilt WebRTC framework lacks a dSYM (UUID `4C4C4496-5555-3144-A149-A7E882FEE780`). This was not the blocking rejection. No credentials or private delivery logs are stored in this repository.

[Build 6](https://appstoreconnect.apple.com/teams/cbaca10a-f696-4d2b-959e-0d3fa1b23452/xcode-cloud/products/13960BE0-6304-4C11-A080-C67D06BE2E79/builds/9d70dbc7-be88-4334-aadb-bd12fef922f9/summary), from commit `74af148`, passed the simulator test and archive actions. App Store Connect processing completed successfully, confirming the privacy-metadata fix. [TestFlight 1.0.0 (6)](https://appstoreconnect.apple.com/teams/cbaca10a-f696-4d2b-959e-0d3fa1b23452/apps/6812852139/testflight/ios/5e8ae4ea-28f4-4536-b332-0cc0e9b9453c) currently shows **Missing Compliance**. The owner subsequently requested `ITSAppUsesNonExemptEncryption = false`. That Boolean declaration is now included in `Homem/Info.plist` for future uploads; it does not retroactively change Build 6. The replacement build must finish processing before tester availability can be confirmed.

## Standalone macOS update — 3 October 2026

The Mac workflow now tests and archives `HomemMac`, with native Mac test destination `mac` and archive destination `ANY_MAC`. Both actions are required to pass; the App Store eligible archive delivers to the existing **Homem Internal** group. Restricted editing is enabled. The other two workflows retain `Homem` and `HomemVision`, respectively. All three configurations were read back from Apple's API after the update.

The standalone source was pushed directly to `master` as `c443934`, followed by configuration and release evidence in `ef1e667`. Signed local native tests passed **51/51**, and iOS Simulator and arm64 visionOS Simulator builds passed. The native Release archive contains Intel and Apple silicon `MACOS` binaries, with minimum macOS 14. Native build 101 is valid and submitted to App Review with manual release.

UI evidence: [native workflow](ui/2026-10-03-native/06-native-cloud-workflow.png), [build counter](ui/2026-10-03-native/07-cloud-build-counter.png). Release details: [native Mac submission](app-store/NATIVE-MACOS-2026-10-03.md).

### Native workflow execution and remaining blockers

Runs from `ef1e667` started on all three workflows. At 20:49 UTC on 2 October (3 October locally):

| Platform | Run | Archive | Required tests |
| --- | --- | --- | --- |
| macOS | [103](https://appstoreconnect.apple.com/teams/cbaca10a-f696-4d2b-959e-0d3fa1b23452/xcode-cloud/products/13960BE0-6304-4C11-A080-C67D06BE2E79/builds/bc0c2793-9b7e-4c95-a0a4-3a482d170fae/summary) | Succeeded | Test app launch failed |
| iOS | [104](https://appstoreconnect.apple.com/teams/cbaca10a-f696-4d2b-959e-0d3fa1b23452/xcode-cloud/products/13960BE0-6304-4C11-A080-C67D06BE2E79/builds/a2af82ef-9ace-4db5-8863-4faea98a2907/summary) | Compiled/exported; App Store Connect preparation failed | Running |
| visionOS | [102](https://appstoreconnect.apple.com/teams/cbaca10a-f696-4d2b-959e-0d3fa1b23452/xcode-cloud/products/13960BE0-6304-4C11-A080-C67D06BE2E79/builds/629ada0c-aecc-4e1b-88e1-6b62eeaa9a49/summary) | Compiled/exported; App Store Connect preparation failed | Running |

The native Mac worker explicitly invokes `build-for-testing` with `CODE_SIGN_IDENTITY=-` and `AD_HOC_CODE_SIGNING_ALLOWED=YES`. Its required tests cannot launch the app with the restricted shared Keychain entitlement. Reproducing these flags locally, including disabling hardened runtime for the diagnostic run, also failed before tests executed. The crash report identifies `SIGKILL (Code Signature Invalid)` and `Taskgated Invalid Signature`. The same suite previously passed 51/51 with the development certificate and native provisioning profile. [Apple's documented hardened-runtime workaround](https://developer.apple.com/xcode-cloud/release-notes/) did not resolve this case. The shipped app's entitlements and hardened runtime remain enabled, and Cloud's required test action remains enabled. Native Mac archive success and the valid local upload do not certify Cloud test execution or TestFlight delivery.

Both iOS and visionOS App Store export logs show Apple's `Session Proxy Provider` unable to authenticate with App Store Connect. The public issue is “Preparing build for App Store Connect failed.” These logs do not identify an ITMS packaging rejection. API access and the direct native Mac upload succeeded, but they do not repair Apple's worker authentication. These runs therefore do not yet certify unattended three-platform TestFlight delivery. Private delivery logs and crash reports remain outside the repository.

This documentation-only result update uses Apple's [documented `[ci skip]` marker](https://developer.apple.com/documentation/xcode/configuring-start-conditions) to avoid canceling the in-progress simulator tests and rebuilding unchanged application code.
