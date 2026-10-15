# Feature Status

**Last Updated:** 2026-10-15 (stage 2A: window inventory, MRU, SkyLight focus)

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
| Window inventory | dev | Background cache of windows on all Spaces, minimized and hidden apps via ScreenCaptureKit, merged with Accessibility minimized flags. Refreshed on app, Space, hide and AX window events plus a 3 s timer; the Option+Tab path only reads the cache. | ScreenCaptureKit, Accessibility | Needs Screen Recording; without it falls back to current-Space CoreGraphics. Minimized windows on other Spaces show as other desktop. | Sources/Tabby/WindowInventory.swift |
| Inventory rules | dev | Pure filter and merge: layer 0, at least 40 px, regular apps, not Tabby, untitled off-screen junk dropped, hidden-apps list, show-minimized and show-other-desktops toggles. Unit tested. | None | Settings window to change these is not built yet. | Sources/TabbyCore/WindowInventoryRules.swift |
| MRU ordering | dev | Pure most-recently-used order, seeded from z-order at launch, updated by app activation and AX focus events; closed windows drop out. Unit tested. | NSWorkspace, Accessibility | Focus changes need Accessibility; windows never focused keep inventory order after known ones. | Sources/TabbyCore/MRUOrder.swift |
| Row markers | dev | Rows show Minimized or Other desktop tags. | AppKit | Hidden-app windows get no tag. | Sources/Tabby/SwitcherPanel.swift |
| Private API shim | dev | Four private symbols resolved with dlsym at launch; menu status notes basic focus if any is missing. | SkyLight, HIServices | Behaviour on macOS 26 not yet hand-verified. | Sources/Tabby/PrivateAPI.swift |
| Window focus | dev | Unminimizes via Accessibility when reachable, brings the window forward across Spaces with SkyLight, then AXRaise. Falls back to activate plus AXRaise. | Accessibility, SkyLight | Not yet hand-tested; off-Space windows cannot be unminimized via AX. | Sources/Tabby/WindowFocuser.swift |
| Permissions onboarding | dev | First-run window shows Accessibility and Screen Recording status with buttons to the right System Settings pane; polling continues after launch and the key tap starts once Accessibility is granted. | Accessibility, ScreenCaptureKit | Screen Recording is displayed but not used until phase 3. | Sources/Tabby/Permissions.swift |
| Menu bar item | dev | Status item with a live status line, Permissions and Quit. | AppKit | No settings window yet. | Sources/Tabby/AppDelegate.swift |
| Persistent settings | dev | Codable settings with defaults; missing keys, unknown layout and bad data fall back safely. | Foundation | Stored but no UI to change them yet. | Sources/TabbyCore/Settings.swift |
| No-network guard | dev | A unit test scans Sources/ and fails if any networking API name appears. | swift-testing | Name-based scan; cannot catch obfuscated use. | Tests/TabbyCoreTests/NoNetworkTests.swift |
| App bundling | dev | scripts/bundle.sh builds Tabby.app signed with "Flameshot Local"; --install copies to /Applications and relaunches. | codesign | Fails if the signing identity is missing. | scripts/bundle.sh |
| Settings window | stub | Planned for the rest of phase 2: layout, hidden apps, toggles, launch at login. | AppKit | Not started. | None |
| Thumbnails, App Icons layout, hover controls, live preview | stub | Planned for phase 3. | ScreenCaptureKit | Not started. | None |
