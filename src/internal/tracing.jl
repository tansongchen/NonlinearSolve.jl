"""
    TraceMinimal(freq)
    TraceMinimal(; print_frequency = 1, store_frequency::Int = 1)

Trace Minimal Information

 1. Iteration Number
 2. f(u) inf-norm
 3. Step 2-norm

See also [`TraceWithJacobianConditionNumber`](@ref) and [`TraceAll`](@ref).
"""
@kwdef struct TraceMinimal <: AbstractNonlinearSolveTraceLevel
    print_frequency::Int = 1
    store_frequency::Int = 1
end

"""
    TraceWithJacobianConditionNumber(freq)
    TraceWithJacobianConditionNumber(; print_frequency = 1, store_frequency::Int = 1)

[`TraceMinimal`](@ref) + Print the Condition Number of the Jacobian.

See also [`TraceMinimal`](@ref) and [`TraceAll`](@ref).
"""
@kwdef struct TraceWithJacobianConditionNumber <: AbstractNonlinearSolveTraceLevel
    print_frequency::Int = 1
    store_frequency::Int = 1
end

"""
    TraceAll(freq)
    TraceAll(; print_frequency = 1, store_frequency::Int = 1)

[`TraceWithJacobianConditionNumber`](@ref) + Store the Jacobian, u, f(u), and δu.

!!! warning

    This is very expensive and makes copyies of the Jacobian, u, f(u), and δu.

See also [`TraceMinimal`](@ref) and [`TraceWithJacobianConditionNumber`](@ref).
"""
@kwdef struct TraceAll <: AbstractNonlinearSolveTraceLevel
    print_frequency::Int = 1
    store_frequency::Int = 1
end

for Tr in (:TraceMinimal, :TraceWithJacobianConditionNumber, :TraceAll)
    @eval begin
        $(Tr)(freq) = $(Tr)(; print_frequency = freq, store_frequency = freq)
    end
end

# NonlinearSolve Tracing Utilities
@concrete struct NonlinearSolveTraceEntry{nType}
    iteration::Int
    fnorm
    stepnorm
    condJ
    J
    u
    fu
    δu
end

function __show_top_level(io::IO, entry::NonlinearSolveTraceEntry{nType}) where {nType}
    if entry.condJ === nothing
        @printf io "%-8s %-20s %-20s\n" "----" "-------------" "-----------"
        if nType === :L2
            @printf io "%-8s %-20s %-20s\n" "Iter" "f(u) 2-norm" "Step 2-norm"
        else
            @printf io "%-8s %-20s %-20s\n" "Iter" "f(u) inf-norm" "Step 2-norm"
        end
        @printf io "%-8s %-20s %-20s\n" "----" "-------------" "-----------"
    else
        @printf io "%-8s %-20s %-20s %-20s\n" "----" "-------------" "-----------" "-------"
        if nType === :L2
            @printf io "%-8s %-20s %-20s %-20s\n" "Iter" "f(u) 2-norm" "Step 2-norm" "cond(J)"
        else
            @printf io "%-8s %-20s %-20s %-20s\n" "Iter" "f(u) inf-norm" "Step 2-norm" "cond(J)"
        end
        @printf io "%-8s %-20s %-20s %-20s\n" "----" "-------------" "-----------" "-------"
    end
end

function Base.show(io::IO, entry::NonlinearSolveTraceEntry{nType}) where {nType}
    entry.iteration == 0 && __show_top_level(io, entry)
    if entry.iteration < 0
        # Special case for final entry
        @printf io "%-8s %-20.8e\n" "Final" entry.fnorm
        @printf io "%-28s\n" "----------------------"
    elseif entry.condJ === nothing
        @printf io "%-8d %-20.8e %-20.8e\n" entry.iteration entry.fnorm entry.stepnorm
    else
        @printf io "%-8d %-20.8e %-20.8e %-20.8e\n" entry.iteration entry.fnorm entry.stepnorm entry.condJ
    end
    return nothing
end

function NonlinearSolveTraceEntry(prob::AbstractNonlinearProblem, iteration, fu, δu)
    nType = ifelse(prob isa NonlinearLeastSquaresProblem, :L2, :Inf)
    fnorm = prob isa NonlinearLeastSquaresProblem ? norm(fu, 2) : norm(fu, Inf)
    return NonlinearSolveTraceEntry{nType}(
        iteration, fnorm, norm(δu, 2), nothing, nothing, nothing, nothing, nothing)
end

function NonlinearSolveTraceEntry(prob::AbstractNonlinearProblem, iteration, fu, δu, J)
    nType = ifelse(prob isa NonlinearLeastSquaresProblem, :L2, :Inf)
    fnorm = prob isa NonlinearLeastSquaresProblem ? norm(fu, 2) : norm(fu, Inf)
    return NonlinearSolveTraceEntry{nType}(
        iteration, fnorm, norm(δu, 2), __cond(J), nothing, nothing, nothing, nothing)
end

