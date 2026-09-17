# App Store screenshots

Captured 2026-09-18 from the connected iOS app at commit `bd1e73d`, on an iPhone 17 Pro simulator running iOS 26.5. These are real app screens using the official Memoh service, not demo fixtures or generated mockups.

## Files and provenance

- `en-US/*.png`: original Simulator Save Screen captures, 1206 × 2622.
- `iphone-6.5/en-US/*.jpg`: full-screen exports resampled to Apple's accepted 1284 × 2778 size, maximum JPEG quality, without alpha. No UI content was replaced or composited.
- `03-agent-tools`: connected Max agent and workspace tools.
- `04-desktop`: connected remote desktop in view-only mode. A separate private Chromium window shows only Google; the existing browser session was left intact.
- `05-terminal`: live workspace shell running official neofetch. The shell prompt omits username/hostname, and the configuration only prints OS, kernel, uptime, shell, memory, and colors.
- `06-library`: Library navigation, without private memories or schedules.
- `07-supermarket`: public app catalog with loaded service icons.

All five exports were visually checked for credentials, account email, private conversations, hostnames, IP addresses, and private file contents before upload. Only neutral agent/workspace identity and public catalog/system information are visible.

## App Store Connect status

Five iPhone 6.5-inch screenshots are uploaded to the English (U.S.) version 1.0 draft; persistence was verified after reloading. App Store Connect applies this source set to the other iPhone sizes and localizations unless overridden in Media Manager. The version remains **Prepare for Submission**. No review submission was made.

The set is incomplete: slots `01` and `02` are reserved for the review-server chat list and real agent conversation. The review server URL is present in App Store Connect, but its review username and password fields were blank at capture time. Do not capture the official server's private conversations as a substitute. iPad screenshots also remain to be captured.

For the terminal setup, neofetch was unavailable in the workspace package repository, so its script was downloaded from its [official repository](https://github.com/dylanaraps/neofetch) to `/tmp/homem-neofetch`. The privacy-safe configuration is `/tmp/nf.conf`. These are temporary workspace files, not changes to agent instructions or saved account settings.

Apple's accepted upload dimensions: [Screenshot specifications](https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications).
