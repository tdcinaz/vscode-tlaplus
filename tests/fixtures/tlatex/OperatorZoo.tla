This spec enumerates the different operator *fixities* and shapes TLATeX must
recognize when deciding what can be rewritten into a TeX macro: prefix, infix,
postfix, higher-order (operator-valued) parameters, and user-defined symbolic
operators. It is a map of the parsing surface, not a semantic model.

---------------------- MODULE OperatorZoo ----------------------
EXTENDS Integers

CONSTANTS x, y, z

\* --- User-defined named operators of varying arity ------------------------
Nullary        == 42
Unary(a)       == a
Binary(a, b)   == a + b
Ternary(a, b, c) == a + b + c

\* --- Higher-order operators (operator-valued parameters) ------------------
\* `op(_, _)` is itself an operator argument; the parser must not confuse the
\* placeholder underscores with real arguments.
Apply2(op(_, _), a, b) == op(a, b)
Map(op(_), s)          == { op(e) : e \in s }
Fold(op(_, _), seed, s) == seed

UsesHof == Apply2(Binary, 1, 2) + Map(Unary, {x, y, z}) = {}

\* --- Infix user operators (symbolic) --------------------------------------
a \oplus b  == a + b
a \otimes b == a * b
a \odot b   == a - b
a \sqcup b  == IF a > b THEN a ELSE b

InfixUse == (x \oplus y) \otimes (z \odot x)

\* --- Prefix and postfix built-ins mixed with user operators ---------------
Neg(a)  == -a                 \* prefix minus
Fact(a) == a                  \* stand-in for a postfix factorial a!
Primed  == x'                 \* postfix prime

\* --- Mixfix-style bracketing that a macro rewrite might target ------------
Floor(a)   == a               \* -> \lfloor a \rfloor
Ceil(a)    == a               \* -> \lceil a \rceil
Bracket(a) == a               \* -> \langle a \rangle

Mixfix == Floor(x) + Ceil(y) + Bracket(z)

\* --- Operators appearing as arguments to other operators ------------------
Compose(f(_), g(_), a) == f(g(a))
Composed == Compose(Neg, Fact, x)

================================================================
