# MacList Standalone Core

> **v0.2.0 status: Developer Preview**

A dependency-free Swift core for fast local filename and path recall on macOS. It does not depend on Cling, upload files, or automate another app.

This is deliberately a narrow foundation: authorize folders explicitly, build a private metadata index, then run deterministic fuzzy searches from the command line. It is **not yet a complete Listary alternative, signed `.app`, menu bar utility, or global search window**.

## What works today

- one or more explicit `--root` folders;
- local metadata-only JSON index;
- exact, token, prefix, substring, and fuzzy subsequence ranking;
- short Chinese filename queries;
- human-readable and JSON command output;
- health checks for index format, permissions, readable roots, and scope boundaries;
- reusable `MacListCore` Swift library plus the `maclist` CLI.

## Privacy contract

- Nothing is indexed unless its folder is explicitly passed with `--root`.
- Only authorized roots, filenames, absolute paths, and modification dates are stored.
- Document bodies are never opened, parsed, embedded, or transmitted.
- Hidden entries, package descendants, and symbolic links are skipped by default.
- The package contains no networking, telemetry, account, or API-key code.
- The default index is local at `~/Library/Application Support/MacListStandalone/index.json` with mode `0600`; its app-owned directory uses mode `0700`.
- A custom store file also uses mode `0600`. Existing custom parent-directory permissions are preserved so the CLI does not unexpectedly change a user-managed directory.

Absolute paths are still sensitive metadata. Protect the index and your backups as you would other data in your macOS account.

## Try it

Requirements: macOS 13 or newer and Swift 6.0 or newer.

```bash
cd standalone

# Repeating --root is supported. No folder is scanned implicitly.
swift run maclist index \
  --root "$HOME/Documents" \
  --root "$HOME/Downloads"

# Filename matches rank above path-only matches; fuzzy subsequences work too.
swift run maclist search "quarter plan"
swift run maclist search "qtp" --limit 10

# Check format, permissions, roots, and scope boundaries.
swift run maclist doctor
```

For isolated testing, choose a different metadata store:

```bash
swift run maclist index --root "/absolute/folder" --store "/tmp/maclist-demo/index.json"
swift run maclist search "invoice" --store "/tmp/maclist-demo/index.json" --json
swift run maclist doctor --store "/tmp/maclist-demo/index.json"
```

`index` replaces the previous snapshot. It stops at 250,000 files by default; use `--max-files N` for another explicit cap.

## Commands

| Command | Purpose |
|---|---|
| `maclist index --root PATH [--root PATH]` | Rebuild the metadata snapshot from explicitly authorized roots |
| `maclist search QUERY [--limit N]` | Rank filename and path matches deterministically |
| `maclist doctor` | Validate privacy assumptions, permissions, schema, roots, and scope |

All commands accept an optional `--store FILE`; all three commands support `--json` where structured output is useful.

## Architecture

| Component | Responsibility |
|---|---|
| `AuthorizedRoot` | Canonicalizes and validates only directories supplied by the user |
| `FileIndexer` | Enumerates metadata without reading document bodies; skips symlinks and hidden/package descendants |
| `FuzzySearch` | Ranks exact name → stem → prefix → word prefix → name contains/subsequence → path |
| `IndexStore` | Writes versioned JSON atomically and applies a safe local permission policy |
| `Doctor` | Checks permissions, schema compatibility, root readability, and authorized scope |
| `maclist` | Exposes the zero-dependency `index`, `search`, and `doctor` CLI |

## Development and verification

```bash
cd standalone
swift test
./smoke-test.sh
swift run maclist --help
```

The deterministic tests cover authorization failures, nested enumeration, symbolic-link and hidden-file exclusion, fuzzy ordering, short Chinese queries, index limits, JSON round trips, private permissions, and doctor scope enforcement.

## Known limitations

- CLI/library only; no signed app or graphical search experience.
- Indexes rebuild on demand; filesystem event updates are not implemented.
- No global shortcut, Finder integration, result preview, or open/reveal action yet.
- Stable file handoff actions remain in the [parent project](../README.md) and are not invoked by this core.
- Search is filename/path metadata recall, not document-body or semantic search.
- Performance and behavior are still being validated across different Mac hardware and large directory layouts.

These limitations are intentional release boundaries, not hidden roadmap claims. Follow the [project dashboard](https://xffighting.github.io/maclist-actions/project-dashboard.html) for current status and decisions.

Licensed under the repository's [MIT License](../LICENSE).
