<p align="center">
  <strong>MacList</strong>
</p>

<p align="center">
  <strong>Recall the file. Hand it off. Keep control.</strong>
</p>

<p align="center">
  Local-first filename search and safe file handoff for macOS.
</p>

<p align="center">
  <a href="https://github.com/xffighting/maclist-actions/actions/workflows/ci.yml"><img alt="CI" src="https://github.com/xffighting/maclist-actions/actions/workflows/ci.yml/badge.svg"></a>
  <a href="https://github.com/xffighting/maclist-actions/releases/latest"><img alt="Release" src="https://img.shields.io/github/v/release/xffighting/maclist-actions"></a>
  <img alt="macOS" src="https://img.shields.io/badge/macOS-local--first-1d1d1f">
  <a href="LICENSE"><img alt="MIT License" src="https://img.shields.io/badge/license-MIT-007aff"></a>
</p>

<p align="center">
  <a href="#choose-a-track">Choose a track</a> ·
  <a href="#privacy-boundary">Privacy</a> ·
  <a href="https://xffighting.github.io/maclist-actions/project-dashboard.html">Project dashboard</a> ·
  <a href="docs/README.zh-CN.md">简体中文</a>
</p>

<p align="center">
  <img src="docs/assets/maclist-demo.gif" width="800" alt="MacList demo using synthetic filenames to find files and prepare a safe handoff">
</p>

> [!IMPORTANT]
> MacList v0.2.0 ships as two honest, separate tracks. **Cling Actions is the stable handoff layer. Standalone Core is a Developer Preview CLI/library, not a finished Listary replacement or signed Mac app.**

## Choose a track

| Track | Status | Best for | Cling required? |
|---|---|---|---:|
| **Cling Actions** | **Stable** | Find files with Cling, copy native file attachments, and open a destination app | Yes; custom Scripts may require Cling Pro or a trial |
| **Standalone Core** | **Developer Preview** | Build and test a private metadata index from explicitly authorized folders | No |

The tracks share a product direction—make old files easy to recall and reuse—but they do not yet form one standalone GUI application.

## Stable track: Cling Actions

Finding a document is often only half the job. MacList Actions removes the Finder-to-app drag while leaving the consequential steps to you:

1. open Cling and select one or more files;
2. run a MacList action;
3. MacList writes native file URLs to the pasteboard and opens the target app;
4. you choose the chat or draft, press **Command + V**, review, and send.

No upload service. No automatic recipient selection. No automatic send.

### Actions and shortcuts

| Action | Shortcut | What it does | Sends automatically? |
|---|---:|---|---:|
| WeChat handoff | `⌃⌘W` | Copies real files and opens WeChat | No |
| DingTalk handoff | `⌃⌘D` | Copies real files and opens DingTalk | No |
| Thunderbird handoff | `⌃⌘E` | Copies real files and opens Thunderbird | No |
| Apple Mail handoff | `⌃⌘M` | Copies real files and opens Apple Mail | No |
| Microsoft Outlook handoff | `⌃⌘O` | Copies real files and opens Outlook | No |
| Copy file checklist | `⌃⌘L` | Copies filenames and absolute paths as text | No |

Inside Cling's **Execute script** picker, the corresponding single-letter keys `W`, `D`, `E`, `M`, `O`, and `L` also work.

### Install the stable actions

Requirements:

