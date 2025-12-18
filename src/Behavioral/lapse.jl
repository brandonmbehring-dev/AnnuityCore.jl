"""
Dynamic Lapse Models.

Implements moneyness-based lapse rates for GLWB/GMWB products.
Higher ITM guarantees → lower lapse rates (rational behavior).

Theory
------
[T1] Base lapse rate adjusted by moneyness factor:
    lapse_rate(t) = base_lapse × f(moneyness)

where moneyness = GWB / AV (guarantee value / account value)
- moneyness < 1: OTM guarantee → higher lapse (rational)
- moneyness > 1: ITM guarantee → lower lapse (rational)
- moneyness = 1: ATM → base lapse

[T2] SOA 2006 calibration adds:
- Duration-based surrender curves (1.4% year 1 → 11.2% year 8)
- Surrender charge cliff effect (2.48x at SC expiration)
- Age-based adjustment factors

References:
- Bauer, Kling & Russ (2008), "Universal Pricing of Guaranteed Minimum Benefits"
- SOA 2006 Deferred Annuity Persistency Study
"""


# =============================================================================
# Simple Lapse Model
# =============================================================================

"""
    calculate_lapse(config::LapseConfig, gwb, av; surrender_period_complete=false) -> LapseResult

Calculate dynamic lapse rate based on moneyness (GWB/AV ratio).

[T1] lapse_rate = base_lapse × f(moneyness)

ITM guarantees (GWB > AV) reduce lapse probability as policyholders
are less likely to surrender a valuable guarantee.

# Arguments
- `config::LapseConfig`: Lapse configuration parameters
- `gwb::Real`: Guaranteed Withdrawal Benefit value
- `av::Real`: Current account value
- `surrender_period_complete::Bool=false`: Whether surrender period has ended

# Returns
- `LapseResult`: Calculated lapse rate with diagnostics

# Example
```julia
config = LapseConfig(base_annual_lapse=0.05, moneyness_sensitivity=1.0)
result = calculate_lapse(config, 110_000.0, 100_000.0)  # ITM guarantee
result.lapse_rate < 0.05  # Lower than base (ITM reduces lapse)
```
"""
function calculate_lapse(
    config::LapseConfig,
    gwb::Real,
    av::Real;
    surrender_period_complete::Bool = false
)
    # Validate inputs
    av > 0 || throw(ArgumentError("Account value must be positive, got $av"))
    gwb >= 0 || throw(ArgumentError("GWB cannot be negative, got $gwb"))

    # Calculate moneyness = AV / GWB
    # Moneyness > 1: AV exceeds guarantee (OTM guarantee) → higher lapse
    # Moneyness < 1: AV below guarantee (ITM guarantee) → lower lapse
    moneyness = gwb > 0 ? (av / gwb) : 1.0

    # Dynamic adjustment factor: factor = moneyness^sensitivity
    adjustment_factor = moneyness ^ config.moneyness_sensitivity

    # Get base rate
    base_rate = config.base_annual_lapse

    # If still in surrender period, reduce lapse significantly
    if !surrender_period_complete
        base_rate = base_rate * 0.2  # 80% reduction during surrender period
    end

    # Apply dynamic adjustment
    lapse_rate = base_rate * adjustment_factor

    # Apply floor and cap
    lapse_rate = clamp(lapse_rate, config.min_lapse, config.max_lapse)

    return LapseResult(lapse_rate, moneyness, base_rate, adjustment_factor)
end


# =============================================================================
# SOA-Calibrated Lapse Model
# =============================================================================

