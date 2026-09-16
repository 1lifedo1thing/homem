# Homem

A native Swift / SwiftUI iPhone and iPad client for [Memoh](https://github.com/felinics/Memoh).

**Bundle identifier:** `ad.neko.homem`  
**Deployment target:** iOS 17.0+  
**API baseline:** Memoh commit `51bb2073d8d99c961ce9f23555e8fb3bdd2aadc4`

Homem connects to an existing Memoh backend. It does not run an agent or a container on the phone. The interface uses SwiftUI and UIKit, SwiftTerm for the interactive terminal, and native WebRTC for the remote desktop. There is no web-app wrapper.

## Run

1. Open `Homem.xcodeproj` in Xcode. Swift Package Manager resolves the pinned SwiftTerm and WebRTC packages.
2. Select the **Homem** scheme and an iPhone or iPad simulator, then Run.
3. On a physical device, choose your Apple signing team under Signing & Capabilities. The bundle identifier is already configured.
4. Connect a server, or choose **Explore the demo**. Demo changes are local to the current app session and never contact a server.

Enter the complete **API base URL**, including any reverse-proxy prefix:

- Web/reverse proxy: `https://memoh.example.com/api`
- Direct backend: `http://192.168.1.20:8080`
- Simulator with a backend on the Mac: `http://127.0.0.1:8080`

Use your Memoh username/password or an existing access token. JWTs and conversation drafts are kept in the device Keychain. Passwords are not persisted. Signing out removes the token and drafts for that server. Plain HTTP is supported for self-hosted networks; the connection screen explicitly identifies it.

## Features

- **Conversations:** session creation, history pagination, rename/delete, native Markdown and code blocks, live runtime snapshots/deltas, reconnect and replay recovery, model/reasoning choices, attachments, voice recordings, local read-aloud, retry/edit/fork, abort, approval decisions, agent questions, follow-up and steer queues.
- **Agents:** create/edit/pause/delete, model and behavior settings, native and external agent runtime configuration, permissions, health checks, usage, compaction logs, and backups.
- **Workspace:** directories and files, text/Markdown editing with revision conflict protection, upload/download/share, rename/delete, archive controls, native interactive terminal, native WebRTC desktop with pointer/drag/scroll/keyboard input, workspace lifecycle, snapshots, workdirs, dependencies.
- **Memory and scheduling:** memory CRUD and semantic search, native memory graph, compaction/status/usage, schedule configuration and execution history.
- **Integrations:** channels with adapter-provided native credential fields, MCP, OAuth/device authorization, skills, email bindings, installed apps, Supermarket discovery and installation with streamed progress.
- **Server management:** providers/models, memory/search/fetch/email providers, speech/transcription/video models, remote runtimes, people, profile/password, system/light/dark appearance.
- **Advanced controls:** native request forms generated from the bundled OpenAPI contract expose all 352 documented operations. Long-lived chat, terminal, desktop, file, backup, and activity transports use their dedicated screens; the advanced browser does not substitute for those transports. Less common workflows use these forms and structured results rather than bespoke screens.

See [feature coverage and limits](docs/FEATURES.md) for the distinction between dedicated interfaces, advanced controls, and unverified server-dependent behavior.

## Build and test

The checked-in Xcode project is generated from `project.yml`. Regenerate after changing project configuration or adding source files:

```sh
xcodegen generate
xcodebuild -project Homem.xcodeproj -scheme Homem \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath build -skipPackagePluginValidation build
```

SwiftTerm 1.20 includes a build tool plugin that generates its version metadata. In Xcode, allow that package plugin when prompted. The command above permits its execution for automated builds.

Run tests, including a local HTTP/WebSocket/SSE protocol fixture:

```sh
HOMEM_TEST_DESTINATION='platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' bash scripts/test.sh
```

Or start `python3 scripts/fixture-server.py` separately and run tests from Xcode. Wire integration tests explicitly skip when this fixture is unavailable. The fixture binds only to `127.0.0.1:18765`, uses disposable test credentials, and is **not** a substitute for a real Memoh deployment. Unit tests use URLProtocol to test error and token-refresh behavior. UI tests exercise the running native app and attach screenshots to the `.xcresult`.

With the fixture running, `bash scripts/wire-smoke.sh` also checks the app's actual HTTP, SSE, and WebSocket code directly on macOS without launching a simulator.

Tested builds and remaining verification are recorded in [VALIDATION.md](docs/VALIDATION.md).

## Source layout

| Directory | Responsibility |
|---|---|
| `Homem/App` | App lifecycle, connection flow, navigation, appearance |
| `Homem/Core` | HTTP/Keychain, runtime reducer, demo service, JSON/schema contract, voice |
| `Homem/Features` | Native chat, agents, integrations, workspace, terminal, desktop, management |
| `Homem/Resources` | App icon, privacy manifest, pinned upstream API contract |
| `HomemTests` | Reducer, schema, networking, and live local transport tests |
| `HomemUITests` | Native simulator flows and screenshots |

## License and attribution

Homem is an independent client, not an official Memoh distribution. This project is distributed under AGPL-3.0, with the Memoh API schema attributed to MemohAI. See [LICENSE](LICENSE) and [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
