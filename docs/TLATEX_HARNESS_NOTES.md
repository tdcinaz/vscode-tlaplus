# TLATeX harness repair and test infrastructure — findings and design

*Record of the work done on 2026-10-01 before any source change to the
typesetter (extension commits `85513a0`, `95bbd10`; fork commit `fbceae3`).
How to use the resulting commands is in [TLATEX_DEV.md](TLATEX_DEV.md); this
document explains what was wrong, what was built, and why it is shaped the
way it is. The phase 1 source-code plan is in
[TLATEX_PHASE1_PROPOSAL.md](TLATEX_PHASE1_PROPOSAL.md).*

## 1. Why this came first

The overhaul changes how TLA+ is typeset, so every change needs a way to prove
two things mechanically: the intended output changed, and nothing else did.
When the work started neither could be shown:

- the Java build did not run at all in the dev container or in CI,
- there were no tests under `test/tla2tex/` (upstream has none),
- a LaTeX error in the output went unnoticed, because `tla2tex` ignores
  LaTeX's exit code and the dev script checked only Java's.

## 2. Defects found and how they were fixed

### 2.1 The Ant build fails on the shallow submodule clone

`scripts/tlatex-dev.sh build` ran `ant info compile compile-test dist`. The
`info` target depends on `git-revision`, a jgit build-number task that walks
the full commit history, and the submodule is a depth-1 clone, so Ant died
with `MissingObjectException` before compiling anything. CI checks out the
submodule the same way and had failed on every run.

**Fix (extension repo):** the script never calls `info`. `ant_tools()` passes
the four `git.*` manifest properties from plain git and invokes
`compile compile-test dist` directly. `fetch --unshallow` was rejected: it
would cost every teammate and every CI run a full clone of `tlaplus/tlaplus`.

### 2.2 LaTeX errors are invisible

`ExecuteCommand` reports an error only for a *negative* exit code
(`ExecuteCommand.java:38`), and `tla2tex` runs LaTeX in `\batchmode`, so a
LaTeX error exits 1, is swallowed, and `tla2tex` still reports success.

