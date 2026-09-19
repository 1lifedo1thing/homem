# iPhone Duo

Build with Xcode 27.1 and its iOS 27.1 SDK to enable the native Duo presentation.

- System tab and navigation bars use the real size class on iOS 27.1, allowing vertical bars on Duo and expanded navigation on its inner display.
- Workspace and agent controls use a centered 32-point avatar in vertical toolbars. Horizontal toolbars retain the avatar and dropdown chevron. Compose remains a separate toolbar item.
- The workspace queries active division regions before crossing its UIKit hosting boundary. Panes avoid the fold, with chat on the lower half in a laptop pose and tools above. Side-by-side folds keep chat and tools on opposite sides.
- Drag a pane by its header grip. Drop near an edge to place it beside, above, or below another pane; the tinted preview shows the destination. A center drop reorders. Edge placement requires at least 300 points of width and 180 points of height per pane. Custom splits support divider resizing and are saved with the workspace. Smaller viewports temporarily use the compact layout, and active folds keep their reserved space.
- Panes lift while dragging and settle with a spring animation. Reduce Motion removes the lift movement and animation. Live divider resizing stays immediate.
- Screen changes update frames without replacing pane IDs or saved arrangements. Unfolding restores the user's arrangement. Keyboard/accessory controls remain within their pane.
- Email/code sign-in uses a content-sized sheet on expanded displays and scrolls above the keyboard on compact displays. Adding an account stays within one sheet, preserving the sign-in step across display changes.
- Layout uses local geometry and system safe areas, with no hard-coded Duo screen dimensions or device-name checks.

`HOMEM_DUO_SDK` is enabled by the SDK condition in `project.yml` for iPhoneOS/iPhoneSimulator 27.1. Older SDKs continue to build using the existing layout. When adopting a newer SDK, extend that condition after checking its APIs. Xcode Cloud must select Xcode 27.1 to include Duo-specific support in a distributed build.

Validation (2026-09-19):

- Built with Xcode 27.1 (27A9269); all eight focused layout tests passed on **iPhone Duo, iOS 27.1 (24A94401)** with no runtime warnings in the test result.
- Tests cover compact/expanded layouts, horizontal and vertical fold exclusion, laptop placement, and restoration after unfolding, directional docking, nested resizing, saved-layout migration, and removal of a docked pane.
- Visually checked the outer display, open inner display, book pose, rotated book pose, and software keyboard using Device Hub. Chat/files and chat/files/terminal layouts stay clear of the fold; the keyboard moves content into the remaining viewport. The unsent draft survived opening the device, and the workspace panes survived closing and reopening.
- Checked centered avatar controls and the workspace/account menu on the folded outer display. Verified horizontal/vertical pane docking and divider resizing with simulator gestures. Checked fitted sign-in, the software keyboard, folding during verification, and cancellation back to account setup.
- Also built with Xcode 27.0 to verify the older-SDK fallback.

Simulator UI checks used the demo workspace. They validate presentation and state continuity, not live remote-desktop or terminal transport.

Apple references: [Prepare your app](https://developer.apple.com/videos/play/tech-talks/111461/), [Adaptive layouts and reserved regions](https://developer.apple.com/videos/play/tech-talks/111463/), [Vertical toolbars](https://developer.apple.com/videos/play/tech-talks/111462/).
