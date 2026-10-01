# TLATeX overhaul — developer workflow

This guide sets up a reproducible loop for overhauling the **TLATeX typesetter**.
The short version for agents and new teammates is [CLAUDE.md](../CLAUDE.md)
(also reachable as `AGENTS.md`); this document is the full reference.

## What you're actually editing

TLATeX (`tla2tex.TLA` / `tla2tex.TeX`) is **Java** and lives in the
[`tlaplus/tlaplus`](https://github.com/tlaplus/tlaplus) repo under
`tlatools/org.lamport.tlatools/src/tla2tex/`. It ships compiled inside
`tla2tools.jar`. This VS Code extension does **not** contain the typesetter — it
only shells out to the jar (see `runTex` in [src/tla2tools.ts](../src/tla2tools.ts),
which runs `java -cp tools/tla2tools.jar tla2tex.TLA …`).

So the loop is: **edit the Java source → rebuild `tla2tools.jar` → run the
tla2tex tests and/or swap the jar into this extension and use *Export module to
LaTeX/PDF*.** The [scripts/tlatex-dev.sh](../scripts/tlatex-dev.sh) helper (and
matching `npm run tlatex:*` scripts) automate every step.

## Where the source lives

The Java source is the **`tlaplus/` git submodule**, our fork
[`tdcinaz/tlaplus`](https://github.com/tdcinaz/tlaplus) on branch
**`tlatex-overhaul`** (see [.gitmodules](../.gitmodules)). This repo records the
exact submodule commit it builds against, so checking out any extension commit
also tells you which Java source goes with it.

Inside `tlaplus/`, `origin` is our fork and `upstream` is `tlaplus/tlaplus`.

## One-time setup

1. **Open in the Dev Container** (`Dev Containers: Reopen in Container`). The
   container includes a **JDK 17**, **Ant**, **TeX Live**, **Node 22**, the
   **GitHub CLI**, and **Claude Code**, plus the recommended VS Code extensions
   (Java pack, LaTeX Workshop, Claude Code). On create it runs
   `npm install && npm run tlatex:setup`. This is the reproducible environment,
   so every teammate and every agent session gets the same toolchain. The
   host's `~/.claude` directory is bind-mounted into the container, so Claude
   Code settings, memory, and history are shared and survive rebuilds.

2. **Verify prerequisites and set up the submodule:**

   ```sh
   npm run tlatex:doctor   # confirms JDK/Ant/git are present
   npm run tlatex:setup    # inits ./tlaplus at the pinned commit, on branch tlatex-overhaul
   ```

   `setup` is safe to re-run. It also configures the shallow clone so it can
   fetch/push `tlatex-overhaul` and fetch `upstream/master`, and it installs the
   guard hooks described under [Guard hooks](#guard-hooks).

3. **Check where you stand** at any time:

   ```sh
   npm run tlatex:status   # branch/commit of both repos, pushed?, dev jar installed?
   ```

## Inner loop

Edit Java under `tlaplus/tlatools/org.lamport.tlatools/src/tla2tex/`, then:

| Goal | Command |
| --- | --- |
| Fast unit-test feedback | `npm run tlatex:test` |
| Rebuild jar + swap into the extension | `npm run tlatex:dev` |
| Just rebuild the jar | `npm run tlatex:build` |
| Just copy the built jar into `./tools` | `npm run tlatex:install` |
| Typeset spec(s) from the CLI (no VS Code) | `bash scripts/tlatex-dev.sh typeset path/to/Spec.tla [...]` |
| Release jar vs built jar: `.tex` must be identical for the specs in `tests/tlatex-regress.txt` | `npm run tlatex:regress` (or `bash scripts/tlatex-dev.sh regress 20` for the first 20) |
| Regenerate the golden `.tex` files after an *intended* output change | `npm run tlatex:golden` |
| Full verification before pushing (what CI runs) | `npm run tlatex:check` |
| Restore the released jar | `npm run tlatex:restore` |

The same commands are available as VS Code tasks (`Tasks: Run Task` →
`tlatex: …`); `tlatex: test` is the default test task.

### Debugging the typesetter

The launch configuration **Debug tla2tex.TLA on current .tla file** runs
`tla2tex.TLA` under the Java debugger against the `.tla` file in the active
editor, with the same flags the extension uses. It needs the Java extension
pack (recommended in the container) and a prior `npm run tlatex:build` so the
language server has compiled classes.

### End-to-end check inside the extension

After `npm run tlatex:dev`:

1. Start/keep the `npm: watch` build task running.
2. Press **F5** to launch the Extension Development Host.
3. Open a `.tla` file and run **TLA+: Export module to PDF** (or **… to LaTeX**).
   The host runs your freshly built `tla2tex.TLA`.
4. Reload the host (`Developer: Reload Window`) after each `tlatex:dev` to pick
   up a new jar.

> `npm run tlatex:dev` overwrites `tools/tla2tools.jar` with your local build.
> Run `npm run tlatex:restore` to get the released jar back.

## Tests

The `tlatex:test` target runs, by default, the JUnit tests matching `tla2tex/*`:

```sh
npm run tlatex:test                 # all tla2tex tests
bash scripts/tlatex-dev.sh test "tla2tex/TokenizeSpecTest*"
```

Tests live in the fork under `tlatools/org.lamport.tlatools/test/tla2tex/`
(upstream has none there); their input specs and golden files live in
`tlatools/org.lamport.tlatools/test-model/tla2tex/`. They are compiled with
`ant … compile compile-test` (note: `-Werror`) and run through the `test-set`
Ant target, one JVM per test class, like the upstream `tlc2`/`tla2sany` suites.

| Class | What it covers |
| --- | --- |
| `TLA2TexTestSupport` | Helpers: `resetStatics()`, `tokenize()`, `analyze()`, `latexWithoutAlignment()`, `runCli()` |
| `TokenizeSpecTest` | Token shapes the overhaul depends on (keywords vs identifiers, `WF_` split, primes, parens) |
| `CommentFormattingTest` | English prose vs TLA tokens in comments; isolation between specs |
| `GoldenLaTeXTest` | For each `test-model/tla2tex/NAME.tla`, the LaTeX body must equal `NAME.golden.tex` |
| `TypesetWithLaTeXTest` | Runs the real CLI with `pdflatex` on every test spec; skipped if `pdflatex` is absent |

### Writing a test

TLATeX keeps all state in static fields and normally runs once per JVM, so:

- Call `TLA2TexTestSupport.resetStatics()` in `@Before`. It restores every
  `Parameters` option to its default and resets the tokenizer tables and the
  comment tokenizer's quote state (`TokenizeSpec.reset()`,
  `TokenizeComment.reset()`), which otherwise leak from one spec to the next.
- Use `latexWithoutAlignment(specText, dir)` for output tests. It runs the
  whole pipeline except the two LaTeX runs, so every alignment space is zero
  and no TeX installation is needed. `documentBody()` strips the inlined
  `tlatex.sty` preamble.
- Put new input specs in `test-model/tla2tex/`; `GoldenLaTeXTest` picks them
  up automatically. Generate the golden with `npm run tlatex:golden`, read the
  diff, and commit both files.
- Only tests that genuinely need LaTeX should run it; guard them with
  `Assume.assumeTrue(TLA2TexTestSupport.isOnPath("pdflatex"))`.

### Golden files

A golden file is a snapshot of current behaviour, so a diff in one is either
a regression or an intended change. For an intended change run
`npm run tlatex:golden`, review `git -C tlaplus diff` on the `.golden.tex`
files, and commit them with the Java change.

### Release-vs-built regression

`npm run tlatex:regress` typesets every spec listed in
[tests/tlatex-regress.txt](../tests/tlatex-regress.txt) (210 upstream
`test-model` specs) twice, with the committed release `tools/tla2tools.jar`
and with the freshly built jar, and requires the generated `.tex` to be
byte-identical. The overhaul's features are opt-in, so a spec that uses none
of them must typeset exactly as before. It needs `pdflatex` and takes a few
minutes; `bash scripts/tlatex-dev.sh regress 20` runs only the first 20 specs.

## Sample specs for operator parsing

Ready-made specs for the operator-to-TeX-macro work live in
[tests/fixtures/tlatex/](../tests/fixtures/tlatex/): Greek-letter substitution,
operator-application argument capture, nested/multi-line argument boundaries,
and the full range of operator fixities. All parse cleanly with SANY. Typeset
one with:

```sh
bash scripts/tlatex-dev.sh typeset tests/fixtures/tlatex/MacroOperators.tla
```

## Guard hooks

`npm run tlatex:setup` points `core.hooksPath` at [.githooks/](../.githooks/)
in both repos. The hooks only run on commit and enforce the mistakes that are
easiest to make in a two-repo setup:

| Repo | Blocks |
| --- | --- |
| extension | committing `tools/tla2tools.jar` (set `ALLOW_JAR_COMMIT=1` for a real release jar) |
| extension | bumping the `tlaplus` pointer to a commit that is not on `origin/tlatex-overhaul` |
| `tlaplus/` | committing Eclipse `.project` / `.classpath` / `.settings` files |
| `tlaplus/` | committing from a detached HEAD |

Bypass a single commit with `git commit --no-verify`.

## CI

[.github/workflows/tlatex.yml](../.github/workflows/tlatex.yml) runs on every
PR and push that touches the submodule pointer, the dev script, the fixtures,
or the regression list. It checks out the submodule, builds the jar with JDK
17, runs the `test/tla2tex/*` JUnit tests, typesets every fixture (failing on
any LaTeX error in the `.log`, which `tla2tex` itself ignores), runs the
release-vs-built regression, and uploads the jar and the typeset output as
artifacts. Because the checkout uses `submodules: true`,
a pointer to an unpushed fork commit fails the job. Run `npm run tlatex:check`
locally to get the same result before pushing. The pre-existing `CI` and
`Release` workflows are untouched; they test the extension against the
official released jar.

## Committing Java changes (two steps)

A submodule is its own repo. Commit the Java change in the fork, then commit the
updated submodule pointer in this repo:

```sh
# 1. In the fork
cd tlaplus
git add -A && git commit -m "tla2tex: ..."
git push origin tlatex-overhaul

# 2. In the extension repo: record the new submodule commit
cd ..
git add tlaplus
git commit -m "Bump tlaplus submodule: ..."
git push
```

Always **push the fork first**. If you push the extension repo while it points at
a commit that only exists on your machine, teammates' `git submodule update`
fails.

To pick up a teammate's work, run `git pull` then `npm run tlatex:setup` (or
`git submodule update`). To move to the fork's latest `tlatex-overhaul`, even
if it's ahead of the pinned commit, run `git -C tlaplus pull` and commit the
bump as in step 2.

> `git submodule update` checks out the pinned commit as a detached HEAD. Run
> `npm run tlatex:setup` afterwards (or `git -C tlaplus switch tlatex-overhaul`)
> before you commit inside `tlaplus/`.

## Java IDE support (Extension Pack for Java)

Upstream commits Eclipse `.project`/`.settings` files. By default the Java
language server imports them through Maven and rewrites them, which dirties the
submodule. [.vscode/settings.json](../.vscode/settings.json) prevents this: it
disables Maven import, so `org.lamport.tlatools` is imported from its own
`.classpath`, and it excludes the Toolbox and other projects.

It also sets `java.autobuild.enabled` to `false`. The upstream `.classpath`
sends compiler output to `class/`, the same directory the Ant build uses, and
it does not list JUnit. With auto-build on, the language server compiles the
test sources into `class/` without JUnit resolved, and those broken copies
shadow Ant's `test-class` output (symptoms: `@RunWith` ignored,
`NoClassDefFoundError` for JUnit classes). Build with `npm run tlatex:build`
instead; use **Java: Force Java Compilation** only when you need the IDE's own
compile. The Ant `test-set` classpath in the fork also lists `test-class`
before `class` as a second line of defence.

