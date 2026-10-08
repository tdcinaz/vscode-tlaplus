# TLATeX overhaul — Phase 1 proposal (source changes)

*Status: proposal, 2026-10-01; P1-4 revised 2026-10-08 to locate macro
arguments with SANY's parse tree instead of parenthesis counting. Analysis of
`tlaplus/tlatools/org.lamport.tlatools/src/tla2tex/` at fork commit `fbceae3`,
which adds tests and two reset hooks but changes no typesetting behaviour.
The build, test and regression infrastructure this plan relies on is in place;
its findings and design are in [TLATEX_HARNESS_NOTES.md](TLATEX_HARNESS_NOTES.md)
and the commands in [TLATEX_DEV.md](TLATEX_DEV.md).*

## 1. Recommendation in brief

Phase 1 should deliver the author's "simpler possibility" from the README first
(identifier → TeX symbol, `alpha` → `\alpha`), then the full operator → macro
rewrite restricted to single-line applications, both driven by a small
directive notation that lives in comments. Macro arguments are located with
SANY's syntax-only parse tree, which is already in `tla2tools.jar`, and then
mapped back onto TLATeX's tokens, which remain the only thing that renders
output. Everything is opt-in, so a spec with
no directives typesets byte-for-byte as it does today, and the release-vs-built
regression (`npm run tlatex:regress`) must stay empty throughout.

Work items in order: **P1-1 shared emitter → P1-2 directives → P1-3 symbols →
P1-4 macros → P1-5 hygiene.** P1-1 through P1-3 and P1-5 are small and
low-risk; P1-4 is the only medium-risk item and is deliberately scoped.

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
  so the same substitution works there. Today `alpha * x` renders as
  `alpha \.{*} x` and `Integral(1, 0, 10)` as `Integral ( 1 ,\, 0 ,\, 10 )`.
- **The symbol table cannot be extended at runtime.** `add`/`pcaladd` are
  private; there is no public registration method.
