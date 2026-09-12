# Superseded discovery-time qualification

The 0.05-second warm-up could expire during Julia compilation before reaching
the search loop. The first LSS native/default measurement included residual
compilation; these times must not be used for native/JuMP overhead or solver
speed comparisons. Feasible incumbents were independently valid.

The replacement qualification uses two two-second warm-up solves per JIT path.
These original traces remain intact. Full-size 0.2-second preflight records are
functional integration evidence only; they are not performance measurements.
