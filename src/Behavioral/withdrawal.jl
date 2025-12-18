"""
Withdrawal Utilization Models.

Implements utilization-based withdrawal rates for GLWB products.
Higher utilization → more withdrawals taken relative to maximum allowed.

Theory
------
[T1] Base utilization adjusted by age and duration:
    utilization(t) = base_util × f(age, duration, ITM)

[T2] SOA 2018 calibration uses:
- Duration-based ramp-up (11% year 1 → 54% year 10)
- Age-based curve (5% at 55 → 65% at 77)
- ITM sensitivity factors (1.0 OTM → 2.11 deep ITM)

References:
- SOA 2018 VA GLB Utilization Study (Tables 1-17, 1-18, Figure 1-44)
"""


# =============================================================================
# Simple Withdrawal Model
# =============================================================================

"""
    calculate_withdrawal(config::WithdrawalConfig, gwb, av, withdrawal_rate, age) -> WithdrawalResult

Calculate withdrawal amount using simple utilization model.

[T1] withdrawal_amount = utilization_rate × max_allowed

# Arguments
- `config::WithdrawalConfig`: Withdrawal configuration
- `gwb::Real`: Guaranteed Withdrawal Benefit value
- `av::Real`: Current account value
- `withdrawal_rate::Real`: Annual withdrawal rate (e.g., 0.05 for 5%)
- `age::Int`: Current age of annuitant

# Returns
- `WithdrawalResult`: Calculated withdrawal with diagnostics

# Example
```julia
config = WithdrawalConfig(base_utilization=0.50, age_sensitivity=0.02)
result = calculate_withdrawal(config, 100_000.0, 90_000.0, 0.05, 70)
result.withdrawal_amount  # Actual withdrawal taken
```
"""
function calculate_withdrawal(
    config::WithdrawalConfig,
    gwb::Real,
    av::Real,
    withdrawal_rate::Real,
    age::Int
)
    # Validate inputs
    gwb >= 0 || throw(ArgumentError("GWB cannot be negative, got $gwb"))
    av >= 0 || throw(ArgumentError("AV cannot be negative, got $av"))
    withdrawal_rate >= 0 || throw(ArgumentError("withdrawal_rate must be >= 0, got $withdrawal_rate"))

    # Maximum allowed withdrawal
    max_allowed = gwb * withdrawal_rate

    # Calculate utilization based on age
    # Utilization increases with age (more likely to withdraw as older)
    age_adjustment = max(0, age - 65) * config.age_sensitivity
    utilization_rate = config.base_utilization + age_adjustment

    # Apply bounds
    utilization_rate = clamp(utilization_rate, config.min_utilization, config.max_utilization)

    # Calculate withdrawal
    withdrawal_amount = utilization_rate * max_allowed

    # Cannot withdraw more than AV (if AV < max_allowed)
    withdrawal_amount = min(withdrawal_amount, av)

    return WithdrawalResult(
        withdrawal_amount,
        utilization_rate,
        max_allowed,
        1.0,  # No duration factor in simple model
        1.0 + age_adjustment / config.base_utilization,  # Relative age factor
        1.0   # No ITM factor in simple model
    )
end


# =============================================================================
# SOA-Calibrated Withdrawal Model
# =============================================================================

