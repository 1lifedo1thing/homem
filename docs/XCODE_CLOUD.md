# Xcode Cloud

## Project and source control

- Repository: [iebb/homem](https://github.com/iebb/homem) (private)
- Default branch: `main`
- Project: `Homem.xcodeproj`
- Shared scheme: `Homem`
- Bundle identifier: `ad.neko.homem`
- Apple Developer organization: **Kitta Ltd**
- Team identifier: `7P8CLHDH5G`
- Signing: Automatic

The generated Xcode project and pinned `Package.resolved` are committed. Cloud builds do not require XcodeGen. If project configuration changes locally, run `xcodegen generate` and commit the resulting project alongside `project.yml`.

## Worker preparation

- `ci_post_clone.sh` permits SwiftTerm's pinned version-metadata build plugin in the disposable Xcode Cloud worker. It does not change the local developer's Xcode preferences. Review dependency changes before accepting a new plugin version.
- `ci_pre_xcodebuild.sh` starts the loopback HTTP/SSE/WebSocket fixture during `test-without-building`, waits for readiness, and fails if startup fails.
- `ci_post_xcodebuild.sh` stops that fixture after tests. The fixture script is linked into `ci_scripts` so Apple includes it in the separate test environment.
- Integration tests fail, rather than skip, if the fixture is unavailable in Xcode Cloud. No production credentials or server are needed.

The pre/post hooks and native networking smoke check have passed locally. The app's earlier simulator checks are recorded in [VALIDATION.md](VALIDATION.md).

## Apple-side workflow

**Status: repository preparation complete; Apple-side workflow activation pending.** A repository push alone does not activate Xcode Cloud.

Complete initial onboarding in Xcode's **Integrate → Create Workflow** using the Kitta Ltd team and the Homem scheme. Connect only the `iebb/homem` repository if GitHub asks for repository access, then create the `Homem CI` workflow:

- Start on changes to `main` and pull requests targeting `main`.
- Use the latest stable Xcode and compatible macOS version offered by Xcode Cloud.
- Build and test the Homem scheme on an available iPhone simulator.
- Add an iOS archive action for development builds as needed. App Store/TestFlight distribution requires the corresponding App Store Connect app record and distribution configuration.
- Run the first build and confirm its result in App Store Connect before considering the setup active.

No TestFlight testers, automatic external distribution, App Store submission, paid compute subscription, or export-compliance declaration is configured by these repository scripts.

Apple references: [First workflow](https://developer.apple.com/documentation/xcode/configuring-your-first-xcode-cloud-workflow), [custom build scripts](https://developer.apple.com/documentation/xcode/writing-custom-build-scripts), [Cloud environment variables](https://developer.apple.com/documentation/xcode/environment-variable-reference).