"""
    calculate_lapse(config::SOALapseConfig, gwb, av, duration, years_to_sc_end; age=nothing) -> LapseResult

Calculate SOA-calibrated lapse rate using 2006 Deferred Annuity Persistency Study.

[T2] Incorporates:
- Duration-based surrender curves
- Surrender charge cliff effect (2.48x at SC expiration)
- Optional age-based adjustment
- Moneyness sensitivity for GLWB products

# Arguments
- `config::SOALapseConfig`: SOA-calibrated configuration
- `gwb::Real`: Guaranteed Withdrawal Benefit value
- `av::Real`: Current account value
- `duration::Int`: Contract duration in years (1-indexed)
- `years_to_sc_end::Int`: Years until surrender charge expires (0 = cliff, negative = post-SC)
- `age::Union{Int,Nothing}=nothing`: Owner age for age adjustment

# Returns
- `LapseResult`: Calculated lapse rate with diagnostics

# Example
```julia
config = SOALapseConfig(surrender_charge_length=7, use_sc_cliff_effect=true)
result = calculate_lapse(config, 100_000.0, 100_000.0, 8, 0)  # Year 8, at cliff
result.lapse_rate ≈ 0.112  # 11.2% cliff surrender rate
```
"""
function calculate_lapse(
    config::SOALapseConfig,
    gwb::Real,
    av::Real,
    duration::Int,
    years_to_sc_end::Int;
    age::Union{Int, Nothing} = nothing
)
    # Validate inputs
    av > 0 || throw(ArgumentError("Account value must be positive, got $av"))
    gwb >= 0 || throw(ArgumentError("GWB cannot be negative, got $gwb"))
    duration > 0 || throw(ArgumentError("Duration must be positive, got $duration"))

    # Calculate moneyness for ITM adjustment
    moneyness = gwb > 0 ? (av / gwb) : 1.0

    # Start with duration-based rate from SOA 2006
    if config.use_duration_curve
        base_rate = interpolate_surrender_by_duration(duration; sc_length=config.surrender_charge_length)
    else
        # Use flat rate based on position in SC period
        base_rate = years_to_sc_end > 0 ? 0.03 : 0.08  # Simple in-SC vs post-SC
    end

    # Apply SC cliff effect if enabled
    adjustment_factor = 1.0
    if config.use_sc_cliff_effect
        cliff_multiplier = get_sc_cliff_multiplier(years_to_sc_end)
        # Only apply multiplier if using flat base rate (duration curve already includes cliff)
        if !config.use_duration_curve
            adjustment_factor *= cliff_multiplier
        end
    end

    # Apply age adjustment if enabled and age provided
    if config.use_age_adjustment && age !== nothing
        # Get age-based surrender rate relative to average
        age_rate = interpolate_surrender_by_age(age; surrender_type=:full)
        avg_age_rate = 0.052  # Average from SOA 2006 Table 8
        age_adjustment = age_rate / avg_age_rate
        adjustment_factor *= age_adjustment
    end

    # Apply moneyness sensitivity (ITM reduces lapse)
    if config.moneyness_sensitivity > 0 && gwb > 0
        moneyness_adjustment = moneyness ^ config.moneyness_sensitivity
        adjustment_factor *= moneyness_adjustment
    end

    # Calculate final lapse rate
    lapse_rate = base_rate * adjustment_factor

    # Apply floor and cap
    lapse_rate = clamp(lapse_rate, config.min_lapse, config.max_lapse)

    return LapseResult(lapse_rate, moneyness, base_rate, adjustment_factor)
end


# =============================================================================
# Path-Based Calculations
# =============================================================================

"""
    calculate_path_lapses(config, gwb_path, av_path; kwargs...) -> Vector{Float64}

Calculate lapse rates along a simulation path.

# Arguments
- `config::Union{LapseConfig, SOALapseConfig}`: Lapse configuration
- `gwb_path::Vector{<:Real}`: Path of GWB values
- `av_path::Vector{<:Real}`: Path of AV values

# Keyword Arguments (for LapseConfig)
- `surrender_period_ends::Int=0`: Time step when surrender period ends

# Keyword Arguments (for SOALapseConfig)
- `sc_length::Int=7`: Surrender charge length
- `start_age::Union{Int,Nothing}=nothing`: Starting age

# Returns
- `Vector{Float64}`: Lapse rates at each time step
"""
function calculate_path_lapses(
    config::LapseConfig,
    gwb_path::Vector{<:Real},
    av_path::Vector{<:Real};
    surrender_period_ends::Int = 0
)
    length(gwb_path) == length(av_path) || throw(ArgumentError(
        "Path lengths must match: gwb=$(length(gwb_path)), av=$(length(av_path))"
    ))

    n_steps = length(gwb_path)
    lapse_rates = zeros(Float64, n_steps)

    for t in 1:n_steps
        surrender_complete = t > surrender_period_ends
        result = calculate_lapse(config, gwb_path[t], av_path[t];
                                surrender_period_complete=surrender_complete)
        lapse_rates[t] = result.lapse_rate
    end

    return lapse_rates