- macOS 14 or newer;
- official [Cling 2.6.5](https://github.com/FuzzyIdeas/Cling/releases/tag/v2.6.5), preferably in `/Applications`;
- Cling Pro or an active trial if Cling requires it for custom Scripts;
- only the destination apps you actually use.

```bash
git clone https://github.com/xffighting/maclist-actions.git
cd maclist-actions
./install.sh
./doctor.sh
```

Restart Cling, press **Right Command + /**, select files, then run an action. The installer checks Cling's version, bundle identifier, Developer ID signature, and signing team before writing anything.

To verify or remove the customization:

```bash
./test.sh
./doctor.sh
./acceptance.sh /path/to/a/known/file
./uninstall.sh
```

The full local test temporarily replaces the pasteboard. CI uses an explicit no-UI mode. Uninstall restores snapshotted same-name scripts, six changed preferences, and the original Scripts-directory mode; it does not remove Cling or its index.

## Preview track: Standalone Core

[`standalone/`](standalone/) is a dependency-free Swift package for filename and path recall without Cling. It only indexes folders supplied with `--root`, stores metadata locally, and supports deterministic fuzzy search from the command line.

```bash
cd standalone
swift run maclist index --root "$HOME/Documents" --root "$HOME/Downloads"
swift run maclist search "quarter plan"
swift run maclist doctor
```

Today it is a **CLI and Swift library for development and validation**. It does not yet provide a menu bar app, global shortcut, search window, live filesystem updates, previews, or integrated handoff actions. See the [Standalone Core README](standalone/README.md) for its privacy contract and exact limitations.

## Privacy boundary

MacList's own code is designed around a narrow local boundary:

- no file upload, telemetry client, account, or API key;
- no document-body reading in the action scripts or standalone indexer;
- standalone indexing only inside roots explicitly passed by the user;
- hidden entries, package descendants, and symbolic links are skipped by the standalone indexer;
- native file URLs—not path text—are used for attachment handoff;
- no contact, chat, draft, paste, or Send action is automated;
- private app-owned state uses restrictive local permissions.

The pasteboard keeps file URLs until another app replaces them. If a destination app is missing, the selected files may still already be on the pasteboard. Third-party software—including Cling and destination apps—has its own behavior and privacy policy; this repository's guarantees apply only to MacList code.

## Why two tracks?

The stable path solves the immediate “I found it—now let me reuse it” problem with a small, auditable layer on top of Cling. The preview path is the beginning of an independent search foundation with a stricter explicit-root model. Keeping the labels separate makes it possible to ship useful work now without presenting an unfinished CLI as a complete desktop product.

## Project map

| Path | Purpose |
|---|---|
| `scripts/` | Stable Cling handoff actions and native pasteboard helper |
| `standalone/` | Developer Preview Swift search core and CLI |
| `tools/` | Deterministic demo renderer and media privacy audit |
| [Project dashboard](https://xffighting.github.io/maclist-actions/project-dashboard.html) | Interactive macOS-style project status, tasks, timeline, and decisions |
| [`ACCEPTANCE.md`](ACCEPTANCE.md) | Validation evidence and product boundary |
| [`COMPLIANCE.md`](COMPLIANCE.md) | Distribution and upstream separation |

The demo uses synthetic filenames and no captured desktop, account, recipient, or private path.

## FAQ

<details>
<summary><strong>Is MacList a complete macOS Listary alternative?</strong></summary>

No. The stable track still uses Cling for its launcher, index, search, preview, and selection UI. The independent track is currently a CLI/library Developer Preview.
</details>

<details>
<summary><strong>Does MacList upload or send my files?</strong></summary>

MacList's own code does neither. The stable actions place local file URLs on the pasteboard and open another app. You choose the destination, paste, review, and send.
</details>

<details>
<summary><strong>Why not publish a modified Cling binary?</strong></summary>

The public Cling v2.6.5 project references a local WarpDrop package and includes dependencies or binary artifacts whose downstream source and licensing closure could not be independently verified. This repository ships only original code and points users to the official Cling release.
</details>

<details>
<summary><strong>Does it support Windows?</strong></summary>

Not currently. The stable actions use macOS AppKit pasteboard types, JXA, and `open`; the standalone package targets macOS.
</details>

## Roadmap

- [ ] Package the standalone core behind a signed native Mac search window.
- [ ] Add opt-in filesystem event updates and a visible root-management UI.
- [ ] Connect search results to the existing handoff actions without automating Send.
- [ ] Add configurable shortcuts and conflict checks.
- [ ] Research a Windows adapter after the macOS workflow is stable.

## Contributing

Start with [CONTRIBUTING.md](CONTRIBUTING.md). Every new action must declare its target app, shortcut, content and network behavior, paste/send boundary, and rollback behavior. Small local-first actions make good first issues.

## Attribution and license

MacList is MIT-licensed original code. [Cling](https://github.com/FuzzyIdeas/Cling) is a separate GPL-3.0 project and is not included. This project is not affiliated with FuzzyIdeas, The Low-Tech Guys, Tencent, DingTalk, Mozilla, Microsoft, Apple, or Listary. See [NOTICE.md](NOTICE.md) and [COMPLIANCE.md](COMPLIANCE.md).

If this saves you from one more Finder-to-chat drag, consider starring the repository so another Mac user can find it.
