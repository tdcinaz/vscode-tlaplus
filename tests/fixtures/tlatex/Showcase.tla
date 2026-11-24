------------------------------ MODULE Showcase ------------------------------
EXTENDS Reals, Calculus
CONSTANTS alpha, beta, lambda, mu, sigma, theta, x, v, n

Area      == Integral(lambda * x, 0, 10)
Mean      == Frac(Sum(x, 1, n), n)
Deviation == Sqrt(Frac(Sum((x - mu)^2, 1, n), n))
Energy    == alpha * Norm(v) + beta * Abs(theta)
Stable    == \A eps \in {sigma, mu} : Abs(eps - mu) <= sigma

=============================================================================
