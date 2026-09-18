# App Store screenshots

Captured 2026-09-18 from the live iOS app, including the dynamic workspace/navigation changes in `47ff53d` and the terminal heartbeat/keyboard follow-up. These are native Simulator Save Screen captures, not generated mockups. No UI content was replaced or composited.

## Current sets

- `iphone-6.9/en-US/*.png`: ten iPhone 17 Pro Max captures at 1320 × 2868.
- `ipad-13/en-US/*.png`: ten iPad Pro 13-inch M5 landscape captures at 2752 × 2064.
- Each platform's `upload/*.jpg`: maximum-quality JPEG exports at the original dimensions, without alpha.
- Earlier `en-US` and `iphone-6.5` files preserve the previous five-screen set.

The current sets cover the chat list, real conversations, a real file-writing task with formatted code, MyGO agents, workspace tools, connected desktop, live terminal, Library, Supermarket, and grouped models. The iPad set also shows two independent real conversations side by side.

Chats and MyGO agents use the authorized review server. Other screens use the official Memoh service. Private official-server chats, credentials, account email, IP addresses and private file contents are excluded. Public agent icons and provider display names remain visible.

The remote desktop is connected in view-only mode, showing only Google in a separate Chromium window. The terminal runs official neofetch with a neutral prompt and only OS, kernel, uptime, shell, memory and colors. No username or hostname is shown. Its connection remained usable after several minutes idle following the heartbeat fix.

## App Store Connect

Ten screenshots are uploaded to the English (U.S.) iPhone 6.9-inch gallery and ten to the 13-inch iPad gallery. Both counts were verified after reloading the version draft and reopening Media Manager. The first screens show real review-server chats; the iPad gallery also leads with the multiple-chat layout and agent grid. The earlier five iPhone 6.5-inch assets remain as a separate size override. Other sizes/localizations use Apple's fallback unless overridden.

The version remains Prepare for Submission. No review submission was made. App Privacy, review contact details, saving the supplied review credentials, and selecting a current processed build remain release checks; see `../README.md`.

## Sources

MyGO icon provenance and review fixtures are documented in `../REVIEW-FIXTURES.md`. Neofetch came from its [official repository](https://github.com/dylanaraps/neofetch); the temporary workspace files are `/tmp/homem-neofetch` and `/tmp/nf.conf`.
