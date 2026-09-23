This spec exercises operator-application -> TeX-macro rewriting for TLATeX.
The target transformation from the README is, for example:

    Integral(a + b, c, d)   =>   \int_{c}^{d} (a + b) \, dx

To do this the typesetter must locate each argument by scanning forward and
counting parentheses, commas, and the matching right-paren. The definitions
below give every "macro-like" operator a well-formed body so the module still
parses with SANY; only the *call sites* matter for typesetting.

---------------------- MODULE MacroOperators ----------------------
EXTENDS Reals

\* Operators intended to become TeX macros with sub/superscripts.
Integral(f, lo, hi) == hi - lo          \* -> \int_{lo}^{hi} f \, dx
Sum(term, lo, hi)   == hi - lo          \* -> \sum_{lo}^{hi} term
Product(term, lo, hi) == hi - lo        \* -> \prod_{lo}^{hi} term
Sqrt(x)             == x                 \* -> \sqrt{x}
Frac(a, b)          == a                 \* -> \frac{a}{b}
Pow(base, exp)      == base              \* -> base^{exp}
Norm(v)             == v                 \* -> \lVert v \rVert
Abs(x)              == x                 \* -> \lvert x \rvert

\* Single-argument call.
A == Sqrt(2)

\* Multi-argument calls: arguments are simple atoms.
B == Integral(1, 0, 10)
C == Frac(3, 4)
D == Pow(2, 8)

\* Arguments that are themselves compound expressions containing commas-in-sets
\* and parentheses -- the parser must not mistake the inner comma/parens for
\* argument separators.
E == Integral(2 * 3 + 1, 0, 10)
F == Sum((1 + 2) * 3, 1, 100)
G == Frac(Abs(-5), Norm(7))

\* A set literal inside an argument: the commas here are NOT argument
\* separators of Product.
H == Product({1, 2, 3} = {1, 2, 3}, 1, 5)

\* Realistic combination mirroring the README example \int^{a+b}_{c} d.
Example(a, b, c, d) == Integral(a + b, c, d)

===================================================================
