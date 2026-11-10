## Summary

<!-- What does this change do, and why? -->

## Linked issue

<!-- "Fixes #123". One issue per pull request. Write "None" for a small fix that has no issue. -->

## Test evidence

<!-- The commands you ran and their results, for example `make test`, `make dsl-test`, `make ui-test GODOT=...`, `make web-build`. -->

## Screenshots

<!-- Before and after, at real size, for any change that is visible in the client or on the website. Write "None" otherwise. -->

| Before | After |
|---|---|
|  |  |

## Checklist

- [ ] The checks for every area I touched pass locally (see CONTRIBUTING.md).
- [ ] New behaviour is covered by tests, and no test was skipped, deleted or commented out.
- [ ] Schema or contract change? If a file in `packages/schemas`, the patch semantics, the DSL migration or the HTTP API changed, the client runtime, the server, the baseline DSL, the tests and the docs are updated in this pull request. Otherwise: not applicable.
- [ ] Both RFC 6902 implementations updated? If patch or migration behaviour changed, `packages/dsl` and `apps/client/runtime/json_patch.gd` (and `dsl_migrations.gd`) are changed together and the shared golden fixtures still pass on both sides. Otherwise: not applicable.
- [ ] The Shell and Runtime boundary is intact: all communication goes through `apps/client/runtime/game_session.gd`.
- [ ] No model output is executed or stored without schema validation.
- [ ] New third-party code or assets are licence-compatible with Apache-2.0 and recorded in `docs/legal/licenses.md`.
- [ ] Docs are updated where behaviour, configuration or the API changed.
- [ ] No secrets, tokens or personal data are included in code, fixtures, logs or screenshots.
