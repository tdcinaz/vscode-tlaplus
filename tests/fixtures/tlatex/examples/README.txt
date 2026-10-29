Real-world TLA+ specs for exercising TLATeX, copied unmodified from
https://github.com/tlaplus/examples (MIT License, see LICENSE.md here) at
commit 338afd5b8e9b0ab581c1fe88684df9555635e24d (2026-10-28). Paths mirror
upstream's specifications/ folder. The fixtures one level up are synthetic and
target the operator-to-macro work; these show how the typesetter copes with
specs people actually write: hand-aligned conjunction lists, long boxed
comments, PlusCal, hierarchical TLAPS proofs, and unusual lexemes.

  Paxos/Paxos.tla, Voting.tla, Consensus.tla           (Leslie Lamport)
        The canonical Paxos refinement chain. Lamport's own alignment, INSTANCE,
        ENABLED / WF_, and numbered proof steps (<1>1, <2>3) in Voting and
        Consensus.
  transaction_commit/PaxosCommit.tla, TCommit.tla       (Gray, Lamport, Demirbas)
        Classic two-level \E / \A nesting over records; comments use $...$ and
        \item, i.e. TeX inside comments.
  Bakery-Boulangerie/Bakery.tla                         (Lamport, Merz)
        C-syntax PlusCal plus its translation, a user infix operator
        (a \prec b), CASE, and a long TLAPS proof (130+ step labels).
  LoopInvariance/BinarySearch.tla                       (Lamport)
        --fair algorithm (C syntax) with a proof that uses DEFINE, PICK,
        SUFFICES and ASSUME/PROVE.
  N-Queens/QueensPluscal.tla                            (Stephan Merz)
        P-syntax PlusCal (begin/end) inside a block comment.
  chang_roberts/ChangRoberts.tla                        (Stephan Merz)
        C-syntax PlusCal whose algorithm comment contains nested (* *) comments.
  SpecifyingSystems/Syntax/TLAPlusGrammar.tla, BNFGrammars.tla   (Lamport)
        The TLA+ grammar written in TLA+: postfix ^+ / ^*, \o, user infix
        operators & and |, LOCAL INSTANCE, and dozens of keywords and
        punctuation marks as string literals. A tokenizer stress test.
  SpecifyingSystems/CachingMemory/WriteThroughCache.tla,
    InternalMemory.tla, Memory.tla, MemoryInterface.tla  (Lamport)
        Book chapter 5: INSTANCE ... WITH, subscripted [A]_<<...>> actions, and
        the deeply nested junction lists the book is typeset with.
  detector_chan96/EPFailureDetector.tla                 (Konnov, Widder, Tran)
        Uses `delta' as an identifier 19 times: a real target for
        `@tlatex: preset greek'.
  locks_auxiliary_vars/Stuttering.tla                   (Jarod Differdange)
        Uses `Sigma' as an identifier, plus recursive function definitions
        with LET inside IF / ELSE.
  ewd998/EWD998ChanID.tla, EWD998Chan.tla, EWD998.tla,
    AsyncTerminationDetection.tla, Utils.tla            (Markus Kuppe, Merz)
        LAMBDA, RECURSIVE, multi-line EXCEPT with @, a user infix operator
        (a \prec b) defined over several lines, and heavy use of \*
        end-of-line comments.
  tlaps-library/TLAPS.tla, FiniteSetTheorems.tla,
    WellFoundedInduction.tla, NaturalsInduction.tla
        Not examples: TLAPS standard library modules from
        https://github.com/tlaplus/tlapm (library/, BSD 2-clause, see
        tlaps-library/LICENSE) at commit
        62e7a034d5f7fdfeb22a4475f1ceeca646564efc. Paxos, Bakery and
        BinarySearch import them, and neither tla2tools.jar nor
        CommunityModules-deps.jar ships them. They are dense proof modules, so
        they are typeset too.

Every module parses with SANY (the ewd998 specs need SequencesExt and
FiniteSetTheorems needs Functions, both from tools/CommunityModules-deps.jar):

  cd tests/fixtures/tlatex/examples/Paxos
  java -DTLA-Library=../tlaps-library \
       -cp ../../../../../tools/tla2tools.jar:../../../../../tools/CommunityModules-deps.jar \
       tla2sany.SANY Paxos.tla

Every module typesets with the release jar without LaTeX errors. Several
produce overfull-box warnings (EPFailureDetector, EWD998ChanID, EWD998Chan,
Bakery, ChangRoberts), which is upstream behaviour worth keeping an eye on.

Where they are used:

  - npm run tlatex:check typesets them all with the built jar and fails on any
    LaTeX error.
  - tests/tlatex-regress.txt lists them all, so npm run tlatex:regress requires
    the release jar and the built jar to produce byte-identical .tex for them.

Do not edit these files; to refresh them, copy the same paths from a newer
tlaplus/examples commit and update the commit hash above. Typeset output next
to them is gitignored.
