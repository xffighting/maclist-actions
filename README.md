<p align="center">
  <strong>MacList</strong>
</p>

<p align="center">
  <strong>Search inside the file picker. Stay in the app.</strong>
</p>

<p align="center">
  A local-first, Listary-inspired file-picker companion for macOS.
</p>

<p align="center">
  <a href="https://github.com/xffighting/maclist-actions/actions/workflows/ci.yml"><img alt="CI" src="https://github.com/xffighting/maclist-actions/actions/workflows/ci.yml/badge.svg"></a>
  <img alt="Version 0.3.0 Native Preview" src="https://img.shields.io/badge/version-0.3.0_Native_Preview-f5a623">
  <img alt="macOS 13+" src="https://img.shields.io/badge/macOS-13%2B-1d1d1f">
  <a href="LICENSE"><img alt="MIT License" src="https://img.shields.io/badge/license-MIT-007aff"></a>
</p>

<p align="center">
  <a href="#first-setup-one-time">First setup</a> ·
  <a href="#daily-flow">Daily flow</a> ·
  <a href="#current-status">Status</a> ·
  <a href="#privacy-and-safety">Privacy</a> ·
  <a href="docs/README.zh-CN.md">简体中文</a>
</p>

> [!IMPORTANT]
> MacList 0.3.0 is a Native Preview, not a finished compatibility release. The local index, dual-source search, automatic dialog monitor, attached search UI, and fail-closed select-and-confirm policy pass the repository's headless gates. The real system panel and WeChat, Apple Mail, and Outlook regression remain intentionally paused and are **not yet claimed as passed**.

## The problem

You are already writing a message in WeChat or an email. You click **Upload File** or **Add Attachment**—and then lose time navigating folders, switching to Finder, or remembering where a client or project file lives.

MacList is built for that exact moment.

## First setup (one time)

MacList's private local index is **off by default**. It does not scan a folder until you explicitly choose one.

1. Launch MacList and use its menu-bar icon to grant the normal macOS Accessibility and file-window control permissions.
2. Choose **选择索引文件夹…** (Choose Index Folders) from the MacList menu.
3. Select specific folders that contain your client and project files. MacList rejects broad roots such as the whole system, the whole home folder, and ordinary Library folders.
4. Wait for the menu status to become **Ready** or **Partially indexed**. Limits or filesystem access errors produce an explicit partial state; safe results stay searchable without being mistaken for a complete scan.

MacList stores only each file's **filename, full path, and modification time**, plus macOS bookmark data for the folders you selected. It does not read document bodies. The full path can reveal folder names, so the index and bookmark files are kept in MacList's private local application data.

Use **立即更新本地索引** (Update Local Index Now) after files move or change. Use **清空本地索引…** (Clear Local Index) to remove the saved metadata and folder bookmarks; original files are never deleted.

> [!NOTE]
> “Off by default” applies to MacList's private scanner. macOS Spotlight may still supply supplemental filename/path metadata from the system index that already exists on the Mac.

## Daily flow

1. In WeChat, Mail, Outlook, or another app, click **Upload File** or **Add Attachment**.
2. The macOS file picker appears.
3. MacList detects a high-confidence file picker and attaches a quiet search bar without opening Finder or switching to another app.
4. Type a client name, project name, filename, or path fragment. A candidate list appears in place with filenames and parent folders.
5. Choose a candidate with the arrow keys or pointer, then press Return.
6. In the default mode, MacList selects the exact file and confirms the original Open-file panel; the attachment then enters the current message's waiting-to-send area. MacList never presses **Send**.

If the panel is a Save, folder, unknown, or multi-selection dialog; the session is stale; the exact selection cannot be verified; or the default action is missing or ambiguous, MacList must refuse automatic confirmation and leave the original picker open for manual confirmation. From the menu bar, turn off **Confirm original window after selecting a file** to use select-only mode at any time.

No launcher hotkey is required in the primary flow. `Esc` closes only the MacList panel, not the original picker.

```mermaid
flowchart LR
    A["WeChat or Mail\nUpload File"] --> B["macOS file picker"]
    B --> C["MacList attaches\nwithout app switching"]
    C --> D["Client / project / file / path\nfuzzy search"]
    D --> E["Exact file selected"]
    E --> F["Verified Open-file panel\nauto-confirmed"]
    F --> G["Attachment waits to send\nYou still press Send"]
```

## How search works

MacList merges two metadata-only sources:

- **User-authorized local index — primary.** It searches filenames and full paths inside the folders you selected, so client and project folder names can match even when the exact filename is forgotten.
- **Spotlight — supplement.** It can add files known to the macOS system index. When both sources return the same normalized full path, the authorized local-index record wins.

