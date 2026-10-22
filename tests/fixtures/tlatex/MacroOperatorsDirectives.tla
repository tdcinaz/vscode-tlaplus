This is MacroOperators.tla with macro directives added after the module
header. Each single-line application (and definition) of a directive's
operator is typeset with the directive's TeX template, its arguments
located by SANY. Compare its output with MacroOperators.golden.tex.

---------------------- MODULE MacroOperatorsDirectives ------------
\* @tlatex: macro Integral/3 \int_{#2}^{#3} #1 \, dx
\* @tlatex: macro Sum/3 \sum_{#2}^{#3} #1
\* @tlatex: macro Product/3 \prod_{#2}^{#3} #1
\* @tlatex: macro Sqrt/1 \sqrt{#1}
\* @tlatex: macro Frac/2 \frac{#1}{#2}
\* @tlatex: macro Pow/2 #1^{#2}
\* @tlatex: macro Norm/1 \| #1 \|
\* @tlatex: macro Abs/1 \vert #1 \vert
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
