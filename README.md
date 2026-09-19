# Homem

Your Memoh cloud computer, on iPhone and iPad. Built with Swift and SwiftUI.

Connect to [official Memoh](https://app.memoh.net) or your own [Memoh server](https://github.com/felinics/Memoh).

## Features

- Chat with your agents, queue follow-ups, share attachments, and view formatted code and tool activity.
- Browse files, use an interactive terminal, and control your remote desktop—or keep it view-only.
- Arrange chat, terminal, files, and desktop panes together in a flexible workspace.
- Switch between accounts, servers, and workspaces.
- Manage agents, models, memories, schedules, apps, and integrations.

Supports iOS 17+, system appearance, and English, Simplified Chinese, Spanish, and Japanese.

## Get started

Choose **Sign in to Memoh** for email or browser sign-in, **Use another server** for a custom deployment, or **Explore the demo** to try the app locally.

For a custom server, enter its API URL (for example, `https://memoh.example.com/api`) and sign in with your credentials or access token.

## Development

1. Open `Homem.xcodeproj` in Xcode and let Swift packages resolve.
2. Select the **Homem** scheme and an iPhone or iPad simulator, then run.
3. For a physical device, select your signing team. The bundle ID is `ad.neko.homem`.

Project configuration lives in `project.yml`; regenerate changes with `xcodegen generate`. Allow the SwiftTerm package plugin when Xcode prompts.

Run the test suite with its local server fixture:

```sh
bash scripts/test.sh
```

Set `HOMEM_TEST_DESTINATION` to use a different simulator.

## More

[Feature coverage](docs/FEATURES.md) · [Design](docs/DESIGN.md) · [Localization](docs/LOCALIZATION.md) · [Validation](docs/VALIDATION.md) · [Xcode Cloud](docs/XCODE_CLOUD.md)

[Support](https://docs.kitta.co/homem/support/) · [Privacy](https://docs.kitta.co/homem/)

Homem is an independent Memoh client, licensed under [AGPL-3.0](LICENSE). See [third-party notices](THIRD_PARTY_NOTICES.md) for attribution.