"""
    calculate_withdrawal(config::SOAWithdrawalConfig, gwb, av, withdrawal_rate, duration, age; moneyness=nothing) -> WithdrawalResult

Calculate SOA-calibrated withdrawal using 2018 VA GLB Utilization Study.

[T2] Incorporates:
- Duration-based utilization ramp-up
- Age-based utilization curve
- ITM sensitivity factors
- Multiplicative or additive factor combination

# Arguments
- `config::SOAWithdrawalConfig`: SOA-calibrated configuration
- `gwb::Real`: Guaranteed Withdrawal Benefit value
- `av::Real`: Current account value
- `withdrawal_rate::Real`: Annual withdrawal rate (e.g., 0.05 for 5%)
- `duration::Int`: Contract duration in years (1-indexed)
- `age::Int`: Current age of annuitant
- `moneyness::Union{Real,Nothing}=nothing`: GWB/AV ratio (computed if not provided)

# Returns
- `WithdrawalResult`: Calculated withdrawal with diagnostics

# Example
```julia
config = SOAWithdrawalConfig(use_itm_sensitivity=true)
result = calculate_withdrawal(config, 100_000.0, 80_000.0, 0.05, 5, 70)
result.utilization_rate  # SOA-calibrated utilization
```
"""
function calculate_withdrawal(
    config::SOAWithdrawalConfig,
    gwb::Real,
    av::Real,
    withdrawal_rate::Real,
    duration::Int,
    age::Int;
    moneyness::Union{Real, Nothing} = nothing
)
    # Validate inputs
    gwb >= 0 || throw(ArgumentError("GWB cannot be negative, got $gwb"))
    av >= 0 || throw(ArgumentError("AV cannot be negative, got $av"))
    withdrawal_rate >= 0 || throw(ArgumentError("withdrawal_rate must be >= 0, got $withdrawal_rate"))
    duration > 0 || throw(ArgumentError("Duration must be positive, got $duration"))

    # Maximum allowed withdrawal
    max_allowed = gwb * withdrawal_rate

    # Calculate moneyness if not provided
    if moneyness === nothing
        moneyness = av > 0 ? (gwb / av) : 1.0
    end

    # Get duration factor
    duration_factor = if config.use_duration_curve
        interpolate_utilization_by_duration(duration)
    else
        0.30  # Default 30% utilization
    end

    # Get age factor
    age_factor = if config.use_age_curve
        interpolate_utilization_by_age(age)
    else
        0.40  # Default 40% utilization
    end

    # Get ITM sensitivity factor
    itm_factor = if config.use_itm_sensitivity && moneyness > 1.0
        get_itm_sensitivity_factor(moneyness; continuous=config.use_continuous_itm)
    else
        1.0
    end

    # Combine factors
    utilization_rate = _combine_utilization_factors(
        duration_factor,
        age_factor,
        itm_factor,
        config.combination_method
    )

    # Apply bounds
    utilization_rate = clamp(utilization_rate, config.min_utilization, config.max_utilization)

    # Calculate withdrawal
    withdrawal_amount = utilization_rate * max_allowed

    # Cannot withdraw more than AV
    withdrawal_amount = min(withdrawal_amount, av)

    return WithdrawalResult(
        withdrawal_amount,
        utilization_rate,
        max_allowed,
        duration_factor,
        age_factor,
        itm_factor
    )
end


"""
    _combine_utilization_factors(duration_factor, age_factor, itm_factor, method) -> Float64

Combine utilization factors using specified method.

[T2] Methods:
- :multiplicative: Use duration as base, adjust for age deviation from reference
- :additive: Simple average of duration and age, scaled by ITM
"""
function _combine_utilization_factors(
    duration_factor::Real,
    age_factor::Real,
    itm_factor::Real,
    method::Symbol
)
    if method == :multiplicative
        # Use duration as base, adjust for age deviation from reference age (67)
        # Reference age is 67 (SOA midpoint for mature utilization)
        reference_age_util = interpolate_utilization_by_age(67)

        if reference_age_util > 0
            age_adjustment = age_factor / reference_age_util
        else
            age_adjustment = 1.0
        end

        return duration_factor * age_adjustment * itm_factor

    elseif method == :additive
        # Simple average of duration and age effects, scaled by ITM
        return ((duration_factor + age_factor) / 2) * itm_factor

    else
        throw(ArgumentError("method must be :multiplicative or :additive, got $method"))
    end
end


# =============================================================================
# Path-Based Calculations
# =============================================================================

"""
    calculate_path_withdrawals(config, gwb_path, av_path, withdrawal_rate, ages; kwargs...) -> Vector{WithdrawalResult}

Calculate withdrawals along a simulation path.

# Arguments
- `config::Union{WithdrawalConfig, SOAWithdrawalConfig}`: Withdrawal configuration
- `gwb_path::Vector{<:Real}`: Path of GWB values
- `av_path::Vector{<:Real}`: Path of AV values
- `withdrawal_rate::Real`: Annual withdrawal rate
- `ages::Vector{Int}`: Ages at each time step

# Keyword Arguments (for SOAWithdrawalConfig)
- `moneyness_path::Union{Vector{<:Real}, Nothing}=nothing`: Pre-computed moneyness

# Returns
- `Vector{WithdrawalResult}`: Withdrawal results at each time step
"""
function calculate_path_withdrawals(
    config::WithdrawalConfig,
    gwb_path::Vector{<:Real},
    av_path::Vector{<:Real},
    withdrawal_rate::Real,
    ages::Vector{Int}
)
    n = length(gwb_path)
    length(av_path) == n || throw(ArgumentError(
        "Path lengths must match: gwb=$(length(gwb_path)), av=$(length(av_path))"
    ))
    length(ages) == n || throw(ArgumentError(
        "Ages length must match path length: ages=$(length(ages)), path=$n"
    ))

    results = Vector{WithdrawalResult}(undef, n)

    for t in 1:n
        results[t] = calculate_withdrawal(
            config,
            gwb_path[t],
            av_path[t],
            withdrawal_rate,
            ages[t]
        )
    end

    return results
end

