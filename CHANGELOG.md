# Changelog

All notable changes are documented here.

## Unreleased - 0.3.0 Native Preview (2026-07-15)

### Added

- A native Swift/AppKit menu bar app that automatically discovers supported file pickers and attaches a nonactivating search panel.
- System-wide focus discovery for out-of-process Open/Save Panel owners, with separate host, dialog-owner, and runtime event-target PIDs.
- Confidence-scored file-dialog classification, observer cleanup, generation-bound UI transactions, and multi-screen attachment tests.
- A cancellable, bounded accessibility bridge that verifies the exact selected file URL/path and runs AX work off the main thread.
- A default-off local metadata index configured only through the user-initiated **Choose Index Folders** menu action.
- Private persistence for filename, full path, modification time, and macOS bookmark data; document bodies and candidate-file contents are not read.
- Authorization revisions, canonical-root validation, root-identity checks, bounded scans, and generation-gated rebuild cancellation.
- Explicit ready, partial, needs-refresh, needs-authorization, and failure states, plus **Update Local Index Now** and **Clear Local Index** menu actions.
- Dual-source candidate search: the user-authorized local index is primary, Spotlight is supplemental, and the local record wins when both sources return the same path.
- A local installer that targets `~/Applications/MacList.app`, does not launch by default, and launches only with explicit `--launch`.
- A persistent file-dialog completion preference. The selected default is `selectAndConfirm`; the menu can switch back to `selectOnly`.

### Changed

- Removed the launcher-hotkey and centered-window assumptions from the primary product flow.
- Adopted the user's streamlined default: after exact selection, confirm the original verified single-file Open panel. The attachment may enter the draft's waiting-to-send area, but MacList never sends the message.
- Expanded fuzzy search from exact-filename recall to client name, project name, filename, and path-fragment recall.
- Replaced the old common-folder permission check with an explicit folder picker, persistent authorization bookmarks, and an inspectable local-index lifecycle.
- A partially completed bounded scan now keeps its safe results searchable while remaining visibly marked as partial.
- Reframed Cling actions and the standalone CLI as earlier prototypes rather than the primary product.

### Verification

- Added default-off and no-implicit-scan gates.
- Added authorization-revision and canonical-root-set cache acceptance gates.
- Added build-generation cancellation and clear-without-resurrection gates.
- Added root-policy and root-identity replacement gates.
- Added stale-query and stale-local-refresh rejection gates.
- Added local-index/Spotlight merge, local-wins de-duplication, partial-state, subtree/metadata access-error, bookmark-store, and menu-presentation gates.
- Added headless gates for the one-shot select-and-confirm lease, authoritative Open-panel default action, exact single-file selection, unsafe-title refusal matrix, persistent mode preference, signed release build, and transactional installer rollback.

### Safety

- No visible application, harness, keyboard-event, WeChat, Mail, or Outlook test was run during this headless redesign.
- The daily file-picker path contains no Finder launch, application activation/deactivation, clipboard injection, AppleScript, recipient selection, or automatic Send. MacList activates only after the user explicitly opens the folder-setup command.
- The private scanner remains disabled until the user chooses folders. Broad system/home/Library roots and symlink escapes are rejected.
- Clearing the local index removes saved metadata and folder bookmarks, never original files.
- Automatic confirmation must fail closed for Save, folder, unknown, and multi-selection dialogs; stale sessions; unverified selections; and missing or ambiguous default actions. In every denial case the original picker remains available for manual confirmation.
- Automatic **Send** is never part of either completion mode.
- Live compatibility remains unverified and no native release tag should be created yet.

## 0.2.0 - 2026-07-14

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
