# App Store screenshots

Captured 2026-09-18 from the live iOS app, including the dynamic workspace/navigation changes in `47ff53d` and the terminal heartbeat/keyboard follow-up. These are native Simulator Save Screen captures, not generated mockups. No UI content was replaced or composited.

## Current sets

- `iphone-6.9/en-US/*.png`: iPhone 17 Pro Max captures at 1320 × 2868; ten selected for the current gallery.
- `ipad-13/en-US/*.png`: iPad Pro 13-inch M5 landscape captures at 2752 × 2064; eight currently selected in App Store Connect.
- Each platform's `upload/*.jpg`: maximum-quality JPEG exports at the original dimensions, without alpha.
- Earlier `en-US` and `iphone-6.5` files preserve the previous five-screen set.

The selected screenshots cover the chat list, real conversations, a real file-writing task with formatted code, MyGO agents, workspace tools, connected desktop, live terminal, and Library. The iPhone gallery adds chat + terminal and two independent chats. The iPad set also shows two independent real conversations side by side. Models and Supermarket are excluded from both live galleries; their previous local captures remain archived here.

Chats and MyGO agents use the authorized review server. Other screens use the official Memoh service. Private official-server chats, credentials, account email, IP addresses and private file contents are excluded. Public agent icons and provider display names remain visible.

The remote desktop is connected in view-only mode, showing only Google in a separate Chromium window. The terminal runs official neofetch with a neutral prompt and only OS, kernel, uptime, shell, memory and colors. No username or hostname is shown. Its connection remained usable after several minutes idle following the heartbeat fix.

## App Store Connect

Ten screenshots are uploaded to the English (U.S.) iPhone 6.9-inch gallery; the 13-inch iPad gallery currently has eight. The iPhone version page confirms ten with the first three ordered as chat list, conversation, and chat + terminal. The earlier iPhone 6.5-inch override was removed so it inherits the updated 6.9-inch chat and feature gallery. Other sizes/localizations use Apple's fallback unless overridden.

The version remains Prepare for Submission. No review submission was made. App Privacy, review contact details, saving the supplied review credentials, and selecting a current processed build remain release checks; see `../README.md`.

## Sources

MyGO icon provenance and review fixtures are documented in `../REVIEW-FIXTURES.md`. Neofetch came from its [official repository](https://github.com/dylanaraps/neofetch); the temporary workspace files are `/tmp/homem-neofetch` and `/tmp/nf.conf`.

## Follow-up captures

`09-chat-terminal` and `10-dual-chats` were captured from the review server after the composer/safe-area color fix, pane-local terminal key strip, and embedded progress-indicator hang fix (`454d41a`). Both show real responses. The terminal uses a neutral prompt and neofetch without username, hostname, IP or network details. No screenshot text was replaced.
