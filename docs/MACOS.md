# Homem on Mac

Build the Mac Catalyst app with the `HomemCatalyst` scheme in Xcode, or run `bash scripts/build-catalyst.sh`. It shares the API, accounts, chats, agent tools, and workspace route model with the iOS and visionOS targets. On Mac, chats use a wide sidebar; **New window** opens a separate chat, files, terminal, or desktop window. The menu is available in chats and agent workspaces.

The Mac App Store version uses the same bundle ID, `ad.neko.homem`, as iOS and visionOS. All targets use the `7P8CLHDH5G.ad.neko.homem` Keychain access group. Saved-account credentials, official sessions, and the account directory are synchronizable Keychain items. When iCloud Keychain is enabled under the same Apple Account, another device can restore a synced account without entering its credentials again. The client checks for newly arrived items when its window becomes active and during the first moments after launch. A server may still require sign-in again if a token or cookie expires.

The Mac app and share extension use App Sandbox entitlements. The app permits outgoing server connections, incoming WebRTC traffic, microphone recording, and user-selected files; the share extension permits outgoing connections and user-selected files. iOS and visionOS continue to use their own entitlement files.

Existing device-only credentials migrate when read: Homem copies each item to the synchronizable Keychain before removing the local original. Draft messages and other in-progress text remain device-only. Removing a saved account removes its synced credential and listing, so the removal propagates to devices using iCloud Keychain.

Mac App Store screenshots are under `docs/app-store/screenshots/mac/en-US/`. Their source captures come from the running Mac app connected to the local review fixture. The upload JPEGs are 1440 × 900, have no alpha channel, and preserve the captured interface inside a padded 16:10 canvas.
