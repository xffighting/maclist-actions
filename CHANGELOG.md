# Changelog

All notable changes are documented here.

## 0.2.0 - 2026-07-13

### Added

- Stable Apple Mail and Microsoft Outlook file-handoff actions using their bundle identifiers.
- A standalone Swift search core Developer Preview that does not depend on Cling.
- A privacy-safe 12-second synthetic demo and 1280 × 640 social-preview asset.
- A deterministic media renderer and a macOS Vision privacy audit for every GIF frame.
- An interactive Executive, Operation, Knowledge, and Decision project dashboard.
- Shared design tokens for future README media and product previews.

### Changed

- Reframed the repository as two explicit tracks: stable Cling actions and a standalone-core preview.
- Expanded rollback and missing-application tests to cover the two new mail destinations.
- Added standalone Swift and media privacy checks to the release gate.

### Safety

- Apple Mail and Outlook actions only copy selected file URLs and launch the target bundle.
- Neither mail action creates a draft, chooses a recipient, pastes, or sends.
- The standalone preview indexes metadata only inside roots explicitly supplied by the user.
- Demo media contains synthetic filenames and no captured desktop, account, recipient, or local path.

## 0.1.0 - 2026-07-11

### Added

- WeChat, DingTalk, and Thunderbird file-handoff actions.
- Filename and absolute-path checklist action.
- Native macOS file-URL pasteboard helper.
- Signature, version, bundle, and signing-team installation gates.
- Idempotent install, state-aware rollback, and post-install edit protection.
- Restoration of original scripts, Boolean preferences, and Scripts-directory mode.
- Doctor, full local tests, no-UI CI tests, and search acceptance benchmark.
- English and Simplified Chinese documentation.

### Safety

- No automatic recipient selection, paste, or send.
- No network client in action scripts.
- No-state uninstall exits without changing Cling preferences.
