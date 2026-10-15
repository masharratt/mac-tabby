# Feature Status

**Last Updated:** 2026-10-15 (phase 1 scaffold: Titles-list switcher, permissions onboarding, event tap)

## Status Legend

| Token | Meaning |
|-------|---------|
| `prod` | Live, verified, monitored. Real users. |
| `beta` | Feature-complete, under verification. Usable but not trusted. |
| `dev` | In development. Not verifiable end-to-end. |
| `stub` | Scaffold only. Returns placeholder. Not real. |
| `deprecated` | Still present, scheduled for removal. Do not build on. |

## Features

| Feature | Status | Description | Dependencies | Known Limitations | Location |
|---------|--------|-------------|--------------|-------------------|----------|
| Switcher keyboard | dev | Option+Tab arms, Option+Shift+Tab goes backward, arrows move, Return or Option release focuses, Esc cancels; selection wraps. Pure state machine with unit tests. | None | Not yet hand-tested in the running app. | Sources/TabbyCore/SwitcherStateMachine.swift |
| Event tap | dev | Session key tap on its own thread; swallows Option+Tab and keys while open, re-enables after a system timeout, polls modifier state every 25 ms while open. | CoreGraphics, Accessibility | Does nothing while secure input is on. Cmd+Tab is untouched. | Sources/Tabby/KeyEventTap.swift |
| Titles list panel | dev | Non-activating panel on the screen with the mouse, shown after a 100 ms delay so a quick tap switches without flashing. | AppKit | Text only; no thumbnails or icons-only layout yet. | Sources/Tabby/SwitcherPanel.swift |
| Window list (current Space) | dev | Normal on-screen windows from CoreGraphics, front to back, excluding Tabby itself. | CoreGraphics | Current Space only; no minimized or hidden windows; titles blank without Screen Recording. | Sources/Tabby/CoreGraphicsWindowSource.swift |
| Window focus | dev | Raises the chosen window with Accessibility, then activates its app. | Accessibility, AppKit | Windows on other Spaces are not reachable until phase 2. | Sources/Tabby/WindowFocuser.swift |
| Permissions onboarding | dev | First-run window shows Accessibility and Screen Recording status with buttons to the right System Settings pane; polling continues after launch and the key tap starts once Accessibility is granted. | Accessibility, ScreenCaptureKit | Screen Recording is displayed but not used until phase 3. | Sources/Tabby/Permissions.swift |
| Menu bar item | dev | Status item with a live status line, Permissions and Quit. | AppKit | No settings window yet. | Sources/Tabby/AppDelegate.swift |
| Persistent settings | dev | Codable settings with defaults; missing keys, unknown layout and bad data fall back safely. | Foundation | Stored but no UI to change them yet. | Sources/TabbyCore/Settings.swift |
| No-network guard | dev | A unit test scans Sources/ and fails if any networking API name appears. | swift-testing | Name-based scan; cannot catch obfuscated use. | Tests/TabbyCoreTests/NoNetworkTests.swift |
| App bundling | dev | scripts/bundle.sh builds Tabby.app signed with "Flameshot Local"; --install copies to /Applications and relaunches. | codesign | Fails if the signing identity is missing. | scripts/bundle.sh |
| All Spaces, minimized, hidden windows, MRU order | stub | Planned for phase 2 via ScreenCaptureKit and private focus calls. | ScreenCaptureKit | Not started. | None |
| Thumbnails, App Icons layout, hover controls, live preview | stub | Planned for phase 3. | ScreenCaptureKit | Not started. | None |
