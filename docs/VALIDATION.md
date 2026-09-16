# Validation record

Implementation baseline: Memoh `51bb2073d8d99c961ce9f23555e8fb3bdd2aadc4`, inspected on 17 September 2026. Toolchain: Xcode 26.6, Swift 6.3.3 in Swift 5 language mode. Deployment target: iOS 17.0. App identifier: `ad.neko.homem`.

## Completed checks

- iPhone simulator Debug build succeeded with the pinned SwiftTerm and WebRTC packages.
- Final rebuilt app passed Xcode bundle validation with `ad.neko.homem` and all license resources present.
- `TestResults/FinalCore.xcresult`: **15 tests passed, zero failures, zero skips** — 10 core tests, three networking tests, and two real HTTP/SSE/WebSocket integration tests on iPhone 17 Pro / iOS 26.5. This run includes the final streaming fix.
- `TestResults/Second.xcresult`: **14 tests passed, zero failures** — 12 core/network tests and two native UI flows on iPhone 17 Pro / iOS 26.5.
- The UI flows sent a demo message, opened the agent workspace and its text editor, created a memory, and navigated provider settings. The attached screenshots were exported and visually inspected.
- A native URLSession probe reproduced Swift's removal of empty lines by `AsyncBytes.lines`. The corrected byte parser then successfully decoded all three SSE progress/completion frames from the local fixture. A regression test covers LF, CRLF, CR, and multibyte text.
- `bash scripts/wire-smoke.sh` passed using the unchanged app networking/runtime source compiled for macOS: real HTTP authentication and bot listing, SSE progress/completion, and WebSocket admission, snapshots, deltas, history reconciliation, and duplicate suppression.

Screenshots from the passing UI run:

| Agents | Chat | Memory creation |
|---|---|---|
| ![Agents](screenshots/agents.png) | ![Chat](screenshots/native-chat.png) | ![Memory](screenshots/created-memory.png) |

## Reproduce

Run `bash scripts/test.sh` from the project root, setting `HOMEM_TEST_DESTINATION` to an installed iOS simulator if needed. This starts the loopback fixture and runs the XCTest targets. Result bundles are local build artifacts and are excluded from source control.

For a simulator-independent transport check on the Mac, start `python3 scripts/fixture-server.py`, then run `bash scripts/wire-smoke.sh`. This compiles the app's actual `APIClient`, `ChatModel`, runtime reducer, and JSON types without substituting a mock transport. The fixture itself is a small contract test server, not Memoh.

## Verification limits

- No real Memoh server, account, model provider, container, or OAuth registration was supplied. Local fixture results establish client transport behavior, not end-to-end compatibility with every deployment.
- An intermediate expanded simulator run became unresponsive during UI automation and was stopped. Its wire tests had skipped after a two-second fixture startup timeout. The subsequent final core run used a longer allowance and passed both wire tests without skips. The additional onboarding screenshot test in the expanded UI suite has not completed successfully and is not included in the passing count.
- iPad uses adaptive layouts and is included in the target. A separate iPad simulator launch could not be completed reliably on this host; its layout is not claimed as visually verified.
- Physical-device signing, device installation, TestFlight/App Store submission, accessibility audit, and testing on the oldest supported OS remain release checks.
- See [FEATURES.md](FEATURES.md) for the explicit limits on desktop parity, specialized renderers, provider authentication, backup import, and background behavior.