function NonlinearSolveTraceEntry(prob::AbstractNonlinearProblem, iteration, fu, δu, J, u)
    nType = ifelse(prob isa NonlinearLeastSquaresProblem, :L2, :Inf)
    fnorm = prob isa NonlinearLeastSquaresProblem ? norm(fu, 2) : norm(fu, Inf)
    return NonlinearSolveTraceEntry{nType}(iteration, fnorm, norm(δu, 2), __cond(J),
        __copy(J), __copy(u), __copy(fu), __copy(δu))
end

@concrete struct NonlinearSolveTrace{
    show_trace, store_trace, Tr <: AbstractNonlinearSolveTraceLevel}
    history
    trace_level::Tr
    prob
end

function reset!(trace::NonlinearSolveTrace)
    (trace.history !== nothing && resize!(trace.history, 0))
end

function Base.show(io::IO, trace::NonlinearSolveTrace)
    if trace.history !== nothing
        foreach(entry -> show(io, entry), trace.history)
    else
        print(io, "Tracing Disabled")
    end
    return nothing
end

function init_nonlinearsolve_trace(prob, alg, u, fu, J, δu; show_trace::Val = Val(false),
        trace_level::AbstractNonlinearSolveTraceLevel = TraceMinimal(),
        store_trace::Val = Val(false), uses_jac_inverse = Val(false), kwargs...)
    return init_nonlinearsolve_trace(
        prob, alg, show_trace, trace_level, store_trace, u, fu, J, δu, uses_jac_inverse)
end

function init_nonlinearsolve_trace(prob::AbstractNonlinearProblem, alg, ::Val{show_trace},
        trace_level::AbstractNonlinearSolveTraceLevel, ::Val{store_trace}, u, fu, J,
        δu, ::Val{uses_jac_inverse}) where {show_trace, store_trace, uses_jac_inverse}
    if show_trace
        print("\nAlgorithm: ")
        Base.printstyled(alg, "\n\n"; color = :green, bold = true)
    end
    J_ = uses_jac_inverse ? (trace_level isa TraceMinimal ? J : __safe_inv(J)) : J
    history = __init_trace_history(
        prob, Val{show_trace}(), trace_level, Val{store_trace}(), u, fu, J_, δu)
    return NonlinearSolveTrace{show_trace, store_trace}(history, trace_level, prob)
end

function __init_trace_history(
        prob::AbstractNonlinearProblem, ::Val{show_trace}, trace_level,
        ::Val{store_trace}, u, fu, J, δu) where {show_trace, store_trace}
    !store_trace && !show_trace && return nothing
    entry = __trace_entry(prob, trace_level, 0, u, fu, J, δu)
    show_trace && show(entry)
    store_trace && return NonlinearSolveTraceEntry[entry]
    return nothing
end

function __trace_entry(prob, ::TraceMinimal, iter, u, fu, J, δu, α = 1)
    return NonlinearSolveTraceEntry(prob, iter, fu, δu .* α)
end
function __trace_entry(prob, ::TraceWithJacobianConditionNumber, iter, u, fu, J, δu, α = 1)
    return NonlinearSolveTraceEntry(prob, iter, fu, δu .* α, J)
end
function __trace_entry(prob, ::TraceAll, iter, u, fu, J, δu, α = 1)
    return NonlinearSolveTraceEntry(prob, iter, fu, δu .* α, J, u)
end

function update_trace!(trace::NonlinearSolveTrace{ShT, StT}, iter, u, fu, J, δu,
        α = 1; last::Val{L} = Val(false)) where {ShT, StT, L}
    !StT && !ShT && return nothing

    if L
        nType = ifelse(trace.prob isa NonlinearLeastSquaresProblem, :L2, :Inf)
        fnorm = trace.prob isa NonlinearLeastSquaresProblem ? norm(fu, 2) : norm(fu, Inf)
        entry = NonlinearSolveTraceEntry{nType}(
            -1, fnorm, NaN32, nothing, nothing, nothing, nothing, nothing)
        ShT && show(entry)
        return trace
    end

    show_now = ShT && (mod1(iter, trace.trace_level.print_frequency) == 1)
    store_now = StT && (mod1(iter, trace.trace_level.store_frequency) == 1)
    (show_now || store_now) &&
        (entry = __trace_entry(trace.prob, trace.trace_level, iter, u, fu, J, δu, α))
    store_now && push!(trace.history, entry)
    show_now && show(entry)
    return trace
end

function update_trace!(cache::AbstractNonlinearSolveCache, α = true)
    trace = __getproperty(cache, Val(:trace))
    trace === nothing && return nothing

    J = __getproperty(cache, Val(:J))
    if J === nothing
        update_trace!(
            trace, cache.nsteps + 1, get_u(cache), get_fu(cache), nothing, cache.du, α)
    elseif cache isa ApproximateJacobianSolveCache && store_inverse_jacobian(cache)
        update_trace!(trace, cache.nsteps + 1, get_u(cache), get_fu(cache),
            ApplyArray(__safe_inv, J), cache.du, α)
    else
        update_trace!(trace, cache.nsteps + 1, get_u(cache), get_fu(cache), J, cache.du, α)
    end
end
