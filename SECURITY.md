# Security policy

## Supported version

Security fixes are applied to the latest release.

## Report a vulnerability

Please use GitHub's private vulnerability reporting for issues that could expose files, weaken signature checks, overwrite user scripts, bypass rollback, or trigger an unintended external action.

For the standalone preview, also report unintended traversal outside an authorized root, symlink escapes, unsafe index permissions, content reads, or network behavior.

Do not include real document names, paths, recipients, clipboard contents, licenses, or credentials in a public issue.

For ordinary bugs that contain no sensitive data, use the bug-report template.

## Security model

MacList Actions is designed to:

- operate only on user-selected paths;
- avoid file-content reads and network clients;
- leave paste and send under human control;
- validate the expected Cling identity before installation;
- preserve and restore user state;
- refuse unsafe symlink and overwrite conditions.

The standalone search-core preview is designed to:

- scan only roots explicitly supplied by the user;
- skip symbolic links and hidden entries by default;
- persist filenames, paths, and modification dates, not document contents;
- protect its state directory with mode `0700` and index files with mode `0600`;
- avoid accounts, telemetry, API keys, and network clients.

The model does not cover vulnerabilities in Cling, macOS, filesystem drivers, or destination applications.
