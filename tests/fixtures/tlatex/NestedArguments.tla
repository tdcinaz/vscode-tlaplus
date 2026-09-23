This spec stresses argument-boundary detection for the operator-to-macro
rewrite: deeply nested calls, calls spanning multiple lines, and arguments that
contain function application brackets, tuples, and records. A correct parser
must track paren/bracket/brace depth to find each argument's true extent.

---------------------- MODULE NestedArguments ----------------------
EXTENDS Reals, Sequences

Integral(f, lo, hi) == hi - lo
Sum(term, lo, hi)   == hi - lo
Sqrt(x)             == x
Frac(a, b)          == a
Pow(base, exp)      == base

\* Nested to three levels; each inner call is one argument of the outer call.
N1 == Integral(Sqrt(Pow(2, 4)), 0, 10)

\* Inner call appears inside an arithmetic argument.
N2 == Integral(Sqrt(9) + Frac(1, 2), 0, Pow(2, 3))

\* Multi-line call: the argument list is split across several lines and the
\* parser must join them before locating commas.
N3 == Sum(
        Frac(1, Pow(2, 3)) + Sqrt(16),
        1,
        100
      )

\* Function application brackets inside an argument: seq[i] and record.field
\* must not be treated as argument boundaries.
LOCAL seq == <<10, 20, 30>>
LOCAL rec == [ re |-> 1, im |-> 2 ]
N4 == Integral(seq[2] + rec.im, 0, Len(seq))

\* Tuple as a single argument -- its inner comma is not a separator.
N5 == Frac(<<1, 2>> = <<1, 2>>, 3)

\* Doubly nested with a compound superscript, mirroring \int^{a+b}_{c}.
N6(a, b, c, d) == Integral(Pow(a, b) + Frac(c, d), c, Sqrt(d))

====================================================================