function calculate_path_withdrawals(
    config::SOAWithdrawalConfig,
    gwb_path::Vector{<:Real},
    av_path::Vector{<:Real},
    withdrawal_rate::Real,
    ages::Vector{Int};
    moneyness_path::Union{Vector{<:Real}, Nothing} = nothing
)
    n = length(gwb_path)
    length(av_path) == n || throw(ArgumentError(
        "Path lengths must match: gwb=$(length(gwb_path)), av=$(length(av_path))"
    ))
    length(ages) == n || throw(ArgumentError(
        "Ages length must match path length: ages=$(length(ages)), path=$n"
    ))
    if moneyness_path !== nothing
        length(moneyness_path) == n || throw(ArgumentError(
            "Moneyness path length must match: moneyness=$(length(moneyness_path)), path=$n"
        ))
    end

    results = Vector{WithdrawalResult}(undef, n)

    for t in 1:n
        m = moneyness_path !== nothing ? moneyness_path[t] : nothing
        results[t] = calculate_withdrawal(
            config,
            gwb_path[t],
            av_path[t],
            withdrawal_rate,
            t,  # duration = time step (1-indexed)
            ages[t];
            moneyness=m
        )
    end

    return results
end


# =============================================================================
# Utility Functions
# =============================================================================

"""
    total_withdrawals(results::Vector{WithdrawalResult}) -> Float64

Sum all withdrawal amounts from a path.
"""
function total_withdrawals(results::Vector{WithdrawalResult})
    return sum(r.withdrawal_amount for r in results)
end


"""
    average_utilization(results::Vector{WithdrawalResult}) -> Float64

Calculate average utilization rate across a path.
"""
function average_utilization(results::Vector{WithdrawalResult})
    isempty(results) && return 0.0
    return sum(r.utilization_rate for r in results) / length(results)
end


"""
    withdrawal_amounts(results::Vector{WithdrawalResult}) -> Vector{Float64}

Extract withdrawal amounts from results.
"""
function withdrawal_amounts(results::Vector{WithdrawalResult})
    return [r.withdrawal_amount for r in results]
end


"""
    utilization_rates(results::Vector{WithdrawalResult}) -> Vector{Float64}

Extract utilization rates from results.
"""
function utilization_rates(results::Vector{WithdrawalResult})
    return [r.utilization_rate for r in results]
end


# =============================================================================
# Withdrawal Efficiency Metrics
# =============================================================================

"""
    withdrawal_efficiency(withdrawn::Real, max_allowed::Real) -> Float64

Calculate withdrawal efficiency (actual / maximum).

[T1] Efficiency = actual withdrawal / maximum allowed
- Efficiency = 1.0 means full utilization
- Efficiency < 1.0 means leaving money on the table

# Example
```julia
withdrawal_efficiency(4_000.0, 5_000.0)  # 0.80 (80% efficiency)
```
"""
function withdrawal_efficiency(withdrawn::Real, max_allowed::Real)
    max_allowed > 0 || return 0.0
    return withdrawn / max_allowed
end


"""
    path_withdrawal_efficiency(results::Vector{WithdrawalResult}) -> Float64

Calculate average withdrawal efficiency across a path.
"""
function path_withdrawal_efficiency(results::Vector{WithdrawalResult})
    isempty(results) && return 0.0
    efficiencies = [withdrawal_efficiency(r.withdrawal_amount, r.max_allowed) for r in results]
    return sum(efficiencies) / length(efficiencies)
end


# =============================================================================
# Diagnostic Functions
# =============================================================================

"""
    get_utilization_surface(; duration_range=1:15, age_range=55:85, moneyness=1.0) -> Matrix{Float64}

Generate utilization surface across duration and age dimensions.

# Arguments
- `duration_range::AbstractRange{Int}`: Duration values (default 1:15)
- `age_range::AbstractRange{Int}`: Age values (default 55:85)
- `moneyness::Real=1.0`: Fixed moneyness for surface

# Returns
- `Matrix{Float64}`: Utilization rates (rows=duration, cols=age)
"""
function get_utilization_surface(;
    duration_range::AbstractRange{Int} = 1:15,
    age_range::AbstractRange{Int} = 55:85,
    moneyness::Real = 1.0
)
    n_dur = length(duration_range)
    n_age = length(age_range)
    surface = zeros(Float64, n_dur, n_age)

    for (i, d) in enumerate(duration_range)
        for (j, a) in enumerate(age_range)
            surface[i, j] = combined_utilization(d, a; moneyness=moneyness)
        end
    end

    return surface
end


"""
    utilization_by_itm(; moneyness_range=0.8:0.05:2.0, age=70, duration=5) -> Dict{Float64, Float64}

Calculate utilization across different ITM levels.

# Arguments
- `moneyness_range::AbstractRange`: Moneyness values to evaluate
- `age::Int=70`: Fixed age
- `duration::Int=5`: Fixed duration

# Returns
- `Dict{Float64, Float64}`: Mapping of moneyness to utilization rate
"""
function utilization_by_itm(;
    moneyness_range::AbstractRange = 0.8:0.05:2.0,
    age::Int = 70,
    duration::Int = 5
)
    return Dict(
        m => combined_utilization(duration, age; moneyness=m)
        for m in moneyness_range
    )
end
