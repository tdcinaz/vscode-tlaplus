-------------------------- MODULE ShowcaseDirectives --------------------------
\* @tlatex: preset greek
\* @tlatex: macro Integral/3 \int_{#2}^{#3} #1 \, dx
\* @tlatex: macro Sum/3 \sum_{#2}^{#3} #1
\* @tlatex: macro Frac/2 {\displaystyle\frac{#1}{#2}}
\* @tlatex: macro Sqrt/1 \sqrt{#1}
\* @tlatex: macro Norm/1 \| #1 \|
\* @tlatex: macro Abs/1 \vert #1 \vert
EXTENDS Reals, Calculus
CONSTANTS alpha, beta, lambda, mu, sigma, theta, x, v, n

Area      == Integral(lambda * x, 0, 10)
Mean      == Frac(Sum(x, 1, n), n)
Deviation == Sqrt(Frac(Sum((x - mu)^2, 1, n), n))
Energy    == alpha * Norm(v) + beta * Abs(theta)
Stable    == \A eps \in {sigma, mu} : Abs(eps - mu) <= sigma

=============================================================================
