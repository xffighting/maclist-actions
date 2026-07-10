# Changelog

All notable changes are documented here.

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
