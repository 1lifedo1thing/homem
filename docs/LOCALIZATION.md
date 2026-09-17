# Localization

Homem uses [L10n-swift](https://github.com/Decybel07/L10n-swift) 5.10.3 through Swift Package Manager. The exact dependency and revision are committed. `AppLocalization` serializes access to the library's resource cache and uses its string lookup and locale-aware formatting. This is also the implementation behind the `.localized` convenience property used by app-owned controls.

Translations live in `Homem/Resources/Localizable.xcstrings`. Xcode compiles this catalog into `.strings` resources supported by L10n-swift. `InfoPlist.xcstrings` translates the system permission prompts. Supported languages are English, Simplified Chinese (`zh-Hans`), Spanish (`es`), and Japanese (`ja`). Selection follows the iOS app language preference; Settings → App language opens the app's system settings.

Localize UI labels and app-generated errors. Use format keys such as `Message %@…` for dynamic text. Do not translate agent/team names, conversation content, file names, tool outputs, server-provided descriptions, identifiers, or request payloads. Advanced API/plugin documentation comes from the server contract and remains as supplied. Literal wire values such as `Connected`, `GET`, or `online` must remain stable in models; localize them only for presentation.

Run `python3 scripts/check-localizations.py` to verify complete coverage in the three translated languages and matching format placeholders. Xcode Cloud runs the same check before archiving. XCTest exercises the compiled library resources; UI tests launch each locale and verify login, agent shortcuts, desktop navigation, and new-chat labels.