Each query has its own generation token. Refreshing the local index invalidates older local results, and a previous query cannot overwrite the current candidate list.

## Current status

| Capability | Status | Evidence |
|---|---|---|
| Explicit folder authorization and private metadata index | Implemented, headless-verified | Default-off bootstrap; persistent macOS bookmarks; bounded filename/path/mtime index |
| Ready, partial, refresh, authorization, and failure states | Implemented | Limits, inaccessible roots, subtree/metadata errors, and menu/service state gates |
| Local-index primary + Spotlight supplement | Implemented | Deterministic path de-duplication; local record wins; stale-query gates |
| Automatic file-window lifecycle monitor | Implemented, headless-verified | System-wide focus discovery separates host and dialog-owner PIDs |
| Attached, nonactivating search bar | Implemented | Key-window/first-responder recovery with bounded retries |
| Chinese and English fuzzy filename/path search | Implemented | Framework-free smoke tests and XCTest suite |
| Default select-and-confirm handoff | Implemented; headless gate passed | One-shot lease, authoritative default button, exact single-file selection, explicit file-action allowlist, and fail-closed manual fallback |
| Select-only menu mode | Implemented preference surface | Turn off **Confirm original window after selecting a file** to leave **Open** to the user |
| Standard `NSOpenPanel` live regression | Paused | Requires explicit permission to run visible UI testing |
| WeChat / Apple Mail / Outlook live regression | Not yet verified | No compatibility claim until each current app version is tested |
| Signed and notarized download | Not available yet | Native Preview is built locally from source |

The previous Cling action scripts and standalone CLI remain in the repository as historical prototypes. They are no longer the primary product flow.

## Why this is a native app, not a Skill

A Skill can explain, install, or validate a workflow. It cannot watch macOS window lifecycle events, display a nonactivating panel above another app, or safely control a system file picker. The core experience therefore belongs in a native Swift/AppKit menu-bar app. A Skill may later provide setup and diagnostics around it.

## Architecture

```text
MacListApp
├── DialogProcessDiscovery   finds system focus and out-of-process panel owners
├── FileDialogMonitor         observes host and real dialog-owner PIDs separately
├── SearchPanelController     attaches search and merges current-query results
├── LocalIndexCoordinator     owns user-requested setup, update, and clear actions
├── FileDialogBridge          returns an exact file to the original picker
└── AccessibilityPermission  never bypasses macOS TCC

MacListCore
├── AuthorizedFolderStore     persists revision-bound macOS bookmarks privately
├── LocalIndexRootPolicy      rejects unsafe or overly broad roots
├── LocalIndexService         generation-gated authorization and rebuild lifecycle
├── LocalFileIndexer          bounded filename/path/mtime scanner
├── LocalIndexProvider        primary metadata search source
├── SpotlightProvider         supplemental system metadata source
├── SearchResultSet/Epoch     deterministic merge and stale-result rejection
└── DialogSelectionPolicy     path validation and fail-closed confirmation policy
```

The app uses public macOS Accessibility and Core Graphics APIs. Since macOS 10.15, Open panels are rendered out of process; Apple does not provide a public API for directly setting another app's `NSOpenPanel` URL. MacList therefore uses a narrow, permission-gated accessibility bridge and stops safely when the current dialog, authoritative action, or exact selected normalized path cannot be verified.

## Build, verify, and try locally

Requirements:

- macOS 13 or newer;
- Swift 6 toolchain;
- Accessibility and file-window control permission only when running the app, not for headless verification.

```bash
git clone https://github.com/xffighting/maclist-actions.git
cd maclist-actions
./app/Scripts/verify.sh
```

The verification script runs framework-free core gates, runs XCTest when a complete Xcode toolchain is available, builds release binaries, creates an ad-hoc signed `MacList.app`, validates its property list and signature, and runs the command-line doctor. It does not launch the graphical app.

GitHub Actions remains a permanent per-push gate. Remote status is always the actual workflow result for that commit, never an inference from local verification.

Install without launching, or explicitly launch the menu-bar preview:

```bash
./app/Scripts/install-local.sh
./app/Scripts/install-local.sh --launch
```

The default destination is `~/Applications/MacList.app`. The first command does not launch it; `--launch` is explicit and starts it in the background.
Quit an already running MacList before installing or updating so the process and app bundle always match.

Useful focused commands:

```bash
swift build --package-path app
./app/Scripts/all-smoke-tests.sh
./app/Scripts/build-app.sh release
```

Generated local artifacts are placed under `app/outputs/` and are intentionally ignored by Git.

## Privacy and safety

