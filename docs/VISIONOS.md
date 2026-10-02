# Homem on Apple Vision Pro

Choose the **HomemVision** scheme in `Homem.xcodeproj`. It builds a native visionOS app from the same `Homem` sources as iPhone, iPad, and Mac Catalyst. Minimum system version is **visionOS 26.0**, matching the native WebRTC binary. The separate iOS share extension remains part of the iOS target only.

## Signing in

The welcome screen reuses Homem's app artwork and offers Memoh sign-in or a custom server. Demo mode and its sample data have been removed from the application. A connected account is required.

On visionOS, email and authenticator-code entry use a stable 560 × 660-point panel. Finishing six digits does not submit a code, and typing Return does not send a sign-in email. Press **Send sign-in code** or **Verify and continue** explicitly; fields do not automatically grab focus after a network response. Larger native controls, 20-point spacing between form controls, and neutral secondary buttons separate the actions. The resend countdown keeps a fixed layout.

Custom-server login opens a separate navigation screen. Inputs and authentication-method changes are disabled while connecting, rapid taps cannot start duplicate requests, and leaving the screen cancels its pending connection. Adding an account uses the same stable panel dimensions.

Control sizing and spacing follow Apple's [spatial input guidance](https://developer.apple.com/videos/play/wwdc2023/10073/) and [spatial interface guidance](https://developer.apple.com/videos/play/wwdc2023/10076/). Actual eye/hand targeting still needs physical-headset verification.

## Using native windows

- The main window is a launcher. Selecting or creating a conversation opens a separate native window. The system tab ornament switches the launcher between Chats, Agents, Library, and Settings.
- **New window** opens Chat, Files, Terminal, or Desktop in its own resizable spatial window. Agent and Workspace tool shortcuts also open native windows. A new Terminal window starts a separate shell.
- visionOS has no conversation sidebar/detail split, split-pane controls, embedded tool panes, or pane dividers. Saved split layouts from earlier builds are ignored on visionOS, including their terminal and desktop connections.
- Window position and size use the system's window controls. New windows open in front of the workspace with a small depth offset, keeping the active content in view; people can then arrange them in space. Each window keeps its own conversation; opening another chat leaves existing windows in place.
- Each chat or tool window keeps its original account and workspace connection. Switching accounts or workspaces in the launcher leaves existing windows, drafts, and live connections in place. Windows opened from an existing window use that window's account, and the title bar identifies its account.
- Restored windows resolve their own saved credentials without changing the launcher's account selection. Removing or signing out of an account disconnects that account's windows; other accounts remain connected. Windows never silently access the same agent or conversation identifier under another account.
- Account removal also promptly cancels its active operation streams, including streams waiting for more progress. Signed-out clients cannot open new connections. Closing a window cancels pending chat, terminal, and runtime-desktop connection setup.

## Spatial interface and shared implementation

The visionOS interface uses system window glass, native tab and toolbar treatments, gaze feedback, and larger controls. The launcher defaults to 900 × 720 points; chat and tool windows default to 960 × 720, with a 640 × 480 minimum. The terminal uses 18-point monospaced text and larger shortcut keys. Appearance follows visionOS; accent-color and language choices are shared with the existing app.

`SpatialWorkspace.swift` defines the scene routes and thin wrappers around existing chat, file, terminal, and desktop views. `AppStore.chatWorkspace(for:windowID:)` scopes conversation state by account, agent, and scene. Window restoration values omit pending messages and attachments. Newly created chats receive their initial message through a one-time, account-bound in-memory handoff, so restoring a window cannot replay it. iOS and iPadOS retain their existing sidebar and split-pane behavior.

API, account, chat runtime, queue, file editor, terminal, RFB transport, WebRTC signaling, and video rendering remain shared. The iOS WebRTC package has no visionOS slice, so the visionOS target pins LiveKit's **standalone** WebRTC framework at 150.7871.02. `SpatialWebRTC.swift` maps its prefixed symbols to the existing transport; no LiveKit server or signaling service is introduced. visionOS uses spatial desktop windows instead of Picture in Picture. Backgrounded or closed terminal and desktop views release their connections. The visionOS target uses `Info-Vision.plist` without the background audio mode; the iOS target retains its separate `Info.plist` for iOS Picture in Picture.

The layered app icon reuses the existing face, handset, and sunset SVGs as 1024 × 1024 PNGs with explicit 2× scale metadata. Run `bash scripts/render-vision-icon.sh` after editing the artwork (requires `rsvg-convert`). The project preflight checks the layer sizes and scale metadata required by App Store Connect.

## Verification

```sh
xcodegen generate
xcodebuild -project Homem.xcodeproj -scheme HomemVision \
  -destination 'generic/platform=visionOS' -configuration Release \
  -derivedDataPath build -skipPackagePluginValidation CODE_SIGNING_ALLOWED=NO build
bash scripts/test-vision.sh
```

The test script starts the existing local Memoh fixture and runs the shared unit/integration tests plus visionOS UI flows. It requires an installed Apple Vision Pro simulator; override `HOMEM_VISION_TEST_DESTINATION` to choose a specific simulator.

Physical-headset verification should cover eye/hand targeting, remote desktop drag and scroll, hardware keyboard input, microphone recording, reconnecting after sleep, and several simultaneously active windows. Simulator tests and a device build do not establish headset frame rate or sustained memory/thermal performance.

The visionOS 27 simulator emits SwiftUI `SceneStorage` runtime warnings when opening a value-based window. Full system restoration after terminating the app still needs headset verification. See [the validation record](VALIDATION.md) for exact results and simulator limitations.

Design references: [Apple's spatial layout guidance](https://developer.apple.com/design/human-interface-guidelines/spatial-layout/), [SwiftUI windows on visionOS](https://developer.apple.com/documentation/visionos/creating-a-new-swiftui-window-in-visionos).
