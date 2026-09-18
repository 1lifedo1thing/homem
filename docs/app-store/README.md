# App Store preparation

Updated 2026-09-18. **Do not submit for review until the review server is ready.**

App: Homem · `ad.neko.homem` · Apple ID `6812852139` · Kitta Ltd

## Saved in App Store Connect

- Version 1.0 remains **Prepare for Submission**; manual release is selected.
- English (U.S.), Simplified Chinese, Japanese, and Spanish (Spain): subtitle, promotional text, description, and keywords. Source copy is in `metadata.json`.
- Promotional text and descriptions now lead with the cloud computer; desktop/terminal access comes before the agent-chat feature. The name, subtitles, keywords, and in-app terminology were not changed in this copy pass.
- Support URL in all four localizations: https://docs.kitta.co/homem/support/
- Privacy Policy URL in all four localizations: https://docs.kitta.co/homem/
- Both public pages are deployed from `kitta-co/privacy-policy` on GitHub Pages (commit `705bb4b`), linked from the docs home page, and use the existing public support contact `support@ieb.app`. Publication copies are in `SUPPORT.md` and `PRIVACY.md`.
- Primary category Productivity; secondary category Utilities.
- Copyright: 2026 Kitta Ltd.
- The user has supplied the review server URL in review notes. Review username and password fields are still blank as of the screenshot capture pass.
- Five privacy-checked screenshots from the live official service are uploaded to the iPhone 6.5-inch gallery. Source captures, upload exports, and remaining capture work are documented in `screenshots/README.md`.
- Build **18 / 1.0.0** is attached to the draft and was verified after reloading App Store Connect. Replace it with the build containing the workspace/token-usage fixes and share extension when that build is processed.

## Still required before submission

- Working review-server credentials; keep the server available throughout review and verify the final sign-in steps.
- Review contact first/last name, email, and phone number. These were blank and no contact details were invented.
- Confirm server-side retention and provider practices before completing/publishing App Privacy answers. The native client has no advertising/tracking/analytics SDK; this does **not** mean that conversations, uploads, or account data sent to the selected server are never collected.
- Finish/verify age rating and content-rights declarations. The age-rating questionnaire was being edited interactively and was left alone.
- Complete review-server chat list/conversation screenshots and iPad screenshots. The official-server captures exclude private chats, credentials, and account details.
- Confirm pricing, territories, and any applicable business/trader information.

## Share extension release check

The application embeds `ad.neko.homem.share`, using the containing app's existing Keychain access group `$(AppIdentifierPrefix)ad.neko.homem`. Automatic signing must provision both targets with the same team and matching build/version numbers. No App Group container or externally shared credentials are required.

After updating, open Homem once so it can publish the saved-account directory to Keychain. Other apps' system share sheets can then choose an account, workspace, and bot. Up to 20 files (50 MB each) are copied locally, streamed to a new `Shared-…` folder under `/data`, and removed from the extension's temporary storage on completion/dismissal. The sheet stays open during uploads; a partial failure can retry only remaining files.

Validation: iPhone simulator build and focused token/date/auth/file regression tests; live official-server token usage; Photos → Share → Homem → Max successfully uploaded the app-icon fixture into `/data/Shared-20260918-0219-062FA7D6`.

No App Store review submission or release was performed.

Implementation references: Apple’s [share-extension activation keys](https://developer.apple.com/library/archive/documentation/General/Reference/InfoPlistKeyReference/Articles/AppExtensionKeys.html) and [extension data-handling guidance](https://developer.apple.com/library/archive/documentation/General/Conceptual/ExtensibilityPG/ExtensionScenarios.html).

## Workspace layouts

The Add pane menu supports additional chats, files, terminals and desktops. Each chat can select its own agent and conversation. Pane menus reorder the added panes; each pane closes independently. Automatic layout uses chat on the left and two tools on the right on iPad, a grid for larger sets, and a vertical split on iPhone. Side-by-side, stacked and grid arrangements are also available; overflowing layouts scroll instead of shrinking panes beyond usability. Automatic two/three-pane dividers remain resizable and accessible. Desktops start in view-only mode.

Workspace content is bounded below the navigation bar. Embedded file browsing and conversation selection use local controls instead of replacing the workspace title. iPad app tabs sit at the bottom, and the chat sidebar has a dedicated title/compose row, separate from the workspace and agent selectors.

Validation: simulator build, two focused geometry tests (all four arrangements, 1–8 panes, narrow/keyboard/iPad sizes), localization coverage, live iPad pane add/remove and two independent real conversations, and iPhone portrait split with the software keyboard. The review server's desktop connection still disconnects; this layout change does not claim to resolve that server connection problem.

The iPhone 17 Pro Max and iPad Pro 13-inch simulators have both authorized official and review accounts. Five MyGO agents with five-star card icons and real conversations are configured on the review server. Temporary credential-transfer test code was removed. App Privacy still needs confirmation of whether Kitta operates or receives data from a Memoh service. App Store review has not been submitted.
