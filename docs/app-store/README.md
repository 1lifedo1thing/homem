# App Store preparation

Updated 2026-09-18. **Do not submit for review until the review server is ready.**

App: Homem · `ad.neko.homem` · Apple ID `6812852139` · Kitta Ltd

## Saved in App Store Connect

- Version 1.0 remains **Prepare for Submission**; manual release is selected.
- English (U.S.), Simplified Chinese, Japanese, and Spanish (Spain): subtitle, promotional text, description, and keywords. Source copy is in `metadata.json`.
- Primary category Productivity; secondary category Utilities.
- Copyright: 2026 Kitta Ltd.
- The user has supplied the review server URL in review notes. Review username and password fields are still blank as of the screenshot capture pass.
- Five privacy-checked screenshots from the live official service are uploaded to the iPhone 6.5-inch gallery. Source captures, upload exports, and remaining capture work are documented in `screenshots/README.md`.
- Build **18 / 1.0.0** is attached to the draft and was verified after reloading App Store Connect. Replace it with the build containing the workspace/token-usage fixes and share extension when that build is processed.

## Still required before submission

- Working review-server credentials; keep the server available throughout review and verify the final sign-in steps.
- Review contact first/last name, email, and phone number. These were blank and no contact details were invented.
- Public Support URL and Privacy Policy URL. The GitHub repository is private and cannot serve as the public support page. Draft publication copy is provided in `SUPPORT-DRAFT.md` and `PRIVACY-DRAFT.md`.
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
