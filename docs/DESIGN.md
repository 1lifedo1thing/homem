# Homem design language

Flighty is the reference for hierarchy and restraint. Study its [published app screenshots](https://apps.apple.com/us/app/flighty-live-flight-tracker/id1358823008) and [product detail screens](https://flighty.com/), especially how a small identity, a primary fact, and supporting status fit together. These observations are translated to an agent client; Flighty's brand artwork and flight-specific metaphors are not assets for Homem.

## Principles in the native app

Lead with the thing the user came to read or do. In Chats, that is the conversation title. In New Chat, it is the message, with the receiving agent and run location close by. In a workspace, it is access to files, terminal, and desktop. Keep repeated workspace and agent context compact.

Use typography and alignment to distinguish information before adding containers. Conversation history is a flat list with separators. A surface groups related controls or a complete agent summary. Avoid stacking a card around every label, decorative counters, marketing headlines, or oversized repeated avatars.

Show the configured identity. Bot and team `avatar_url` images remain intact across toolbar controls, selection panels, and detail screens. A missing image gets a neutral monogram or a workspace symbol. Never infer a mascot from a person's name. Status is a small labeled dot, with color used only where the state warrants it; user-selected accent colors identify actions and selections.

Keep the platform's behavior. The agent selector is a toolbar-anchored popover with real avatars and a selected checkmark. Dismissal, destructive alerts, keyboard avoidance, navigation, and sheets remain native. Labels must stay readable at larger type sizes; tool groups stack when horizontal space is insufficient.

## Shared implementation

| Element | Treatment |
|---|---|
| Canvas | `Theme.canvas`: system background, follows appearance |
| Related controls | `DetailSurface`: secondary background, subtle border, 16-point corner radius |
| Page inset | `Theme.gutter`: 20 points |
| Main value | Semibold/bold system text; larger type reserved for the current identity |
| Metadata | Caption-sized secondary text; monospaced digits for dates and counts |
| Short section label | `Eyebrow`, used sparingly for context |
| Identity image | `AgentAvatar`: real image, clipped consistently, neutral fallback |
| State | `StatusIndicator`: labeled dot; no decorative badge collection |
| Selection | User's accent, checkmark, and accessibility value |

Use these patterns across future screens. Verify light and dark appearance, long names, keyboard-visible composition, and iPhone/iPad layouts with actual screen captures before release.
