This spec exercises simple identifier-to-symbol substitution for TLATeX.
The goal: identifiers such as `alpha`, `beta`, `pi` should be typesettable as
\alpha, \beta, \pi, while ordinary English words (e.g. `sum`, `max`) must be
left alone. Note how the same names also appear inside the comments below,
which TLATeX scans for TLA tokens.

---------------------- MODULE GreekOperators ----------------------
EXTENDS Reals

\* Greek-letter identifiers that SHOULD map to TeX symbols.
CONSTANTS alpha, beta, gamma, delta, epsilon, theta, lambda,
          mu, nu, pi, rho, sigma, tau, phi, chi, psi, omega

\* Uppercase variants (\Gamma, \Delta, \Sigma, \Omega, ...).
CONSTANTS Gamma, Delta, Lambda, Sigma, Phi, Psi, Omega

\* Ordinary words that must NOT be turned into symbols even though they are
\* valid identifiers: sum, max, min, log, sin, cos.
VARIABLES sum, max, min

\* Mixed expression: a linear combination alpha*x + beta*y + gamma*z.
LinearCombo(x, y, z) == alpha * x + beta * y + gamma * z

\* Circle circumference 2*pi*r -- here `pi` should become \pi but `r` stays r.
Circumference(r) == 2 * pi * r

\* Greek letters used inside quantifiers and set constructors (the bound
\* variables are plain names so they don't shadow the Greek constants).
SmallAngles == { r \in Real : r <= pi }
Rotation == \E r \in Real : r + psi = omega

\* Ambiguity check: `nu` (uncommon) vs `min`/`max` (common words). Only the
\* uncommon Greek identifiers should be symbolized, including this reference
\* to sigma and tau appearing inside a comment.
Spectrum == sigma + tau + mu + nu + chi

\* Uppercase Greek in a summation-like context.
Aggregate == Gamma + Delta + Sigma + Omega + Lambda + Phi + Psi

Init == /\ sum = 0
        /\ max = 0
        /\ min = 0

Next == /\ sum' = sum + LinearCombo(alpha, beta, gamma)
        /\ max' = max
        /\ min' = min

Spec == Init /\ [][Next]_<<sum, max, min>>
===================================================================