end

function calculate_path_lapses(
    config::SOALapseConfig,
    gwb_path::Vector{<:Real},
    av_path::Vector{<:Real};
    sc_length::Int = config.surrender_charge_length,
    start_age::Union{Int, Nothing} = nothing
)
    length(gwb_path) == length(av_path) || throw(ArgumentError(
        "Path lengths must match: gwb=$(length(gwb_path)), av=$(length(av_path))"
    ))

    n_steps = length(gwb_path)
    lapse_rates = zeros(Float64, n_steps)

    for t in 1:n_steps
        duration = t  # Assuming annual steps, 1-indexed
        years_to_sc_end = sc_length - t + 1  # SC ends at year sc_length
        age = start_age !== nothing ? start_age + t - 1 : nothing

        result = calculate_lapse(config, gwb_path[t], av_path[t], duration, years_to_sc_end; age=age)
        lapse_rates[t] = result.lapse_rate
    end

    return lapse_rates
end


# =============================================================================
# Survival Probability
# =============================================================================

"""
    survival_from_lapses(lapse_rates; dt=1.0) -> Vector{Float64}

Calculate cumulative survival probability from lapse rates.

[T1] Survival probability at time t:
    S(t) = ∏_{s=1}^{t} (1 - lapse_rate_s × dt)

# Arguments
- `lapse_rates::Vector{<:Real}`: Lapse rates at each time step
- `dt::Real=1.0`: Time step size in years

# Returns
- `Vector{Float64}`: Cumulative survival probability at each step

# Example
```julia
lapse_rates = [0.05, 0.05, 0.10, 0.08]  # Annual lapse rates
survival = survival_from_lapses(lapse_rates)
# survival[1] = 0.95, survival[2] = 0.9025, survival[3] = 0.8123, survival[4] = 0.7473
```
"""
function survival_from_lapses(lapse_rates::Vector{<:Real}; dt::Real=1.0)
    n = length(lapse_rates)
    survival = ones(Float64, n)

    cumulative = 1.0
    for t in 1:n
        cumulative *= (1.0 - lapse_rates[t] * dt)
        survival[t] = cumulative
    end

    return survival
end


"""
    lapse_probability(lapse_rates; dt=1.0) -> Float64

Calculate total probability of lapse over the path.

[T1] Total lapse probability = 1 - final survival probability

# Arguments
- `lapse_rates::Vector{<:Real}`: Lapse rates at each time step
- `dt::Real=1.0`: Time step size in years

# Returns
- `Float64`: Probability of lapse occurring during the path
"""
function lapse_probability(lapse_rates::Vector{<:Real}; dt::Real=1.0)
    survival = survival_from_lapses(lapse_rates; dt=dt)
    return 1.0 - survival[end]
end


# =============================================================================
# Moneyness Utilities
# =============================================================================

"""
    moneyness_from_state(gwb, av) -> Float64

Calculate moneyness (GWB/AV ratio) from state.

# Arguments
- `gwb::Real`: Guaranteed Withdrawal Benefit value
- `av::Real`: Current account value

# Returns
- `Float64`: Moneyness ratio (>1 means ITM guarantee)
"""
function moneyness_from_state(gwb::Real, av::Real)
    av > 0 || throw(ArgumentError("Account value must be positive"))
    return gwb > 0 ? (gwb / av) : 1.0
end


"""
    is_itm(gwb, av) -> Bool

Check if guarantee is in-the-money (GWB > AV).
"""
is_itm(gwb::Real, av::Real) = gwb > av
