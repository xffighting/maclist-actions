<p align="center">
  <strong>MacList</strong>
</p>

<p align="center">
  <strong>Search inside the file picker. Stay in the app.</strong>
</p>

<p align="center">
  A local-first, Listary-inspired file picker companion for macOS.
</p>

<p align="center">
  <a href="https://github.com/xffighting/maclist-actions/actions/workflows/ci.yml"><img alt="CI" src="https://github.com/xffighting/maclist-actions/actions/workflows/ci.yml/badge.svg"></a>
  <img alt="Native Preview" src="https://img.shields.io/badge/status-native_preview-f5a623">
  <img alt="macOS 13+" src="https://img.shields.io/badge/macOS-13%2B-1d1d1f">
  <a href="LICENSE"><img alt="MIT License" src="https://img.shields.io/badge/license-MIT-007aff"></a>
</p>

<p align="center">
  <a href="#the-flow">The flow</a> ·
  <a href="#current-status">Status</a> ·
  <a href="#privacy-and-safety">Privacy</a> ·
  <a href="docs/README.zh-CN.md">简体中文</a>
</p>

> [!IMPORTANT]
> The native Mac app is an active developer preview. Its automatic dialog monitor, attached search UI, fuzzy search, and fail-safe selection bridge compile and pass headless tests. Real WeChat, Apple Mail, and Outlook regression is intentionally paused and is **not yet claimed as passed**.

## The problem

You are already writing a message in WeChat or an email. You click **Upload File** or **Add Attachment**—and then lose time navigating folders, switching to Finder, or remembering where the file lives.

MacList is designed around that exact moment.

## The flow

1. Click **Upload File** in WeChat, Mail, Outlook, or another Mac app.
2. The system file picker appears.
3. MacList detects it automatically, attaches a quiet search bar to that same window, and gives it keyboard focus without activating or switching apps.
4. Type a fuzzy filename, project name, or path fragment. A candidate list opens in place with the filename and parent folder.
5. Use the arrow keys or pointer to choose a candidate, then press Return. MacList locates and selects that exact path in the original picker. During the developer preview, you make the final **Open** confirmation yourself.

No launcher hotkey is required in the primary flow. No Finder window opens. MacList does not open or switch to the destination app—it stays attached to the picker you already invoked.

```mermaid
flowchart LR
    A["WeChat or Mail\nUpload File"] --> B["macOS file picker"]
    B --> C["MacList auto-detects\nand attaches search"]
    C --> D["Fuzzy match\nlocal metadata"]
    D --> E["Exact file selected\nin the same picker"]
```

## Current status

| Capability | Status | Evidence |
|---|---|---|
| Automatic file-window lifecycle monitor | Implemented, headless-verified | System-wide focus discovery separates host and dialog-owner PIDs; pure state tests and release build pass |
| Attached, nonactivating search bar | Implemented | AppKit key-window/first-responder recovery with bounded retries; no centered launcher path |
| Chinese and English fuzzy filename search | Implemented | Framework-free smoke tests and XCTest suite |
| Visible candidate list and search states | Implemented | Loading, results, no-match, and failure states; stale queries are cancelled |
| Spotlight metadata lookup | Implemented | Filename and path metadata only; no document-body or candidate-file reads |
| Exact file-picker handoff | Implemented with fail-safe | Preview selects and verifies the physical file, then leaves the final **Open** click to the user |
| Standard `NSOpenPanel` live regression | Paused | Requires explicit permission to run visible UI testing |
| WeChat / Apple Mail / Outlook live regression | Not yet verified | No compatibility claim until each app is tested |
| Signed and notarized download | Not available yet | Native preview is built locally from source |

The previous Cling action scripts and standalone CLI remain in this repository as historical prototypes. They are no longer the primary product flow.

## Why this is a native app, not a Skill

A Skill can explain, install, or validate a workflow. It cannot watch macOS window lifecycle events, display a nonactivating panel above another app, or safely control a system file picker. The core experience therefore belongs in a native Swift/AppKit menu bar app. A Skill may later provide setup and diagnostics around it.

## Architecture

```text
MacListApp
├── DialogProcessDiscovery   finds system focus and out-of-process panel owners
├── FileDialogMonitor         observes host and real dialog-owner PIDs separately
├── FileDialogDetector        scores focused, visible file-window evidence
├── SearchPanelController     attaches a compact nonactivating search bar
├── FileDialogBridge          returns an exact file to the original picker
└── AccessibilityPermission  never bypasses macOS TCC

MacListCore
├── DialogObservation         pure monitor state machine and attachment layout
├── SearchEngine              deterministic fuzzy ranking
├── SpotlightProvider         local metadata candidates
└── DialogSelectionPolicy     path validation and fail-safe bridge plan
```

The app uses public macOS Accessibility and Core Graphics APIs. Since macOS 10.15, Open panels are rendered out of process; Apple does not provide a public API for directly setting another app's `NSOpenPanel` URL. MacList therefore uses a narrow, permission-gated accessibility bridge and stops safely when the dialog cannot be verified.