- No upload service, telemetry client, account, or API key.
- The authorized index stores only filename, full path, modification time, and selected-folder bookmark data; it does not read document bodies or candidate-file contents.
- The private scanner is default-off, only follows explicit folder selection, skips symlink escapes, and rejects unsafe broad roots.
- Cached data is accepted only when authorization revision and canonical root set match. Root identity is rechecked before and after a build.
- Replacing folders, clearing data, closing a dialog, or starting a new search invalidates older asynchronous work so it cannot restore stale results.
- **Clear Local Index** removes metadata and bookmarks, never original files.
- No Finder launch, clipboard injection, AppleScript, recipient selection, or automatic **Send**. Automatic confirmation is limited to the original, current, verified single-file Open panel.
- Folder setup may temporarily activate MacList only after you click its menu command; the daily file-picker flow does not activate or switch applications.
- Candidate handoff does not open the file itself or download cloud placeholders. The original picker owns file access while MacList verifies its selected normalized URL/path with bounded timeouts.
- Save, folder, unknown, and multi-selection dialogs are never auto-confirmed. A stale session, unverified exact selection, missing default action, or ambiguous action also falls back to manual confirmation.

## Research basis

MacList takes product inspiration from [Listary Quick Save & Open](https://www.listary.com/feature/quick-save-and-open), while adapting the experience to macOS process, permission, and privacy boundaries.

Relevant open-source references were reviewed as behavioral and architectural evidence:

- [Cling](https://github.com/FuzzyIdeas/Cling) — local search UX and indexing ideas; GPL-3.0, so its code is not copied into this MIT app.
- [Dialog Jumper](https://github.com/limars874/dialog-jumper-macos) — an MIT experiment around macOS file-dialog detection and targeted path navigation.
- [Peekaboo](https://github.com/openclaw/Peekaboo) — MIT accessibility automation patterns, especially re-resolving stale AX elements.
- [LeaderKey](https://github.com/mikker/LeaderKey) — MIT reference for nonactivating AppKit panels.

See [the file-dialog flow specification](docs/FILE_DIALOG_FLOW_SPEC.md) for the exact boundary and release gate.

## Repository map

| Path | Purpose |
|---|---|
| `app/` | Native Swift/AppKit preview and headless tests |
| `docs/FILE_DIALOG_FLOW_SPEC.md` | Product flow, failure semantics, and release criteria |
| `standalone/` | Earlier local-search CLI/core prototype |
| `scripts/` | Earlier Cling action-layer prototype |
| `tasks/` | Implementation plans and verification checklists |
| `COMPLIANCE.md` | Upstream and distribution boundaries |

## FAQ

<details>
<summary><strong>Does MacList appear automatically?</strong></summary>

That is the implemented primary design. The Native Preview follows system-wide focus, discovers the real owner of an out-of-process file panel, and attaches only when the evidence reaches its picker threshold. Real WeChat, Mail, and Outlook behavior still needs visible regression testing.
</details>

<details>
<summary><strong>Why is there no candidate list?</strong></summary>

Open the MacList menu and choose **选择索引文件夹…** first. If the menu says **Partially indexed**, the safe partial results remain available, but some folders or files may have been inaccessible or a scan limit was reached. Use **立即更新本地索引** after correcting access. Spotlight remains supplemental and may not know every file.
</details>

<details>
<summary><strong>Does pressing Return upload the file?</strong></summary>

The selected default is: MacList selects the verified file and confirms the original single-file Open panel, so the attachment enters the message's waiting-to-send area. It never sends the message. If any safety check is uncertain, the picker stays open for you to confirm manually. You can also turn automatic confirmation off from the MacList menu and keep select-only behavior.
</details>

<details>
<summary><strong>Is automatic confirmation already verified in WeChat and Mail?</strong></summary>

No. The mode, one-shot bridge, refusal matrix, preference, build, and installer pass the headless repository gate, but no visible standard-panel, WeChat, Apple Mail, or Outlook regression has been run. Compatibility remains unverified until those tests are explicitly allowed and completed.
</details>

<details>
<summary><strong>Does it read or upload my documents?</strong></summary>

No. It searches local metadata and contains no document-upload path. Remember that a full path is metadata and can expose client or project folder names; use **Clear Local Index** whenever you want to remove the local cache and bookmarks.
</details>

## Contributing

Start with [CONTRIBUTING.md](CONTRIBUTING.md). The most valuable contributions are reproducible, privacy-safe AX structure fixtures from different macOS versions and file pickers—never screenshots or paths containing personal data.

## Attribution and license

MacList is MIT-licensed original code. It is not affiliated with Apple, Listary, Tencent, Microsoft, FuzzyIdeas, or the referenced open-source projects. See [NOTICE.md](NOTICE.md) and [COMPLIANCE.md](COMPLIANCE.md).

If this product moment resonates with you, consider starring the repository—but judge it by verified compatibility, not promises.
