# Contributing

Thanks for helping make file handoff on macOS less tedious.

The repository has two maturity tracks:

- Cling actions are stable and must preserve the current rollback contract.
- `standalone/` is a Developer Preview and must remain usable without Cling.

## Add an action

1. Copy one of the executable scripts in `scripts/`.
2. Name it with the `MacList - ` prefix.
3. Add these metadata comments near the top:

   ```text
   # filesOnly: true
   # minFiles: 1
   # description: What the action does and what it never does
   # key: one-unused-letter
   # icon: an.sf.symbol
   ```

4. Keep all outbound effects explicit.
5. Identify destination applications by bundle ID, not a localized display name.
6. Run both test modes:

   ```bash
   MACLIST_TEST_NO_UI=1 ./test.sh
   ./test.sh
   ```

## Change the standalone core

Standalone changes must keep scanning limited to roots explicitly supplied by the user and must not read document contents.

Run:

```bash
cd standalone
swift test
./smoke-test.sh
```

Document any new persisted field, permission, dependency, or platform API. A future launcher must be able to consume the library without parsing human-formatted CLI output.

## Change README media

Media must be reproducible and contain synthetic data only:

```bash
python3 tools/render_media.py
swiftc tools/audit_media.swift -framework Vision -framework ImageIO -o /tmp/maclist-media-audit
/tmp/maclist-media-audit docs/assets/social-preview.png docs/assets/maclist-demo.gif docs/assets/demo-poster.png
```

Do not use real screenshots, account names, recipients, email addresses, client names, or absolute user paths.

## Pull-request checklist

- [ ] Target application and supported name are documented.
- [ ] Shortcut does not collide with an existing action.
- [ ] Network use is absent. The current safety gate rejects `curl`, `wget`, and `nc`.
- [ ] The action does not choose a recipient, paste, or send.
- [ ] File contents are not read.
- [ ] Missing-app behavior is safe.
- [ ] Rollback behavior is documented.
- [ ] Tests pass on macOS.
- [ ] Standalone changes pass `swift test` and the smoke test without Cling.
- [ ] Media changes pass the frame-by-frame Vision privacy audit.

## Design principles

- Local-first by default.
- Real file URLs for attachments; path text only when the user selects the checklist action.
- Human confirmation before any external communication.
- No hidden daemons, accounts, keys, or upload services.
- Honest capability and dependency disclosure.

Please keep pull requests small and focused. For a larger change, open an action request first.
