This spec uses the `brace conjunctions' directive: each definition whose
body is a bulleted conjunction list is typeset like a piecewise function,
with a tall left brace in place of the /\ bullets and the defined name and
its == centered vertically on the list. The last definitions show the
cases that are typeset as usual.

------------------------- MODULE ConjunctionBraces -------------------------
\* @tlatex: brace conjunctions
EXTENDS Naturals, FiniteSets

CONSTANTS Proc, MaxCount
VARIABLES pc, count, msgs

\* The list follows the ==.
TypeOK == /\ pc \in [Proc -> {"idle", "busy", "done"}]
          /\ count \in [Proc -> 0..MaxCount]
          /\ msgs \subseteq Proc \X (0..MaxCount)

\* The list starts on the next line; it moves up beside the ==.
Init ==
  /\ pc = [p \in Proc |-> "idle"]
  /\ count = [p \in Proc |-> 0]
  /\ msgs = {}

\* Conjuncts may span lines, contain disjunction lists and end-of-line
\* comments, and a nested definition's list gets its own brace.
Step(p) ==
  /\ pc[p] = "idle"
  /\ \/ count[p] < MaxCount          \* room for another message
     \/ msgs = {}
  /\ LET next == /\ count' = [count EXCEPT ![p] = @ + 1]
                 /\ msgs' = msgs \cup {<<p, count[p]>>}
     IN  next
  /\ pc' = [pc EXCEPT ![p] = "busy"]

\* An invariant with one wide conjunct: it does not fit beside the long
\* name, so the name is on its own line and the brace below it.
EveryProcessThatIsDoneHasSentAtLeastOneMessage ==
  /\ \A p \in Proc : pc[p] = "done" => \E m \in msgs : m[1] = p /\ m[2] < MaxCount
  /\ Cardinality(msgs) <= Cardinality(Proc) * (MaxCount + 1)

\* Typeset as usual: a single conjunct, a comment between the == and the
\* list, and a body that is not just the list.
Single == /\ msgs = {}
Commented == \* every process is idle
  /\ pc = [p \in Proc |-> "idle"]
  /\ msgs = {}
Quantified == \A p \in Proc : /\ count[p] <= MaxCount
                              /\ pc[p] \in {"idle", "busy", "done"}
=============================================================================
