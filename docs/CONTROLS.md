# Native control locations

The old generic operation browser is removed. Each action is bound to the agent, conversation, file, or connection already selected by the user. UUIDs remain request values; reference fields display server-provided names. Boolean fields use toggles, choices use pickers, and structured settings use nested forms.

| In Homem | Controls | Memoh client reference |
|---|---|---|
| Agent → Access & permissions | Default access, rules, workspace members, channel managers, ownership transfer | `bot-access.vue` |
| Agent → Computers | Available computers, default run location, tool approval, disconnect | `bot-remote-runtime.vue` |
| Agent → Connected accounts → Account authorization | Enable, reconnect in browser, refresh authorization status | `bot-apps.vue` / `reauthorize` |
| Agent → Automation | Events, test event, configuration files | `bot-advanced.vue` |
| Conversation → menu → Conversation settings | Rename, summarize, context usage, supported goal actions | `useRuntimeControls.ts`, `chat-pane.vue` |
| Memories → menu | Search; retention and age settings; import and rebuild | `bot-memory.vue` |
| Workspace → Snapshots | Named snapshots, create, confirm restore of a managed version | `bot-container.vue` |
| Files → archive button | Select files to download as an archive; select an archive to extract | Container file manager |
| Working directories → directory → Git branch | Select an existing branch; respects workspace busy state | Workdir branch controls |
| Dependencies → dependency | Preflight, version, install/update/reinstall/rollback, operation progress | `dependency-enable-flow.vue` |
| Installed apps → app | Resume installation, update release | `bot-apps.vue`, `app-actions.ts` |
| MCP connections → transfer button | Import JSON via Files; export with native sharing | `mcp-server-detail.vue` |
| Channels → channel | Enabled toggle, configuration | Channel configuration components |
| Settings → More connections | Linked channels, remote runtimes, speech/transcription/video providers | Shared settings routes |
| Models → provider → Refresh models | Refresh catalog in the selected provider | Provider model controls |

References are in Memoh's `apps/web/src/pages/bots/components` unless a composable or route is named. Request shapes are checked against the bundled schema. These controls do not imply that every backend endpoint has a native screen: protocol callbacks, transports, arbitrary runtime commands, and specialized channel administration are not shown as editable HTTP requests.

Verification: iPhone simulator build, focused record/reference mapping tests, translation validation, and a simulator navigation check. Destructive operations, third-party OAuth completion, and dependency installation still need testing against a suitable server; they were not run against a user's live workspace for this change.
