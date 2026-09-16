# Desktop feature coverage

Audited against `apps/desktop`, the shared `apps/web` routes/components, and `spec/swagger.json` at Memoh commit `51bb2073d8d99c961ce9f23555e8fb3bdd2aadc4`.

“Implemented” describes client code and reachable UI, not a claim that every operation has been exercised against a deployed Memoh server.

| Desktop area | Native implementation | Additional controls |
|---|---|---|
| Server connection and login | API-base URL, username/password or token, Keychain, refresh, expired-session recovery | Cloud-specific login extensions are not included in the OSS contract |
| Agent management | List/create/edit/pause/resume/delete, health, usage, settings, access | Ownership, ACL rules, hooks, connectors and workspace target policies use advanced forms |
| Chat sessions | List/page/create/rename/delete, Markdown/code, history, attachments, reasoning/model choices | ACP session configuration and runtime commands use session controls |
| Live chat | WebSocket admission, stable invocation IDs, snapshot/delta sequencing, reconnect, resend, abort | Foreground sockets reconnect after app suspension; server work continues independently |
| Interactive decisions | Tool approval options, agent questions, single/multiple choices and free text | Server permissions govern whether the user can respond |
| Message operations | Retry, edit, fork when server marks the turn forkable, queue follow-up/steer | Queue inspect/edit/reorder/delete and goals use session controls |
| Voice | Microphone recording as audio attachment, native read-aloud; provider/model configuration | The backend must support the selected input modality; recording stops when leaving chat |
| Memory | List/add/edit/delete, semantic search form, topic graph, usage, compact | Rebuild/ingest/status use advanced forms; graph displays at most 60 visual nodes and lists all topics |
| Schedules | Create/edit/delete, enabled flag, cron pattern, agent/model/reasoning/session/workdir settings, logs | Uses the server’s scheduler; no local iOS scheduling substitute |
| Files | Navigate/create/read/edit/preview/rename/delete, import/export/share | Archive/extract forms; file writes use `expectedRevision`; explicit discard confirmation |
| Terminal | SwiftTerm ANSI/VT terminal, binary input/output, resize, reconnect | Requires a running workspace; no shell is executed on iOS |
| Desktop | Native WebRTC video and data channel, prepare progress, pointer drag/click, scroll, right-click, text and control keys | Requires display-enabled runtime and working ICE/network reachability; no browser-engine embedding |
| Workspace lifecycle | Create/start/stop, metrics, workdirs, snapshot list/create/rollback | Runtime-specific options, remote targets and data restore use advanced forms |
| Dependencies and apps | Inspect/manage dependencies, app catalogue/detail/install with immutable revision, streamed operation progress | Preflight/install/update/rollback/resume and connector auth use advanced forms |
| Channels | Discover adapters and edit native fields from their config schema, enable/disable | Adapter-specific QR login, send actions, webhook endpoints and routing use advanced forms |
| MCP | CRUD, probe, OAuth authorization through system browser, status | Provider must accept the `homem://oauth/mcp/callback` redirect; discovery/client setup/import/export use advanced forms |
| Providers and models | CRUD, connection tests, OAuth/device-code sign-in and status | Import models and provider-specific settings use advanced forms |
| Email/voice/video/search/memory services | Provider/model configuration and bindings | Browser OAuth callback handling depends on provider/server configuration |
| People and profile | Admin-only people entry, user access, profile/password | Backend remains the permission authority |
| Backups | Export/share ZIP with optional passphrase; import ZIP as a new agent | Selective overwrite/merge import is not exposed as a dedicated flow |
| Appearance and navigation | iPhone navigation, iPad conversation split view, adaptive agent grid, system/light/dark colors, Dynamic Type and SF Symbols | Desktop window docking, tray, OS-specific hotkeys, updater and CLI installation do not apply to iOS |

## Deliberate limits and release checks

- This implementation has no APNs service, background chat execution, Home Screen widgets, share extension, or offline server-data cache. Server work keeps running while the iOS app is suspended.
- Rich Markdown text and fenced code render natively. Mermaid diagrams, KaTeX equations, interactive HTML artifacts, and desktop-style patch editors are not rendered as their desktop widgets. Diffs are readable as text.
- Attachments are limited to five files of 10 MB each in the composer. Workspace uploads are limited to 50 MB. Downloads/backups currently buffer the response in memory; very large workspaces should use server-side backup tooling.
- Demo mode is clearly labeled, has in-memory sample data, and explicitly rejects unavailable remote actions. It never silently substitutes sample data after a server error.
- Provider-specific Cloud authentication, OAuth registrations, QR logins, actual model responses, external channel delivery, container lifecycle, terminal sessions, WebRTC connectivity and backup round trips still require testing against the intended server. No server credentials were supplied during implementation.
- Full desktop parity is therefore **not certified**. The API coverage is broad, but the specialized desktop renderers and workflows listed above remain limits. Review these before treating this as an App Store release.
