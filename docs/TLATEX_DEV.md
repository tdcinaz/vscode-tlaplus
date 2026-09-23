# TLATeX overhaul — developer workflow

This guide sets up a reproducible loop for overhauling the **TLATeX typesetter**.

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

## One-time setup

1. **Open in the Dev Container** (`Dev Containers: Reopen in Container`). The
   container now includes a **JDK 17**, **Ant**, **LaTeX**, and Node; `npm
   install` runs automatically on create. This is the reproducible environment —
   every teammate gets an identical toolchain.

2. **Pin the source.** Edit [.tlatools.env](../.tlatools.env) and point it at
   your team's fork + working branch of `tlaplus/tlaplus`:

   ```sh
   TLATOOLS_REPO=https://github.com/<your-org>/tlaplus.git
   TLATOOLS_REF=tlatex-overhaul
   ```

   Commit this file — it is how everyone builds from the same source.

3. **Verify prerequisites and fetch the source:**

   ```sh
   npm run tlatex:doctor   # confirms JDK/Ant/git are present
   npm run tlatex:setup    # shallow-clones the Java source into ./.tlatools (gitignored)
   ```

## Inner loop

Edit Java under `.tlatools/tlatools/org.lamport.tlatools/src/tla2tex/`, then:

| Goal | Command |
| --- | --- |
| Fast unit-test feedback | `npm run tlatex:test` |
| Rebuild jar + swap into the extension | `npm run tlatex:dev` |
| Just rebuild the jar | `npm run tlatex:build` |
| Just copy the built jar into `./tools` | `npm run tlatex:install` |
| Typeset a spec from the CLI (no VS Code) | `bash scripts/tlatex-dev.sh typeset path/to/Spec.tla` |
| Restore the released jar | `npm run tlatex:restore` |

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

## How it stays reproducible

- The toolchain (JDK, Ant, LaTeX) is baked into the Dev Container image.
- The exact source fork/branch is pinned in the committed `.tlatools.env`.
- Every action is a single `npm run tlatex:*` command with no hidden state; the
  cloned source lives in the gitignored `./.tlatools` and never pollutes the
  extension's git history.

A teammate reproduces the whole environment with:

```sh
# after cloning this forked extension repo
# (Reopen in Dev Container, which runs npm install)
npm run tlatex:setup
npm run tlatex:dev
```
