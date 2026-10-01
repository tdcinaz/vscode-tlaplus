## What changed

<!-- One or two sentences. Link the fork PR/commit if this bumps the tlaplus submodule. -->

## Checklist

- [ ] Java changes are committed in `tlaplus/` **and pushed to `tdcinaz/tlaplus` `tlatex-overhaul`** before the submodule pointer was bumped here (`npm run tlatex:status` says "pushed: yes").
- [ ] `npm run tlatex:check` passes locally (build, `test/tla2tex/*` JUnit tests, all fixtures typeset).
- [ ] New or changed typesetting behavior has a JUnit test under `test/tla2tex/` and, if it concerns syntax, a fixture under `tests/fixtures/tlatex/`.
- [ ] `tools/tla2tools.jar` is **not** in this diff (`npm run tlatex:restore`).
- [ ] No Eclipse `.project` / `.settings` / `.classpath` changes in `tlaplus/`.
- [ ] Fork diff stays confined to `tla2tex` source, its tests, and minimal build wiring.
