# Contributing

Thanks for helping make file selection on macOS less tedious.

The native app under `app/` is the primary product. `standalone/` and `scripts/` are earlier prototypes with separate compatibility contracts.

## Change the native app

The product moment is fixed: a user opens a file picker from WeChat, Mail, or another app; MacList appears on that picker without a launcher hotkey or application switch.

Native changes must preserve these boundaries:

- keep `hostPID`, `dialogOwnerPID`, runtime event target, and session generation separate;
- never use application activation/deactivation, Finder launch, clipboard injection, AppleScript, recipient selection, or automatic Send;
- classify only focused, visible, high-confidence file dialogs;
- cancel stale work when the dialog closes or changes;
- keep the preview select-only until live compatibility evidence supports final auto-confirmation;
- never bypass macOS TCC.

Run the no-UI gate:

```bash
./app/Scripts/verify.sh
```

The script runs framework-free logic tests, runs XCTest when full Xcode is present, builds and signs a local app bundle, and performs command-line diagnostics. It must not launch `MacList.app` or `DialogHarness.app`.

Any visible test requires deliberate local consent. Record the macOS version, host app version, dialog kind, expected file, failure stage, and whether focus or Space changed. Never commit personal paths or screenshots.

## Change the standalone prototype

Standalone changes must stay limited to roots explicitly supplied by the user and must not read document contents.

```bash
swift test --package-path standalone
./standalone/smoke-test.sh
```

Document every new persisted field, permission, dependency, or platform API.

## Change a legacy Cling action

Keep the existing rollback contract and test in no-UI mode:

```bash
MACLIST_TEST_NO_UI=1 ./test.sh
```

Do not distribute Cling binaries or copy GPL source into the MIT native app.

## Change README media or the Dashboard

- Use only synthetic filenames and project names.
- Never capture a real desktop, account, chat, recipient, email address, client name, or local path.
- Dashboard HTML follows the Apple/macOS Light Mode system in `DESIGN.md`.
- Do not present the old Cling demo as evidence for the native file-picker flow.

## Pull-request checklist

- [ ] The primary upload-window flow is unchanged or explicitly justified.
- [ ] Native smoke tests and release build pass without launching UI.
- [ ] Full XCTest passes on a complete Xcode runner.
- [ ] No app switching, Finder, clipboard, AppleScript, automatic Send, or hidden network path was added.
- [ ] Dialog PID ownership, focus, visibility, cancellation, and stale-element behavior are covered.
- [ ] Save/folder/unknown dialogs cannot be auto-submitted.
- [ ] Real-app compatibility claims include reproducible live evidence.
- [ ] Markdown links, YAML, sensitive-data scan, and Dashboard JavaScript pass.
- [ ] README, Chinese guide, flow specification, acceptance record, and changelog agree.

Keep pull requests small and evidence-led. A successful build is not a compatibility claim.