**Fix (extension repo):** `typeset` now reads the `.log` after each run, fails
on any line starting with `!`, warns on `Overfull` boxes, and fails if no
`.pdf` was produced. Verified with a spec containing `` `^ \undefinedmacro ^' ``.
Fixing the Java itself is a phase 1 hygiene item.

### 2.3 An empty test suite looked green

Ant's `batchtest` silently runs nothing when the glob matches no files, and
the script only warned. **Fix:** `test` dies when `test/<glob>` matches nothing.

### 2.4 The Java language server pollutes Ant's output directory

The upstream Eclipse `.classpath` sets the output folder to `class/`, the same
directory the Ant `compile` target writes to, and it lists no JUnit jar. With
auto-build on, the VS Code Java language server compiled the new test sources
into `class/` with unresolved JUnit types. Those class files shadowed Ant's
`test-class` output on the test classpath. Symptoms were baffling until traced:
`@RunWith(Parameterized.class)` silently ignored ("Test class should have
exactly one public zero-argument constructor"), and
`NoClassDefFoundError: TemporaryFolder` with a package-less class name.
Upstream's own `BucketStatisticsTest` failed the same way in this container.

**Fix:** `.vscode/settings.json` sets `java.autobuild.enabled` to `false`
(build with `npm run tlatex:build`; use *Java: Force Java Compilation* when
the IDE's own compile is wanted). As a second line of defence the fork's
`customBuild.xml` lists `test-class` before `class` on the `test-set`
classpath; this is the one upstream file the fork touches outside `tla2tex/`.

### 2.5 Comment tokenizer quote state leaks across specs

`TokenizeComment` keeps `inSQuote`/`inDQuote` in statics that `Tokenize` never
resets. Within one spec that is deliberate (a `` `quoted' `` region may span
comments), but when several specs run in one JVM an unbalanced `` ` `` in one
spec's comments made every identifier in the next spec's comments a TLA token.
The first golden file generated was right and the other three were wrong.

**Fix (fork):** package-private `TokenizeComment.reset()`, called by the test
support between specs. Single-spec behaviour is unchanged, as the regression
below proves. `CommentFormattingTest.unbalancedQuoteInOneSpecDoesNotLeakIntoTheNext`
pins it.

### 2.6 Spec identifier tables are never cleared

`TokenizeSpec.identHashTable`, `usedBuiltinHashTable` and `stringHashTable`
accumulate across `Tokenize` calls; `TeX.java` relies on that across the
environments of one document. **Fix (fork):** package-private
`TokenizeSpec.reset()`, again called only between specs in tests.

### 2.7 Smaller things

- The fork's `core.hooksPath` pointed at a macOS host path, so the guard
  hooks were inert in the container. `npm run tlatex:setup` (idempotent)
  rewrites it; run it after switching machines.
- `test-model/UseHideModuleDefsXml.tla` has no `====` line, so `tla2tex`
  rejects it ("Input ended before end of module"). It is the one top-level
  `test-model` spec excluded from the regression list.
- Java hygiene left for phase 1: `looking for file:` debug print on every
  run, success message says `dvi` after `pdflatex`, `System.exit` on
  `-help`/`-info`, `Runtime.exec(String)`.

## 3. Test infrastructure

All of it lives in the fork under `tlatools/org.lamport.tlatools/`.

### 3.1 `test/tla2tex/TLA2TexTestSupport`

TLATeX keeps all state in static fields and expects one run per JVM. The
support class makes it usable from a suite:

- **`resetStatics()`** restores every `public static` non-final field of
  `Parameters` to the value it had at class load (a reflection snapshot, so
  no duplicated defaults in the Java), then calls `TokenizeSpec.reset()` and
  `TokenizeComment.reset()`. Every test calls it in `@Before`.
- **`tokenize()` / `analyze()`** run the front half of
  `TLA.runTranslation` on a spec given as a string (via `VectorCharReader`),
  up to and including `FindAlignments`.
- **`latexWithoutAlignment()`** continues through `WriteLaTeXFile` but skips
  both LaTeX runs and `SetDimensions`. Every alignment space is therefore 0,
  the output is deterministic, and no TeX installation is needed.
  `documentBody()` strips the inlined 930-line `tlatex.sty` preamble.
- **`runCli()`** spawns `tla2tex.TLA` in a child JVM with a chosen working
  directory, because the tool resolves its input and runs LaTeX relative to
  the process's cwd, which a test cannot change in-process.
- Inputs are found through the `basedir` system property that the Ant
  `test-set` target passes, like the SANY and TLC suites.

JUnit's `TemporaryFolder` rule was replaced by explicit temp directories
while chasing §2.4; now that the cause is known the rule would work again,
but the explicit version has no downside.

### 3.2 Test classes

| Class | Purpose |
| --- | --- |
| `TokenizeSpecTest` | Token shapes the overhaul relies on: keywords vs identifiers, `WF_` split from its subscript, prime as a postfix token, parens and commas as `LEFT_PAREN`/`RIGHT_PAREN`/`PUNCTUATION`, prolog/epilog tokens, and that both reset hooks work |
| `CommentFormattingTest` | English prose stays text, spec identifiers in comments become TLA tokens, and the cross-spec quote-state isolation |
| `GoldenLaTeXTest` | Parameterized over `test-model/tla2tex/*.tla`; the LaTeX body must equal `NAME.golden.tex` |
| `TypesetWithLaTeXTest` | Runs the real CLI with the extension's flags on every test spec; asserts exit 0, `.tex` and `.pdf` exist, zero `!` lines in the `.log`; skipped when `pdflatex` is absent |

### 3.3 Golden files

`test-model/tla2tex/NAME.golden.tex` is the zero-alignment document body for
`NAME.tla`. The four fixture specs from `tests/fixtures/tlatex/` were copied
there so the fork's tests are self-contained. A golden is a snapshot of
current behaviour: a diff is a regression or an intended change, and only
`npm run tlatex:golden` (environment variable `TLA2TEX_UPDATE_GOLDEN=1`)
rewrites them. The word list matters here: a capitalised word that is not in
`words.all` (for example "English") is typeset as a TLA token by the
capitalisation rule, which is upstream behaviour, not a harness defect.

### 3.4 Release-vs-built regression

`npm run tlatex:regress` typesets every spec in `tests/tlatex-regress.txt`
with the committed release `tools/tla2tools.jar` (extracted with
`git show HEAD:tools/tla2tools.jar`, so a locally swapped dev jar cannot fool
it) and with the freshly built jar, using the extension's exact flags and real
`pdflatex`, then requires the `.tex` files to be byte-identical. The list is
the 210 of 211 top-level `test-model` specs that typeset cleanly with the
release jar (a sweep on 2026-10-01; one failure, see §2.7). It takes about
three minutes; `regress 20` runs a prefix. The overhaul's features are opt-in,
so this diff must stay empty for the whole of phase 1.

### 3.5 What `check` and CI run

`npm run tlatex:check` = build → all `tla2tex/*` tests → typeset the four
fixtures with the log check → regression (`TLATEX_SKIP_REGRESS=1` skips it).
The TLATeX workflow runs exactly that; its first green run was `95bbd10`,
in about three minutes.

## 4. Inspecting output

A PDF is unreadable to a diff and to an agent, so the dev container now ships
poppler-utils (and the Dockerfile installs it on rebuild):

- `scripts/tlatex-dev.sh render Spec.tla [page|all] [dpi]` writes PNGs next
  to the PDF (gitignored under the fixtures); 110 dpi is enough to judge
  symbols and layout.
- `scripts/tlatex-dev.sh pdfdiff a.pdf b.pdf` renders both page by page and
  pixel-compares them with ImageMagick, keeping red-highlight images for pages
  that differ. The release and built jars were pixel-identical on the fixtures.
- `shellcheck` is installed and the dev script is clean at `-S warning`.

## 5. Baseline behaviour recorded

With the release jar at fork commit `3bae559`:

- All four fixtures typeset with zero LaTeX errors and zero overfull boxes.
- `alpha * x` renders as `alpha \.{*} x`; `Integral(1, 0, 10)` as
  `Integral ( 1 ,\, 0 ,\, 10 )`; identifiers are emitted bare inside the
  math-mode `\@x{...}` line macro.
- Every generated `.tex` carries the full `tlatex.sty` in its preamble
  (about 930 of roughly 1 080 lines for a one-page spec).

## 6. Known limitations

- `tlatex:test` recompiles everything first (`compile` depends on `clean`),
  so the inner loop is about 40 s even for one test class.
- The Ant `test-set` target binds debug port 1044 in the forked JVM
  (upstream configuration); a second concurrent test run on the same machine
  fails to start.
- The regression needs `pdflatex` and real LaTeX runs; a no-LaTeX mode would
  need a CLI flag in the Java, which is not worth adding yet.
- Goldens cover four specs. Add a spec to `test-model/tla2tex/` whenever a
  phase 1 feature needs a new shape of input.
