This directory holds TLA+ specs for exercising TLATeX operator parsing while
implementing the "turn operators into TeX macros" enhancement (see the
POSSIBLE ENHANCEMENTS section of the tla2tex source README).

Each spec targets a specific facet of operator parsing:

  GreekOperators.tla   Simple identifier -> symbol substitution (alpha -> \alpha),
                       including the "is it a common word?" ambiguity and
                       identifiers appearing inside comments.
  MacroOperators.tla   Operator application -> macro with sub/superscripts,
                       where the typesetter must capture arguments by counting
                       parentheses, commas and right-parens.
  NestedArguments.tla  Deeply nested and multi-line operator applications that
                       stress argument-boundary detection.
  OperatorZoo.tla      Prefix / infix / postfix / higher-order / mixfix-style
                       user operators, to map the full space the parser must
                       recognize.

The following specs use the phase 1 "@tlatex:" directives (documented in the
INFO text, `java -cp tla2tools.jar tla2tex.TLA -info`, last section):

  GreekOperatorsPreset.tla       GreekOperators.tla plus `preset greek': every
                                 Greek letter name prints as its symbol, also in
                                 comments where TLATeX classifies it as TLA.
  MacroOperatorsDirectives.tla   MacroOperators.tla plus `macro' directives: each
                                 single-line application and definition prints
                                 with its TeX template.
  NestedArgumentsDirectives.tla  NestedArguments.tla plus the same directives:
                                 nested applications nest; the multi-line N3 is
                                 typeset as without directives.

Copies of these three live in test-model/tla2tex/ of the tlaplus fork, where
GoldenLaTeXTest compares their output with reviewed golden files.

Typeset any of them with the freshly built jar:

  bash scripts/tlatex-dev.sh typeset tests/fixtures/tlatex/MacroOperators.tla

They are syntactically valid TLA+, so they can also be parsed with SANY and
reused as inputs for future JUnit tests under test/tla2tex/ in the tlaplus fork.

examples/ holds real-world specs copied from https://github.com/tlaplus/examples
(Paxos, Paxos Commit, Bakery, PlusCal algorithms, TLAPS proofs, the TLA+
grammar, Greek-letter identifiers). They are typeset by `tlatex:check' and
listed in tests/tlatex-regress.txt; see examples/README.txt.
