This spec shows a macro directive that typesets Cardinality(S), from the
standard FiniteSets module, as |S| with vertical bars. Each single-line
application prints with the bars, nested applications nest, and the
multi-line application at the end is typeset as usual.

-------------------------- MODULE CardinalityBars --------------------------
\* @tlatex: macro Cardinality/1 \left\vert #1 \right\vert
EXTENDS Naturals, FiniteSets

CONSTANTS Acceptor, Value

\* A plain set name.
N == Cardinality(Acceptor)

\* A set literal and a set built with an operator.
Three   == Cardinality({1, 2, 3})
Subsets == Cardinality(SUBSET Acceptor) = 2^Cardinality(Acceptor)

\* A set comprehension: the commas and colon inside the braces stay part of
\* the single argument.
Big(S, k) == Cardinality({x \in S : x > k})

\* Majority quorums, the usual place cardinality shows up.
Quorum == {Q \in SUBSET Acceptor : Cardinality(Q) * 2 > Cardinality(Acceptor)}

\* Cardinality of a set of sets of cardinality k.
Choose(S, k) == Cardinality({T \in SUBSET S : Cardinality(T) = k})

\* Spread over several lines, so typeset as an ordinary application.
Spread == Cardinality({ v \in Value :
                          v # 0 })
=============================================================================
