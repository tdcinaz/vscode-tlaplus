# TLATeX overhaul — Phase 1 proposal

*Status: proposal, 2026-10-01. Analysis of `tlaplus/tlatools/org.lamport.tlatools/src/tla2tex/`
at submodule commit `3bae559` (fork branch `tlatex-overhaul`, no fork changes yet).*

## 1. Recommendation in brief

Phase 1 should deliver the author's "simpler possibility" from the README first
(identifier → TeX symbol, `alpha` → `\alpha`), then the full operator → macro
rewrite restricted to single-line applications, both driven by a small
directive notation that lives in comments. Everything is opt-in, so a spec with
no directives typesets byte-for-byte as it does today.

Before any of that, two things have to happen because nothing else can be
verified without them:

1. **The Java build is broken in this workspace.** `npm run tlatex:build` runs
   the Ant `info` target, which depends on a jgit build-number task that walks
   full git history. The submodule is a depth-1 clone, so it fails with
   `MissingObjectException` before compiling a single file. Passing the
   `git.*` properties from plain git and skipping `info` builds in 48 s.
   CI checks out the submodule the same way and will fail the same way.
2. **There is no test infrastructure**, and the pipeline has three traits that
   fight JUnit: all state is static with no reset, alignment needs a real LaTeX
   run, and LaTeX failures are swallowed (only a *negative* exit code is an
   error). A thin test harness that runs the pipeline without LaTeX, plus a
   byte-identical regression check against the existing 649 specs in
   `test-model/`, is the safety net every later item relies on.

Work items in order: **P1-0 harness → P1-1 shared emitter → P1-2 directives →
P1-3 symbols → P1-4 macros → P1-5 hygiene.** Items P1-0 through P1-3 are small
and low-risk; P1-4 is the only medium-risk item and is deliberately scoped.

## 2. What the code looks like today

### Pipeline

