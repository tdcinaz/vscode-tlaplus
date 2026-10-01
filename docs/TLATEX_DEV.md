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
   so every teammate and every agent session gets the same toolchain. Claude
   Code's auth and history persist in a named volume across rebuilds.

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

The `tlatex:test` target runs, by default, JUnit tests matching `tla2tex/*`:

```sh
npm run tlatex:test                 # all tla2tex tests
bash scripts/tlatex-dev.sh test "tla2tex/MySpecificTest*"
```

**Heads-up:** upstream `tlaplus/tlaplus` currently has **no** JUnit tests under
`test/tla2tex/`. Part of the overhaul is adding them there (in your fork). The
target above is already wired, so tests run as soon as you add them. Tests are
compiled with `ant … compile compile-test` and executed via the `test-set`
Ant target — the same mechanism the upstream `tlc2`/`tla2sany` suites use.

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
PR and push that touches the submodule pointer, the dev script, or the
fixtures. It checks out the submodule, builds the jar with JDK 17, runs the
`test/tla2tex/*` JUnit tests, typesets every fixture, and uploads the jar and
the typeset output as artifacts. Because the checkout uses `submodules: true`,
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
