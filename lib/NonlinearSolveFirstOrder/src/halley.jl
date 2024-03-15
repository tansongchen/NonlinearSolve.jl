"""
    Halley(; concrete_jac = nothing, linsolve = nothing, linesearch = NoLineSearch(),
        precs = DEFAULT_PRECS, autodiff = nothing)

An experimental Halley's method implementation.
"""
function Halley(; concrete_jac = nothing, linsolve = nothing,
        linesearch = missing, autodiff = nothing)
    return GeneralizedFirstOrderAlgorithm(;
        concrete_jac, name = :Halley, linesearch,
        descent = HalleyDescent(; linsolve), autodiff)
end
