# vscode-tlaplus — TLATeX overhaul fork

**Goal of this repo:** overhaul and modernize **TLATeX** (`tla2tex`), the Java
pretty-printer that typesets TLA+ modules to LaTeX/PDF. This VS Code extension is
the *workspace and test harness*; the typesetter source lives in the `tlaplus/`
git submodule (our fork `tdcinaz/tlaplus`, branch `tlatex-overhaul`).

Full workflow guide: [docs/TLATEX_DEV.md](docs/TLATEX_DEV.md). Read it before
touching the Java.

## Where things are

| What | Path |
| --- | --- |
| TLATeX Java source (the thing we are changing) | `tlaplus/tlatools/org.lamport.tlatools/src/tla2tex/` (entry point `TLA.java`; `TokenizeSpec`, `FindAlignments`, `LaTeXOutput` do most of the work; `tlatex.sty` is the LaTeX style) |
| TLATeX JUnit tests (none upstream; we add them) | `tlaplus/tlatools/org.lamport.tlatools/test/tla2tex/` |
| Ant build for `tla2tools.jar` | `tlaplus/tlatools/org.lamport.tlatools/customBuild.xml` |
| How the extension invokes the jar | `src/tla2tools.ts` (`runTex`, `runTex2PDF`) |
| Sample specs for the operator-to-macro work | `tests/fixtures/tlatex/` (see its `README.txt`) |
| Single entry point for build/test/typeset | `scripts/tlatex-dev.sh` (wrapped as `npm run tlatex:*`) |
| Guard hooks (installed by `tlatex:setup`) | `.githooks/` |
| CI for the Java side | `.github/workflows/tlatex.yml` |

## Commands (run from the repo root)

```sh
npm run tlatex:doctor    # verify JDK 17 + Ant + git (+ pdflatex)
npm run tlatex:setup     # init submodule on branch tlatex-overhaul, install hooks (idempotent)
npm run tlatex:status    # branch/commit/dirty state of both repos, dev-jar status
npm run tlatex:test      # JUnit tests matching test/tla2tex/*   (fast inner loop)
npm run tlatex:dev       # rebuild tla2tools.jar and swap it into ./tools
npm run tlatex:check     # build + test + typeset every fixture (what CI runs)
bash scripts/tlatex-dev.sh typeset tests/fixtures/tlatex/MacroOperators.tla
npm run tlatex:restore   # put the released jar back
```

Extension side (TypeScript): `npm run compile`, `npm run lint`, `npm test`
(VS Code must not be open when running `npm test` from a terminal).

## Rules for agents and humans

1. **Work inside the Dev Container.** It has JDK 17, Ant, TeX Live, Node 22,
   `gh`, and Claude Code. The host may lack Ant or have a broken Node.
2. **Edit Java only on branch `tlatex-overhaul` inside `tlaplus/`.** After
   `git submodule update` the submodule is on a detached HEAD; run
   `npm run tlatex:setup` before committing there.
3. **Two-step commits, fork first.** Commit and push in `tlaplus/`, then
   `git add tlaplus` and commit the pointer bump here. Pushing a pointer to an
   unpushed commit breaks every teammate's checkout. The pre-commit hook blocks
   this.
4. **Never commit `tools/tla2tools.jar`.** `tlatex:dev` overwrites it with a
   local build. CI and releases download the official jar. The hook blocks it.
5. **Never commit Eclipse metadata** (`.project`, `.settings/*.prefs`,
   `.classpath`) inside `tlaplus/`. The Java language server regenerates them;
   discard with `git -C tlaplus checkout -- .`. The hook blocks it.
6. **Keep fork changes confined to `tla2tex`** (its source, tests, and the
   minimal `customBuild.xml` wiring they need) so syncing with upstream
   `tlaplus/tlaplus` stays a clean merge.
7. **Add a JUnit test with every behavior change** under `test/tla2tex/`, and a
   fixture under `tests/fixtures/tlatex/` when the change concerns new syntax.
   Fixtures must parse with SANY and typeset without LaTeX errors.
8. **Typeset output is disposable.** `.tex/.dvi/.pdf/.log/.aux` next to
   fixtures are gitignored; do not commit them.
9. **Do not reformat Java files you are not changing.** Upstream style is
   decades-old Lamport code; large reformatting diffs make upstream sync and
   review impossible.
10. **Commit messages:** fork commits start with `tla2tex: `; extension commits
    that only move the pointer start with `Bump tlaplus submodule: `.

## Context for the design work

The original author's own list of planned enhancements is in
`tlaplus/tlatools/org.lamport.tlatools/src/tla2tex/README` ("POSSIBLE
ENHANCEMENTS"). The first target is item 2: turning operator applications into
TeX macros (and identifier-to-symbol substitution such as `alpha` to `\alpha`).