## Build and verify

Requirements:

- macOS 13 or newer;
- Swift 6 toolchain;
- Accessibility and file-window control permission when the app is eventually run (not needed for headless core tests).

```bash
git clone https://github.com/xffighting/maclist-actions.git
cd maclist-actions
./app/Scripts/verify.sh
```

The verification script runs framework-free core tests, runs XCTest when the local Xcode toolchain provides it, builds release binaries, creates an ad-hoc signed `MacList.app`, validates its property list, and checks its signature. It does not launch the UI.

Useful focused commands:

```bash
swift build --package-path app
./app/Scripts/smoke-test.sh
./app/Scripts/build-app.sh release
```

Generated local artifacts are placed under `app/outputs/` and are intentionally ignored by Git.

## Privacy and safety

- No upload service, telemetry client, account, or API key.
- No document-body or candidate-file reads; search uses local filename and path metadata.
- No Finder launch, app switching, clipboard injection, AppleScript, recipient selection, or automatic Send.
- The first launch uses the normal macOS Accessibility prompt; file-window control permission is exposed from the menu bar. MacList cannot bypass TCC.
- A separate, user-initiated menu action can check top-level access to Desktop, Documents, Downloads, iCloud Drive, and installed cloud-provider roots. It does not read file contents, persist directory listings, or create a local index.
- Candidate handoff does not open the candidate file or download cloud placeholders. The original picker owns file access, while MacList verifies the exact selected path with bounded timeouts.
- The current preview never presses the original picker's final button. It selects and reads back the exact physical file, then leaves confirmation under user control.
- Save dialogs must never be auto-submitted or allowed to overwrite a file.

## Research basis

MacList takes product inspiration from [Listary Quick Save & Open](https://www.listary.com/feature/quick-save-and-open), while adapting the experience to macOS process and permission boundaries.

Relevant open-source references were reviewed as behavioral and architectural evidence:

- [Cling](https://github.com/FuzzyIdeas/Cling) — strong local search UX and indexing ideas; GPL-3.0, so its code is not copied into this MIT app.
- [Dialog Jumper](https://github.com/limars874/dialog-jumper-macos) — a small MIT experiment around macOS file-dialog detection and targeted path navigation.
- [Peekaboo](https://github.com/openclaw/Peekaboo) — mature MIT accessibility automation patterns, especially re-resolving stale AX elements.
- [LeaderKey](https://github.com/mikker/LeaderKey) — MIT reference for nonactivating AppKit panels.

See [the file-dialog flow specification](docs/FILE_DIALOG_FLOW_SPEC.md) for the exact boundary and release gate.

## Repository map

| Path | Purpose |
|---|---|
| `app/` | Native Swift/AppKit preview and headless tests |
| `docs/FILE_DIALOG_FLOW_SPEC.md` | Product flow, failures, and release criteria |
| `standalone/` | Earlier local search CLI/core prototype |
| `scripts/` | Earlier Cling action-layer prototype |
| `tasks/` | Current implementation plan and verification checklist |
| `COMPLIANCE.md` | Upstream and distribution boundaries |

## FAQ

<details>
<summary><strong>Does MacList appear automatically?</strong></summary>

That is the primary design. The native preview follows system-wide focus, discovers the real owner of an out-of-process file panel, and attaches when a high-confidence picker appears. It does not require `Option + Space`.
</details>

<details>
<summary><strong>Is WeChat support finished?</strong></summary>

Not yet. The automatic monitor has been implemented, but the redesigned flow has not been allowed to run a real WeChat UI regression. The README will not claim support until that test passes repeatedly.
</details>

<details>
<summary><strong>Why does MacList need Accessibility permission?</strong></summary>

macOS does not expose another app's `NSOpenPanel` object. Permission-gated Accessibility APIs are required to identify the picker, write the chosen path, and verify the selected file without switching apps or using the clipboard.
</details>

<details>
<summary><strong>Why can the search bar appear without showing my file?</strong></summary>

First, use the MacList menu-bar item **检查常用文件夹与云盘访问权限…** (Check Common Folders and Cloud Drive Access) and respond to any macOS permission prompts. MacList then refreshes Spotlight metadata. This check is user-initiated and does not build a private file index, so files excluded from Spotlight can still remain unavailable in the current preview.
</details>

<details>
<summary><strong>Does it read or upload my documents?</strong></summary>

No. MacList searches local metadata and does not contain a network upload path. The selected file is handed back to the file picker that you opened.
</details>

## Contributing

Start with [CONTRIBUTING.md](CONTRIBUTING.md). The most valuable contributions are reproducible, privacy-safe AX structure fixtures from different macOS versions and file pickers—never screenshots or paths containing personal data.

## Attribution and license

MacList is MIT-licensed original code. It is not affiliated with Apple, Listary, Tencent, Microsoft, FuzzyIdeas, or the referenced open-source projects. See [NOTICE.md](NOTICE.md) and [COMPLIANCE.md](COMPLIANCE.md).

If this product moment resonates with you, consider starring the repository—but judge it by verified compatibility, not promises.