`TLA.runTranslation` ([TLA.java:155](../tlaplus/tlatools/org.lamport.tlatools/src/tla2tex/TLA.java#L155))
drives eight static stages:

| Stage | Where | What it produces |
| --- | --- | --- |
| `BuiltInSymbols.Initialize` | `BuiltInSymbols.java:86` | ~280 hard-coded `add(...)` calls filling raw `Hashtable`s: TLA string → `Symbol{TeXString, symbolType, alignmentType}` |
| `TokenizeSpec.Tokenize` | `TokenizeSpec.java:840` | a flat `Token[][]` (one array per source line). Hand-written switch FSM; IDENT vs BUILTIN decided in state `ID` at lines 996-1038 |
| `Token.FindPfStepTokens`, `FixPlusCal` | `Token.java:232`, `TokenizeSpec.java:1789` | proof-step and PlusCal fix-ups |
| `CommentToken.ProcessComments`, `FormatComments.Initialize` | | multi-line comment grouping; loads the 38 639-word `words.all` list |
| `FindAlignments.FindAlignments` | `FindAlignments.java` | sets `aboveAlign` / `belowAlign` / `isAlignmentPoint` / `subscript` on tokens via six heuristic alignment kinds |
| `LaTeXOutput.WriteAlignmentFile` + `RunLaTeX` + `SetDimensions` | `LaTeXOutput.java:52, 477, 490` | a throw-away LaTeX run whose `.log` yields typeset widths, written back into `tok.distFromMargin` / `preSpace` |
| `LaTeXOutput.WriteLaTeXFile` + `RunLaTeX` | `LaTeXOutput.java:821` | the final `.tex` (one `\@x{...}` per spec line) and the `.dvi`/`.pdf` |

Facts that shape the design:

- **Token emission is duplicated.** The alignment writer
  (`InnerWriteAlignmentFile`, lines 106-234) and the output writer
  (`InnerWriteLaTeXFile`, lines 838-1225) each contain their own
  `switch (tok.type)`. Any change to how a token renders must be made twice or
  the alignment widths no longer match the output.
- **Identifiers are emitted bare.** `case Token.IDENT` at
  [LaTeXOutput.java:1208](../tlaplus/tlatools/org.lamport.tlatools/src/tla2tex/LaTeXOutput.java#L1208)
  calls `Misc.TeXifyIdent`, which only escapes `_`. Lines are in math mode
  (the `.sty` remaps letter mathcodes to text italic), so a TeX symbol such as
  `\alpha` can be dropped in place of the identifier. In comments, TLA tokens
  are wrapped in `\ensuremath{}` ([FormatComments.java:1926](../tlaplus/tlatools/org.lamport.tlatools/src/tla2tex/FormatComments.java#L1926)),
  so the same substitution works there.
- **The symbol table cannot be extended at runtime.** `add`/`pcaladd` are
  private; there is no public registration method.
- **The tokenizer tracks no parenthesis depth** (only comment depth, module
  depth and PlusCal brace depth). But the symbol table already classifies
  `( [ { <<` as `Symbol.LEFT_PAREN` and `) ] } >>` as `RIGHT_PAREN`
  ([BuiltInSymbols.java:277-285](../tlaplus/tlatools/org.lamport.tlatools/src/tla2tex/BuiltInSymbols.java#L277)),
  and `,` as `PUNCTUATION`, so argument capture can be a post-tokenization
  pass over `Token[][]` rather than an FSM change.
- **Subscript machinery exists.** `WF_x`, `]_v`, `^` already produce
  `_{...}` / `^{...}` via `Symbol.SUBSCRIPTED` and the per-token `subscript`
  flag; the macro rewrite does not need to invent this.
- **Prolog and epilog are comments.** They are tokenized as PROLOG/EPILOG
  tokens and then handed to `FormatComments.WriteComment` as a paragraph
  comment ([LaTeXOutput.java:913](../tlaplus/tlatools/org.lamport.tlatools/src/tla2tex/LaTeXOutput.java#L913)).
  No code anywhere reads a line as a TLATeX command, which is exactly what the
  README's enhancement 2 says must be introduced.
- **Comment classification machinery is rich.** `TokenizeComment.CTokenOut`
  and `FormatComments.adjustIsTLA` (lines 570-934) decide whether a word in a
  comment is a TLA token, using the spec's identifier set
  (`TokenizeSpec.identHashTable`) and the English word list. Symbol
  substitution in comments can simply piggy-back on `isTLA`.
- **The style file is inlined.** Every generated `.tex` carries the full 932-line
  `tlatex.sty` in its preamble unless `-style` is given. New macros the rewrite
  needs (`\lVert`, `\lfloor`, ...) must come from the `.sty` or a package it
  loads; today it loads only `latexsym`, `ifthen`, `verbatim`.

### Code health

- About 13 300 lines of pre-Java-5 code: raw `Vector`/`Hashtable`/`Enumeration`
  everywhere, zero generics, all state in `public static` fields.
  `Parameters.java` has 30 static option fields and no reset; `TokenizeSpec`
  and `TokenizeComment` keep their FSM state in statics. The build targets
  Java 11 (`java.release=11`), so new code may use modern constructs.
- `TeX.java` duplicates roughly 40-50 % of `TLA.java` (driver skeleton,
  helpers, option parsing).
- Platform-default charsets in every reader/writer (`FileCharReader.java:28`,
  `OutputFileWriter.java:23`). No Unicode operator support: a `∧` is an
  "Illegal lexeme".
- `ExecuteCommand` uses `Runtime.exec(String)` (breaks on paths with spaces)
  and treats only `errorCode < 0` as failure
  ([ExecuteCommand.java:38](../tlaplus/tlatools/org.lamport.tlatools/src/tla2tex/ExecuteCommand.java#L38)),
  so a LaTeX error (exit 1 under `\batchmode`) is silent.
- Leftover debug output: `prependMetaDirToFileName` prints
  `looking for file: ...` on every call ([LaTeXOutput.java:1581](../tlaplus/tlatools/org.lamport.tlatools/src/tla2tex/LaTeXOutput.java#L1581)).
  The success message always says `dvi` even when `-latexCommand pdflatex`
  produced a PDF.
- `System.exit(0)` on `-help`/`-info` (TLA.java:354, 358).
- Known bugs (README BUGS 1-4) map to: `TokenizeComment.java:861-885`
  (spurious space after `` `token'. ``), `TokenizeSpec.java:996-1000`
  (`foo.WF_foo` lexed as `foo . WF_ foo`), the LET/IN alignment class 59 in
  `BuiltInSymbols.java:426-427`, and the capitalisation rule in
  `FormatComments.java:683-716`.

### Harness

- `scripts/tlatex-dev.sh build` fails as described in §1. `test` warns but
  does not fail when no tests match; `typeset` checks only Java's exit code,
  never the LaTeX `.log`; `check` therefore cannot currently detect a LaTeX
  error.
- `test/tla2tex/` does not exist. `compile-test` compiles only `test/` and
  copies only `*.dot`/`*.dump` resources; existing suites locate inputs via
  `System.getProperty("basedir")` + `test-model/`
  ([TestDecimalXMLExport.java:38-40](../tlaplus/tlatools/org.lamport.tlatools/test/tla2sany/xml/TestDecimalXMLExport.java#L38)).
  The `test-set` target forks one JVM per test class (`forkmode="perTest"`)
  and binds a debug port (1044), so static leaks only matter within a class.
- Baseline: all four fixtures typeset with the freshly built jar with zero
  LaTeX errors and zero overfull boxes. `alpha * x` renders today as
  `alpha \.{*} x`; `Integral(1, 0, 10)` as `Integral ( 1 ,\, 0 ,\, 10 )`.

## 3. Phase 1 scope

**Goals**

- A spec author can declare, in the spec itself, that an identifier typesets as
  a TeX symbol and that an operator application typesets as a TeX macro with
  its arguments substituted.
- Output for specs without directives is unchanged.
- Every behaviour has a JUnit test; the harness can prove "unchanged" mechanically.

**Non-goals for phase 1 (deferred, see §6)**

Unicode TLA+ input, generics/collections modernisation, `TeX.java` dedupe,
multi-line macro arguments, the alignment engine, externalising `tlatex.sty`,
README bugs 1/3/4.

## 4. Work items

### P1-0 Harness repair and test infrastructure (extension repo + fork) — small

*Status 2026-10-01: implemented (uncommitted at the time of writing). Two
further defects surfaced while doing it and are fixed as part of P1-0: the
VS Code Java language server compiles test sources into `class/` (the Eclipse
output folder) without JUnit, and those copies shadowed Ant's `test-class`
output; and `TokenizeComment` never resets its quote state, so an unbalanced
`` ` `` in one spec's comments made every identifier in the next spec's
comments a TLA token when several specs run in one JVM.*

1. In `cmd_build` and `cmd_test`, stop invoking `info`; pass
   `-Dgit.revision=$(git rev-parse HEAD) -Dgit.shortRevision=... -Dgit.branch=... -Dgit.tag=`
   and call `compile compile-test dist` directly. Verified to work in this
   container. Alternative (rejected): `fetch --unshallow`, which costs every
   teammate and CI a full clone of `tlaplus/tlaplus`.
2. `cmd_typeset`: after each run, fail if the `.log` contains a line starting
   with `!`, and report overfull boxes as a warning. Also fail when
   `-latexCommand` is given but the `.pdf` is missing.
3. `cmd_test`: fail (not warn) when the glob matches nothing, so CI cannot pass
   on an empty suite.
4. New `cmd_regress`: typeset a configurable list of `test-model/*.tla` specs
   (start with ~50 that have no PlusCal and parse in the released jar) with the
   released jar and the built jar, `-nops`, LaTeX not run (see 5), and `diff`
   the `.tex`. Phase 1 changes must keep this diff empty.
5. Fork: add `TLA2TexTestSupport` under `test/tla2tex/` that
   - resets `Parameters` and tokenizer statics before each test (add a
     package-private `TokenizeSpec.reset()` and `Parameters.reset()`; these are
     the only new statics-touching methods),
   - runs the pipeline on a string via `VectorCharReader` through
     `WriteLaTeXFile` **without** `RunLaTeX`/`SetDimensions`, so every
     `preSpace` is 0 and no LaTeX is needed in unit tests,
   - optionally runs `pdflatex` when it is on `PATH` (tagged tests, skipped
     otherwise).
   Golden files live under `test-model/tla2tex/` next to their `.tla`, found
   via the `basedir` property like the SANY tests.
6. Copy the four fixtures into `test-model/tla2tex/` so the fork's tests are
   self-contained (CI for the fork alone must not depend on this repo).

Acceptance: `npm run tlatex:check` passes in the dev container and CI; a
deliberately injected LaTeX error in a fixture makes it fail.

### P1-1 Single token-emission path — small

Extract the two `switch (tok.type)` bodies into one package-private class,
`TokenRenderer`, with a method that returns the TeX string for a token given
its context (previous/next token, subscript state). Both `InnerWrite*` methods
call it. No behaviour change; `cmd_regress` must show an empty diff.

Rationale: P1-3 and P1-4 change what a token renders as. Doing it in one place
is the only way to guarantee the alignment pass measures what the output
prints. This is the one refactor phase 1 needs; it is confined to
`LaTeXOutput.java` and a new file (rule 9).

### P1-2 Directive notation — small

Introduce one notation that marks a comment line as a tool command, as the
README asks for ("should generalize to arbitrary tools"). Proposed form,
following the `@type:` annotation convention already used by Apalache in TLA+
comments:

```tla
\* @tlatex: symbol alpha \alpha
\* @tlatex: symbol Omega \Omega
\* @tlatex: macro Integral/3 \int_{#2}^{#3} #1
\* @tlatex: macro Norm/1 \lVert #1 \rVert
\* @tlatex: preset greek
```

- Recognised anywhere a comment line can appear: prolog, module body, epilog,
  one-line `\*` comments and lines of `(* ... *)` comments. Scope is the whole
  module regardless of position (directives are collected in a pre-pass over
  the `Token[][]`, before `FindAlignments`).
- Directive lines are removed from the typeset output (like `` `~ ... ~' ``),
  and from `-tlaOut`. A directive the tool does not understand is reported
  with line number and ignored; a well-formed `@othertool:` line is left alone.
- `preset greek` enables the obvious lower/upper-case Greek map
  (`alpha`..`omega`, `Gamma`..`Omega`) in one line.
- Also accept the same lines (without the `\*`) from a file given with
  `-directives file`, so a team can share one table across modules. The VS
  Code extension needs no change for the comment form; a
  `tlaplus.pdf.directivesFile` setting mapping to this flag is a one-line
  follow-up in `buildTexOptions`.

Implementation: new class `Directives` (parser + the two tables: ident → TeX,
operator name/arity → template). Unit tests on the parser, including malformed
lines, duplicate definitions, and arity mismatch.

### P1-3 Identifier → symbol substitution — small

- In `TokenRenderer`, an IDENT token whose string is a key in the symbol table
  renders as `{<TeX>}` instead of `TeXifyIdent(string)`. Whole-token match
  only (`alpha1` is untouched). Primes and subscripts work unchanged because
  `'`, `WF_`, `^` are separate tokens.
- In comments (`FormatComments.java:1926`): apply the same table, but only when
  the comment token has `isTLA == true`. English prose mentioning "alpha"
  therefore stays text unless the existing ambiguity rules (or `-tlaComment`)
  already classify it as a TLA token. This reuses README enhancement 1's
  machinery rather than competing with it.
- `-tlaOut` output is unaffected (it writes the original strings).

Tests: golden `.tex` for `GreekOperators.tla` with and without the preset;
unit tests for `alpha'`, `WF_alpha`, `alpha(x)`, `alpha` in a comment with and
without `-tlaComment`.

### P1-4 Operator application → TeX macro, single-line scope — medium

Design:

1. **Find applications** in a pass over `Token[][]` run before
   `FindAlignments`: an IDENT whose string is a macro name, immediately followed
   by BUILTIN `(` on the same line. Walk forward on that line tracking depth
   over `Symbol.LEFT_PAREN` / `RIGHT_PAREN` symbol types (this covers `(`, `[`,
   `{`, `<<` and their closers, so set literals, tuples, and function
   application inside arguments are handled). Top-level `,` tokens split the
   arguments; the matching `)` ends the application. Record on the head token a
   `MacroApplication{argRanges[]}`; mark interior tokens `hiddenByMacro`.
2. **Decline when unsafe**: arity mismatch, the closing `)` is on another
   line, or (checked after `FindAlignments`) any interior token has
   `aboveAlign`/`belowAlign` set or `isAlignmentPoint`. Declined applications
   render as today, and `-debug` says why. This keeps the alignment engine
   untouched.
3. **Render**: `TokenRenderer` emits the template with `#k` replaced by the
   rendered tokens of argument k (recursively, so `Frac(Abs(-5), Norm(7))`
   nests), then skips to after the `)`. Because both writers share the renderer,
   the alignment run measures the macro's real width.
4. **Definitions** (`Integral(f, lo, hi) == hi - lo`) are rewritten like any
   other application. See open question 3.
5. Higher-order placeholders (`op(_, _)`) tokenize as IDENT `_` and are not
   macro heads, so they pass through.

Why single-line only: output is one `\@x{...}` per source line and alignment
is computed per line. A macro spanning lines (`NestedArguments.tla`, `N3`)
would need either joining lines or emitting partial macros, which is the
alignment-engine work deferred to phase 2. The fixtures already separate the
single-line cases (`MacroOperators.tla`) from the multi-line ones.

Tests: unit tests for the span finder over hand-built `Token[][]` (nested
parens, set literal with commas, tuple, `seq[2]`, arity mismatch, unclosed
paren at end of line, nested macro heads); golden `.tex` for
`MacroOperators.tla`; a fixture check that `NestedArguments.tla` still typesets
with `N3` rendered the old way; `cmd_regress` diff empty.

### P1-5 Hygiene fixes — small, each with a test

Small, test-covered, contained changes that improve every user and make the
harness honest:

| Fix | Where |
| --- | --- |
| Treat any non-zero LaTeX exit code as an error; switch to `ProcessBuilder` with an argument list so paths with spaces work | `ExecuteCommand.java` |
| Remove the `looking for file:` print; make the success message use the real output extension | `LaTeXOutput.java:1581`, `TLA.java:265` |
| Return instead of `System.exit(0)` after `-help`/`-info` | `TLA.java:354-358` |
| README bug 2: do not split `WF_`/`SF_` when the preceding token is `.` | `TokenizeSpec.java:996-1000` |
| Read `.tla` and write `.tex` as UTF-8 explicitly | `FileCharReader.java:28`, `OutputFileWriter.java:23` (open question 4) |

## 5. Sequencing and estimates

| Item | Depends on | Risk | Size |
| --- | --- | --- | --- |
| P1-0 harness + tests | — | low | S |
| P1-1 shared renderer | P1-0 | low (regress-guarded) | S |
| P1-2 directives | P1-0 | low | S |
| P1-3 symbols | P1-1, P1-2 | low | S |
| P1-4 macros | P1-1, P1-2 | medium | M |
| P1-5 hygiene | P1-0 | low | S |

P1-0 and P1-5 can proceed in parallel with P1-1/P1-2. Each item is one fork
commit prefixed `tla2tex:` plus a pointer bump, per CLAUDE.md rule 3.

## 6. Explicitly deferred to phase 2+

- **Multi-line macro arguments** and any change to `FindAlignments`.
- **Unicode TLA+ input** (`∧ ∨ ∈ ≜`): needs a code-point-based `CharReader`
  and tokenizer; upstream's PlusCal already moved to code points (2024).
- **Collections/generics modernisation and `TeX.java` dedupe**: valuable but
  violates rule 9 unless done as a dedicated, review-isolated sync point.
- **Externalising `tlatex.sty`** (ship as a package, stop inlining 930 lines).
- **README bugs 1, 3, 4** (need a `CToken` width field; alignment heuristics;
  comment capitalisation rule).
- **`x_1` as a math subscript** (today prints a literal underscore). Cheap, but
  changes output for every existing spec, so it needs a flag and a decision.

## 7. Risks

- **Alignment regressions** are the main risk and the reason for `cmd_regress`
  and the "decline when unsafe" rule in P1-4.
- **Static state in tests**: mitigated by the reset methods and the per-class
  JVM fork Ant already uses.
- **Upstream sync**: all changes stay under `src/tla2tex`, `test/tla2tex`,
  `test-model/tla2tex`; the only shared file touched is none (the build fix is
  in this repo's script, not `customBuild.xml`).
- **Directive syntax churn**: pick it once (open question 1); it becomes part
  of users' specs.

## 8. Decisions needed

1. **Directive syntax.** Proposed `\* @tlatex: <command> <args>`. Alternatives:
   `\* TLATeX: ...` (README wording) or a dedicated prolog block.
2. **Directive lines suppressed from output** (proposed) vs typeset as comments.
3. **Rewrite definitions too?** Proposed yes (`Integral(f, lo, hi) == ...`
   becomes `\int_{lo}^{hi} f == ...`). Alternative: a `nodef` modifier.
4. **UTF-8 by default** for reading and writing. Correct for modern specs, but a
   behaviour change on Windows for non-ASCII comments encoded in cp1252.
5. **Symbol substitution inside comments** on by default when the token is
   classified as TLA (proposed), or only with `-tlaComment`.
