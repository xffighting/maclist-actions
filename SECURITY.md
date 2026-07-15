# Security policy

## Supported version

Security fixes are applied to the latest release.

## Report a vulnerability

Please use GitHub's private vulnerability reporting for issues that could expose files, weaken signature checks, overwrite user scripts, bypass rollback, or trigger an unintended external action.

For the native preview and standalone prototype, also report unintended traversal outside an authorized root, symlink escapes, stale authorization reuse, unsafe index permissions, content reads, unintended file-picker confirmation, or network behavior.

Do not include real document names, paths, recipients, clipboard contents, licenses, or credentials in a public issue.

For ordinary bugs that contain no sensitive data, use the bug-report template.

## Security model

The native MacList preview is designed to:

- keep its private scanner off until the user explicitly chooses folders;
- scan only those selected roots, reject broad roots, and skip symlink escapes;
- persist filenames, normalized full paths, modification dates, and folder bookmarks, not document contents;
- protect its application-data directory with mode `0700` and index files with mode `0600`;
- treat stale or invalid folder authorization and incomplete scans as fail-closed or partial states;
- use macOS Spotlight only as a supplemental source of filename/path metadata already indexed by the system;
- confirm only the exact selected file in the original single-file Open panel after all fail-closed gates pass, with a select-only manual mode available;
- leave every WeChat, Mail, or other message send under human control;
- avoid accounts, telemetry, API keys, document uploads, and network clients.

The local installer is designed to refuse a running MacList process, unsafe destination symlinks/types/owners, concurrent replacement, and invalid code signatures. It keeps a recoverable previous app while replacing the bundle and does not launch unless `--launch` is explicit.

The earlier standalone search-core prototype is designed to:

- scan only roots explicitly supplied by the user;
- skip symbolic links and hidden entries by default;
- persist filenames, paths, and modification dates, not document contents;
- protect its state directory with mode `0700` and index files with mode `0600`.

The historical Cling actions validate the expected Cling identity before installation, preserve user state, and refuse unsafe script overwrite or symlink conditions. They are not the native file-picker workflow.

The model does not cover metadata exposed by macOS Spotlight itself, or vulnerabilities in Cling, macOS, filesystem drivers, cloud providers, or destination applications.
