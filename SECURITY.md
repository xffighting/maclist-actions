# Security policy

## Supported version

Security fixes are applied to the latest release.

## Report a vulnerability

Please use GitHub's private vulnerability reporting for issues that could expose files, weaken signature checks, overwrite user scripts, bypass rollback, or trigger an unintended external action.

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

The model does not cover vulnerabilities in Cling, macOS, or destination applications.