- **The tokenizer tracks no parenthesis depth** (only comment depth, module
  depth and PlusCal brace depth). But the symbol table already classifies
  `( [ { <<` as `Symbol.LEFT_PAREN` and `) ] } >>` as `RIGHT_PAREN`
  ([BuiltInSymbols.java:277-285](../tlaplus/tlatools/org.lamport.tlatools/src/tla2tex/BuiltInSymbols.java#L277)),
  and `,` as `PUNCTUATION`. Counting these is **not** enough to find
  arguments, as a probe over real tokens showed: `]_` and `>>_` are
  `SUBSCRIPTED`, not `RIGHT_PAREN` (lines 274-275), so `Op([][A]_v)` and
  `Op(<<A>>_v)` never close; and the commas in `\A x, y : P` and
  `LAMBDA u, v : e` sit at argument depth, so `Pair(\A x, y : P, TRUE)` splits
  into three arguments. Parenthesis counting means re-implementing part of the
  TLA+ grammar by hand, which is what the README calls "nontrivial".
- **TLATeX does not use SANY, but SANY's parser is in the same jar.**
  `tla2sany.parser.TLAplusParser(SanyOutput, byte[])` followed by `parse()` and
  `rootNode()` gives the concrete syntax tree for one file without the semantic
  phase, so it needs no module resolution (it parsed a probe with
  `EXTENDS DoesNotExist`). Each `N_OpApplication` node has a `N_GeneralId`
  head and an `N_OpArgs` child whose argument nodes carry begin/end line and
  column; it located every argument in the probe correctly. Both lexers
  expand tabs to 8-column stops, and SANY's 1-based `line:col` maps to
  `Token[line-1]` with `column == col-1` (verified on the probe). TLATeX
  itself still never checks syntax
  ([info.txt](../tlaplus/tlatools/org.lamport.tlatools/src/tla2tex/info.txt)
  line 124), and SANY never sees PlusCal source or TLA+ inside comments.
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
  `Parameters.java` has 30 static option fields; `TokenizeSpec` and
  `TokenizeComment` keep their FSM state in statics (the test support resets
  these between specs via `TokenizeSpec.reset()` / `TokenizeComment.reset()`).
  The build targets Java 11 (`java.release=11`), so new code may use modern
  constructs.
- `TeX.java` duplicates roughly 40-50 % of `TLA.java` (driver skeleton,
  helpers, option parsing).
- Platform-default charsets in every reader/writer (`FileCharReader.java:28`,
  `OutputFileWriter.java:23`). No Unicode operator support: a `∧` is an
  "Illegal lexeme".
- `ExecuteCommand` uses `Runtime.exec(String)` (breaks on paths with spaces)
  and treats only `errorCode < 0` as failure
  ([ExecuteCommand.java:38](../tlaplus/tlatools/org.lamport.tlatools/src/tla2tex/ExecuteCommand.java#L38)),
  so a LaTeX error (exit 1 under `\batchmode`) is silent. The dev script
  compensates by reading the `.log`; the Java should stop needing that.
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

## 3. Phase 1 scope

**Goals**

- A spec author can declare, in the spec itself, that an identifier typesets as
  a TeX symbol and that an operator application typesets as a TeX macro with
  its arguments substituted.
- Output for specs without directives is unchanged (regression stays empty).
- Every behaviour change ships with a JUnit test under `test/tla2tex/` and,
  where it concerns new input shapes, a spec in `test-model/tla2tex/` with a
  reviewed golden.

**Non-goals for phase 1 (deferred, see §6)**

Unicode TLA+ input, generics/collections modernisation, `TeX.java` dedupe,
multi-line macro arguments, the alignment engine, externalising `tlatex.sty`,
README bugs 1/3/4.

## 4. Work items

### P1-1 Single token-emission path — small

Extract the two `switch (tok.type)` bodies into one package-private class,
`TokenRenderer`, with a method that returns the TeX string for a token given
its context (previous/next token, subscript state). Both `InnerWrite*` methods
call it. No behaviour change: goldens unchanged, regression empty.

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
lines, duplicate definitions, and arity mismatch. A spec with only directive
lines and no uses must produce the same body as the spec without them.

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

Tests: a copy of `GreekOperators.tla` with the `preset greek` directive as a
new golden spec; unit tests via `latexWithoutAlignment` for `alpha'`,
`WF_alpha`, `alpha(x)`, and `alpha` in a comment with and without
`-tlaComment`.

### P1-4 Operator application → TeX macro, single-line scope — medium

Design: SANY decides *where* applications and arguments are; TLATeX's tokens
still decide *how* everything is printed. No SANY source is changed.

1. **Find applications** in a new class `MacroSpans`, run before
   `FindAlignments`, and only if the module has at least one `macro` directive
   (so specs without directives never invoke SANY). Its entry point takes the
   source bytes, the `Token[][]` and the directive table, so tests need no
   files; `TLA.runTranslation` passes the bytes of `Parameters.TLAInputFile`.
   Run `new TLAplusParser(new SilentSanyOutput(), bytes).parse()` and walk
   `rootNode()`. For each `N_OpApplication` whose head's last name component
   (`Integral`, or `Integral` in `M!Integral`) matches a macro of the same arity,
   take the argument nodes of `N_OpArgs` (skipping the `(`, `,`, `)` leaves).
   Definitions are found the same way from `N_IdentLHS` (see item 4).
2. **Map spans to tokens.** A SANY location `line:col` corresponds to
   `Token[line-1]` with `column == col-1`. An argument's token range runs from
   the token starting exactly at its begin column to the token covering its
   end column. If any boundary falls between token starts, decline the
   application; this guards against lexers that disagree on a token (for
   example README bug 2, or a non-ASCII character decoded differently before
   P1-5's UTF-8 fix). Record a `MacroApplication{argRanges[]}` on the head token and
   mark interior tokens `hiddenByMacro`.
3. **Fall back when SANY cannot parse.** TLATeX's contract is that it does not
   check syntax, and that stays true: if `parse()` returns false or throws
   (including `TokenMgrError`), no macros are applied, TLATeX prints one
   warning naming the first SANY error, and output is what it would be without
   macro directives. Symbol substitution (P1-3) does not depend on SANY and
   still applies.
4. **Definitions** (`Integral(f, lo, hi) == hi - lo`) are rewritten like any
   other application; SANY distinguishes them (`N_IdentLHS` vs
   `N_OpApplication`), so the `nodef` alternative in open question 3 is a
   one-line switch. Higher-order parameters (`F(op(_, _)) == ...`) are
   declarations, not applications, so they pass through.
5. **Decline when unsafe**: arity mismatch, an application or argument
   spanning more than one line, a boundary mismatch from item 2, or (checked
   after `FindAlignments`) any interior token with `aboveAlign`/`belowAlign`
   set or `isAlignmentPoint`. Declined applications render as today, and
   `Parameters.Debug` (`-debug`) says why. This keeps the alignment engine
   untouched.
6. **Render**: `TokenRenderer` emits the template with `#k` replaced by the
   rendered tokens of argument k (recursively, so `Frac(Abs(-5), Norm(7))`
   nests), then skips to after the `)`. Because both writers share the renderer,
   the alignment run measures the macro's real width.

Why not counting parentheses over `Token[][]`, as the README suggests: see §2.
Fixing that approach requires treating `]_`/`>>_` as closers and suppressing
commas between a binder (`\A`, `\E`, `\AA`, `\EE`, `LAMBDA`) and its `:`, and
each later construct would need the same treatment. With SANY the grammar
stays the parser's job, and phase 2 inherits exact spans for multi-line
applications and user-defined infix/prefix operators.

Why not rebuild TLATeX on SANY's tree: the tree does not keep the layout
(alignment, comment placement) that TLATeX's line/column output depends on, and
it never sees PlusCal source or TLA+ inside comments. So the tree is used only
to find applications.

Why single-line only: output is one `\@x{...}` per source line and alignment
is computed per line. A macro spanning lines (`NestedArguments.tla`, `N3`)
would need either joining lines or emitting partial macros, which is the
alignment-engine work deferred to phase 2. The fixtures already separate the
single-line cases (`MacroOperators.tla`) from the multi-line ones.

Out of scope for phase 1: macros inside PlusCal algorithm text and inside
TLA+ in comments (SANY sees both as comments, so they render as today). The
TLA+ translation of a PlusCal algorithm is ordinary module text and is
rewritten.

Tests: unit tests for `MacroSpans` that parse small modules from strings
(`TLAplusParser` accepts `byte[]`) and tokenize them with `VectorCharReader`,
covering nested parens, a set literal with commas, a tuple, `f[2]`,
`\A x, y : P` and `LAMBDA u, v : e` arguments, `[][A]_v` and `<<A>>_v`
arguments, `M!Op(...)`, nested macro heads, arity mismatch, an argument
continuing on the next line, a tab before the application, an unresolvable
`EXTENDS`, and a module SANY rejects (no macros, one warning, same body as
without directives); a directive-bearing copy of `MacroOperators.tla` as a
golden spec; `NestedArguments.tla` with directives must still typeset, with
`N3` rendered the old way; `render`/`pdfdiff` to eyeball the first real PDFs;
regression empty.

### P1-5 Hygiene fixes — small, each with a test

Small, test-covered, contained changes that improve every user and let the
harness stop compensating:

| Fix | Where |
| --- | --- |
| Treat any non-zero LaTeX exit code as an error; switch to `ProcessBuilder` with an argument list so paths with spaces work | `ExecuteCommand.java` |
| Remove the `looking for file:` print; make the success message use the real output extension | `LaTeXOutput.java:1581`, `TLA.java:265` |
| Return instead of `System.exit(0)` after `-help`/`-info` | `TLA.java:354-358` |
| README bug 2: do not split `WF_`/`SF_` when the preceding token is `.` | `TokenizeSpec.java:996-1000` |
| Read `.tla` and write `.tex` as UTF-8 explicitly | `FileCharReader.java:28`, `OutputFileWriter.java:23` (open question 4) |

The first item is testable end to end: `TypesetWithLaTeXTest` can then assert
a non-zero exit for a spec with a bad `` `^ ... ^' `` region instead of
reading the log.

## 5. Sequencing and estimates

| Item | Depends on | Risk | Size |
| --- | --- | --- | --- |
| P1-1 shared renderer | — | low (regression-guarded) | S |
| P1-2 directives | — | low | S |
| P1-3 symbols | P1-1, P1-2 | low | S |
| P1-4 macros | P1-1, P1-2 | medium | M |
| P1-5 hygiene | — | low | S |

P1-5 can proceed in parallel with P1-1/P1-2. Each item is one fork commit
prefixed `tla2tex:` plus a pointer bump, per CLAUDE.md rule 3, and each must
leave `npm run tlatex:check` green.

## 6. Explicitly deferred to phase 2+

- **Multi-line macro arguments** and any change to `FindAlignments`. SANY
  already reports exact multi-line spans, so the remaining work is output and
  alignment, not finding arguments.
- **Macros in PlusCal source and in TLA+ inside comments**, plus user-defined
  infix/prefix operators as macros (`N_InfixExpr` / `N_PrefixExpr` in the same
  tree walk).
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

- **Alignment regressions** are the main risk and the reason for the
  release-vs-built regression and the "decline when unsafe" rule in P1-4.
- **Upstream sync**: all phase 1 changes stay under `src/tla2tex`,
  `test/tla2tex`, `test-model/tla2tex`. The only upstream file the fork has
  touched is the `test-set` classpath order in `customBuild.xml`.
- **Coupling to SANY's parse tree**: P1-4 reads `TLAplusParser` and the
  `SyntaxTreeConstants` node kinds without changing them. An upstream grammar
  change could alter tree shapes; the `MacroSpans` unit tests pin the shapes
  used, and the boundary check in P1-4 item 2 makes a mismatch decline rather
  than mis-render.
- **Macros require a parseable spec**: a spec with a syntax error silently
  loses its macros (with a warning) until it is fixed. Acceptable because
  macros are opt-in and the extension already runs SANY on save.
- **Directive syntax churn**: pick it once (open question 1); it becomes part
  of users' specs.
- **Comment-side substitution** depends on the existing `isTLA` heuristics,
  which are themselves fragile (README bug 4). Keep it opt-in via directives
  so a wrong classification only affects specs that asked for symbols.

## 8. Decisions needed

1. **Directive syntax.** Proposed `\* @tlatex: <command> <args>`. Alternatives:
   `\* TLATeX: ...` (README wording) or a dedicated prolog block.
2. **Directive lines suppressed from output** (proposed) vs typeset as comments.
3. **Rewrite definitions too?** Proposed yes (`Integral(f, lo, hi) == ...`
   becomes `\int_{lo}^{hi} f == ...`). Alternative: a `nodef` modifier, cheap
   because SANY separates definitions from uses.
4. **UTF-8 by default** for reading and writing. Correct for modern specs, but a
   behaviour change on Windows for non-ASCII comments encoded in cp1252.
5. **Symbol substitution inside comments** on by default when the token is
   classified as TLA (proposed), or only with `-tlaComment`.
6. **When SANY cannot parse the spec**: drop macros with a warning and
   typeset anyway (proposed), or fail the run so the author notices. Falling
   back keeps TLATeX's "does not check syntax" contract.