The dev script never calls the Ant `info` target: it depends on a jgit
build-number task that walks the full commit history and fails on the shallow
submodule clone. The script passes the `git.*` manifest properties from plain
git instead.

`npm run tlatex:setup` also adds a per-clone entry to the submodule's
`.git/info/exclude` for the encoding prefs file the language server drops into
the sibling `org.lamport.tlatools.*` projects, so those never show up in
`git status`. Nothing is pushed to the fork for this.

If the submodule shows modified `.project` files or new `.settings/*.prefs`
anyway, they are generated, so discard them and reset the language server:

```sh
git -C tlaplus checkout -- . && git -C tlaplus clean -n   # review, then clean -f
```

Then run **Java: Clean Java Language Server Workspace** in VS Code.

## Syncing with upstream tlaplus

```sh
cd tlaplus
git fetch --depth 50 upstream master   # deepen as needed for the merge base
git merge upstream/master              # or: git rebase upstream/master
git push origin tlatex-overhaul
cd .. && git add tlaplus && git commit -m "Sync tlaplus with upstream"
```

The submodule is shallow (`--depth 1`) to keep clones fast. If a merge/rebase
complains about missing history, run `git -C tlaplus fetch --unshallow origin`.

## How it stays reproducible

- The toolchain (JDK, Ant, LaTeX) is baked into the Dev Container image.
- The exact Java source commit is pinned by the `tlaplus` submodule in this
  repo's history.
- Every action is a single `npm run tlatex:*` command. The submodule is excluded
  from the packaged `.vsix` (see [.vscodeignore](../.vscodeignore)).

A teammate reproduces the whole environment with:

```sh
git clone --recurse-submodules --shallow-submodules https://github.com/tdcinaz/vscode-tlaplus.git
# Reopen in Dev Container: runs npm install && npm run tlatex:setup for you
npm run tlatex:check
```

## Working with agents

- [CLAUDE.md](../CLAUDE.md) is the agent-facing summary: layout, commands, and
  the rules above. Keep it in sync when this workflow changes; `AGENTS.md` is a
  symlink to it for tools that look for that name.
- Run agent sessions inside the Dev Container so they have the Java toolchain.
- Ask agents to finish with `npm run tlatex:check` and `npm run tlatex:status`;
  the second confirms the fork is pushed before a pointer bump.
- The [PR template](../.github/PULL_REQUEST_TEMPLATE.md) lists the same
  checks for reviewers.
