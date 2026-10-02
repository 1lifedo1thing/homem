# Standalone Mac UI — 3 October 2026

The `HomemMac` target uses SwiftUI and AppKit on macOS 14+. The executable's `LC_BUILD_VERSION` platform is **MACOS**, for both Apple silicon and Intel. The native target excludes the UIKit feature shell and the iOS share extension.

## UI verification

- Native sidebar selection opens Chats, Agents, and Library reliably.
- The compact unified toolbar provides agent switching, compose, split arrangements, and separate windows.
- Side-by-side chat and native file tables use draggable system dividers. New splits receive an even initial allocation of the available workspace.
- The file browser opens a native editor with Save, Preview, and unsaved-change protection.
- Native agent edits send the schema-defined `PUT /bots/{id}` operation; the HTTP fixture confirmed the update and refresh.
- Sending with ⌘Return reached the shared WebSocket transport and loaded the resulting history. The shortcut belongs to the focused composer.
- ⌘⇧F and ⌘⇧D opened independent account-scoped tool windows; the native Files window was moved from the BenQ display to the built-in Retina display, while the main workspace stayed on the external display.
- Saved sign-in survives app relaunch.

## Checks

51 signed native Mac tests passed with no failures, covering Keychain update/migration/deletion, account and window isolation, workspace restoration, chat queues, formatting, model catalogs, official login, and RFB protocol transport. iOS Simulator and arm64 visionOS Simulator builds passed. Icon, privacy-string, and existing localization preflights passed.

The visionOS prebuilt WebRTC simulator framework supports arm64; the generic simulator check therefore specifies that architecture. Live production WebRTC/terminal interaction and physical iCloud Keychain propagation were not exercised by the local fixture.

Cloud's native Mac archive succeeded, but its ad hoc test signing prevents the app from launching with the shared Keychain entitlement. A local reproduction confirmed an invalid-signature termination; the development-signed 51-test run remains the completed test result. See [Cloud diagnostics](../../XCODE_CLOUD.md#native-workflow-execution-and-remaining-blockers).

## Captures

These are captures of the running native Mac app, with fictional sample data from the local review fixture. They retain the system window-sharing indicator shown during automated capture. App Store JPEGs preserve the interface within a 1440 × 900 canvas.

After capture, the native app and fixture server were stopped. The temporary loopback fixture account was removed from the synchronized Keychain directory and local account preferences; other saved accounts were preserved.

| Capture | View |
| --- | --- |
| [Chat](01-chat.png) | Sidebar, transcript, native compact composer |
| [Split workspace](02-split-files.png) | Chat beside the native file browser |
| [File editor](03-file-editor.png) | Native editor and preview controls |
| [Agents](04-agents.png) | Agent list and native grouped settings |
| [Independent window](05-independent-window.png) | Files window on the other physical display |
