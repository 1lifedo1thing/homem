# Login and connected-app UI fixtures

Run `python3 scripts/fixture-server.py` before UI tests, or use `scripts/test.sh` / `scripts/test-vision.sh`, which own and stop their fixture process.

`Runner/FixtureLogin.swift` signs in through the real custom-server UI at `http://127.0.0.1:18765/ui-api`. Sample agents, conversations, and files live in `scripts/ui_fixture.py`, outside the application bundle. Chat replies use the existing loopback WebSocket fixture and the production chat transport. There is no demo client, demo mode, or simulated reply path in the app.

Official email/MFA UI tests opt into `HOMEM_OFFICIAL_LOGIN_FIXTURE=1`. `App/OfficialLoginFixture.swift` routes only that client's requests to the same loopback fixture. Its entire implementation is guarded by `#if DEBUG` and is absent from Release builds. Tests do not send sign-in emails or authenticate production accounts. Unit tests continue to inject their own URLSession stubs.

The fixture server resets between UI tests. Run UI tests serially, as the test scripts already do.
