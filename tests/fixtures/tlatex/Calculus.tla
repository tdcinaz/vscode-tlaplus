Helper module for Showcase.tla and ShowcaseDirectives.tla. It gives the
calculus-style operators bodies so the specs parse with SANY; only the call
sites matter for typesetting, so the bodies are placeholders.

---------------------------- MODULE Calculus ----------------------------
EXTENDS Reals

Integral(f, lo, hi)   == hi - lo
Sum(term, lo, hi)     == hi - lo
Frac(a, b)            == a
Sqrt(x)               == x
Norm(v)               == v
Abs(x)                == x

=========================================================================
