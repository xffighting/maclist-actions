# Contributing

Thanks for helping make file handoff on macOS less tedious.

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
5. Run both test modes:

   ```bash
   MACLIST_TEST_NO_UI=1 ./test.sh
   ./test.sh
   ```

## Pull-request checklist

- [ ] Target application and supported name are documented.
- [ ] Shortcut does not collide with an existing action.
- [ ] Network use is absent. The current safety gate rejects `curl`, `wget`, and `nc`.
- [ ] The action does not choose a recipient, paste, or send.
- [ ] File contents are not read.
- [ ] Missing-app behavior is safe.
- [ ] Rollback behavior is documented.
- [ ] Tests pass on macOS.

## Design principles

- Local-first by default.
- Real file URLs for attachments; path text only when the user selects the checklist action.
- Human confirmation before any external communication.
- No hidden daemons, accounts, keys, or upload services.
- Honest capability and dependency disclosure.

Please keep pull requests small and focused. For a larger change, open an action request first.
