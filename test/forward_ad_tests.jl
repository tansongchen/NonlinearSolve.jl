@testsetup module ForwardADTesting
using Reexport, NonlinearSolve
@reexport using ForwardDiff, MINPACK, NLsolve, StaticArrays, Sundials, LinearAlgebra

test_f!(du, u, p) = (@. du = u^2 - p)
test_f(u, p) = (@. u^2 - p)

jacobian_f(::Number, p) = 1 / (2 * √p)
jacobian_f(::Number, p::Number) = 1 / (2 * √p)
jacobian_f(u, p::Number) = one.(u) .* (1 / (2 * √p))
jacobian_f(u, p::AbstractArray) = diagm(vec(@. 1 / (2 * √p)))

function solve_with(::Val{mode}, u, alg) where {mode}
    f = if mode === :iip
        solve_iip(p) = solve(NonlinearProblem(test_f!, u, p), alg).u
    elseif mode === :iip_cache
        function solve_iip_init(p)
            cache = SciMLBase.init(NonlinearProblem(test_f!, u, p), alg)
            return SciMLBase.solve!(cache).u
        end
    elseif mode === :oop
        solve_oop(p) = solve(NonlinearProblem(test_f, u, p), alg).u
    elseif mode === :oop_cache
        function solve_oop_init(p)
            cache = SciMLBase.init(NonlinearProblem(test_f, u, p), alg)
            return SciMLBase.solve!(cache).u
        end
    end
    return f
end

compatible(::Any, ::Val{:oop}) = true
compatible(::Any, ::Val{:oop_cache}) = true
compatible(::Number, ::Val{:iip}) = false
compatible(::AbstractArray, ::Val{:iip}) = true
compatible(::StaticArray, ::Val{:iip}) = false
compatible(::Number, ::Val{:iip_cache}) = false
compatible(::AbstractArray, ::Val{:iip_cache}) = true
compatible(::StaticArray, ::Val{:iip_cache}) = false

compatible(::Any, ::Number) = true
compatible(::Number, ::AbstractArray) = false
compatible(u::AbstractArray, p::AbstractArray) = size(u) == size(p)

compatible(u::Number, ::SciMLBase.AbstractNonlinearAlgorithm) = true
compatible(u::Number, ::Union{CMINPACK, NLsolveJL, KINSOL}) = true
compatible(u::AbstractArray, ::SciMLBase.AbstractNonlinearAlgorithm) = true
compatible(u::AbstractArray{T, N}, ::KINSOL) where {T, N} = N == 1  # Need to be fixed upstream
compatible(u::StaticArray{S, T, N}, ::KINSOL) where {S <: Tuple, T, N} = false
compatible(u::StaticArray, ::SciMLBase.AbstractNonlinearAlgorithm) = true
compatible(u::StaticArray, ::Union{CMINPACK, NLsolveJL, KINSOL}) = false
compatible(u, ::Nothing) = true

compatible(::Any, ::Any) = true
compatible(::CMINPACK, ::Val{:iip_cache}) = false
compatible(::CMINPACK, ::Val{:oop_cache}) = false
compatible(::NLsolveJL, ::Val{:iip_cache}) = false
compatible(::NLsolveJL, ::Val{:oop_cache}) = false
compatible(::KINSOL, ::Val{:iip_cache}) = false
compatible(::KINSOL, ::Val{:oop_cache}) = false

export test_f!, test_f, jacobian_f, solve_with, compatible
end

@testitem "ForwardDiff.jl Integration" setup=[ForwardADTesting] tags=[:core] begin
    @testset for alg in (
        NewtonRaphson(),
        TrustRegion(),
        LevenbergMarquardt(),
        PseudoTransient(; alpha_initial = 10.0),
        Broyden(),
        Klement(),
        DFSane(),
        nothing,
        NLsolveJL(),
        CMINPACK(),
        KINSOL(; globalization_strategy = :LineSearch)
    )
        us = (2.0, @SVector[1.0, 1.0], [1.0, 1.0], ones(2, 2), @SArray ones(2, 2))

        alg isa CMINPACK && Sys.isapple() && continue

        @testset "Scalar AD" begin
            for p in 1.0:0.1:100.0, u0 in us, mode in (:iip, :oop, :iip_cache, :oop_cache)
                compatible(u0, alg) || continue
                compatible(u0, Val(mode)) || continue
                compatible(alg, Val(mode)) || continue

                sol = solve(NonlinearProblem(test_f, u0, p), alg)
                if SciMLBase.successful_retcode(sol)
                    gs = abs.(ForwardDiff.derivative(solve_with(Val{mode}(), u0, alg), p))
                    gs_true = abs.(jacobian_f(u0, p))
                    if !(isapprox(gs, gs_true, atol = 1e-5))
                        @error "ForwardDiff Failed for u0=$(u0) and p=$(p) with $(alg)" forwardiff_gradient=gs true_gradient=gs_true
                    else
                        @test abs.(gs)≈abs.(gs_true) atol=1e-5
                    end
                end
            end
        end

        @testset "Jacobian" begin
            for u0 in us,
                p in ([2.0, 1.0], [2.0 1.0; 3.0 4.0]),
                mode in (:iip, :oop, :iip_cache, :oop_cache)

                compatible(u0, p) || continue
                compatible(u0, alg) || continue
                compatible(u0, Val(mode)) || continue
                compatible(alg, Val(mode)) || continue

                sol = solve(NonlinearProblem(test_f, u0, p), alg)
                if SciMLBase.successful_retcode(sol)
                    gs = abs.(ForwardDiff.jacobian(solve_with(Val{mode}(), u0, alg), p))
                    gs_true = abs.(jacobian_f(u0, p))
                    if !(isapprox(gs, gs_true, atol = 1e-5))
                        @show sol.retcode, sol.u
                        @error "ForwardDiff Failed for u0=$(u0) and p=$(p) with $(alg)" forwardiff_jacobian=gs true_jacobian=gs_true
                    else
                        @test abs.(gs)≈abs.(gs_true) atol=1e-5
                    end
                end
            end
        end
    end
end
