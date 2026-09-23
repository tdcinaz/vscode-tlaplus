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

Typeset any of them with the freshly built jar:

  bash scripts/tlatex-dev.sh typeset tests/fixtures/tlatex/MacroOperators.tla

They are syntactically valid TLA+, so they can also be parsed with SANY and
reused as inputs for future JUnit tests under test/tla2tex/ in the tlaplus fork.
