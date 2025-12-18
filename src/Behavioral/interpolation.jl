"""
Interpolation Functions for SOA-Based Behavioral Models.

[T2] Interpolation and lookup functions using SOA benchmark data.

This module provides functions to:
1. Interpolate surrender rates by contract duration
2. Calculate surrender charge cliff effects
3. Interpolate GLWB utilization by duration and age
4. Calculate ITM sensitivity factors
"""


# =============================================================================
# Generic Interpolation Utilities
# =============================================================================

"""
    linear_interpolate(x, points; extrapolate=true) -> Float64

[T1] Linear interpolation/extrapolation from a Dict of {x: y} points.

# Arguments
- `x::Real`: The x value to interpolate at
- `points::Dict{Int,Float64}`: Dictionary mapping x values to y values
- `extrapolate::Bool=true`: If true, use nearest value beyond range

# Returns
- `Float64`: Interpolated y value

# Example
```julia
points = Dict(1 => 0.1, 5 => 0.5, 10 => 0.8)
linear_interpolate(3, points)  # Returns 0.3
```
"""
function linear_interpolate(x::Real, points::Dict{Int,Float64}; extrapolate::Bool=true)
    # Sort keys for proper interpolation
    keys_sorted = sort(collect(keys(points)))

    # Handle boundary cases
    if x <= keys_sorted[1]
        return points[keys_sorted[1]]
    end
    if x >= keys_sorted[end]
        return points[keys_sorted[end]]
    end

    # Find bracketing points
    for i in 1:(length(keys_sorted) - 1)
        x0, x1 = keys_sorted[i], keys_sorted[i + 1]
        if x0 <= x <= x1
            y0, y1 = points[x0], points[x1]
            # Linear interpolation
            t = (x - x0) / (x1 - x0)
            return y0 + t * (y1 - y0)
        end
    end

    # Fallback (should not reach)
    return points[keys_sorted[end]]
end


# =============================================================================
# Surrender Rate Functions (SOA 2006)
# =============================================================================

"""
    interpolate_surrender_by_duration(duration; sc_length=7) -> Float64

Interpolate surrender rate from SOA 2006 Table 6.

[T2] Based on 7-year surrender charge schedule data.

# Arguments
- `duration::Int`: Contract duration in years (1-indexed)
- `sc_length::Int=7`: Surrender charge period length

# Returns
- `Float64`: Annual surrender rate (decimal, e.g., 0.05 = 5%)

# Examples
```julia
interpolate_surrender_by_duration(1)   # Year 1 → 0.014
interpolate_surrender_by_duration(8)   # Post-SC cliff → 0.112
```

# Notes
For SC lengths other than 7, the function scales the duration
to match the 7-year pattern and applies the cliff effect.
"""
function interpolate_surrender_by_duration(duration::Int; sc_length::Int=7)
    duration > 0 || throw(ArgumentError("Duration must be positive, got $duration"))

    if sc_length == 7
        # Direct lookup from SOA data
        if haskey(SOA_2006_SURRENDER_BY_DURATION_7YR_SC, duration)
            return SOA_2006_SURRENDER_BY_DURATION_7YR_SC[duration]
        end
        # Extrapolate for durations > 11
        if duration > 11
            return SOA_2006_SURRENDER_BY_DURATION_7YR_SC[11]
        end
        # Interpolate
        return linear_interpolate(duration, SOA_2006_SURRENDER_BY_DURATION_7YR_SC)
    end

    # Scale for different SC lengths
    if duration <= sc_length
        # During SC period: scale to 7-year equivalent
        scaled_duration = (duration / sc_length) * 7
        return linear_interpolate(scaled_duration, SOA_2006_SURRENDER_BY_DURATION_7YR_SC)
    else
        # Post-SC: years after SC expiration
        years_post_sc = duration - sc_length
        # Map to year 8+ in 7-year data
        equivalent_duration = 7 + years_post_sc
        return linear_interpolate(
            min(equivalent_duration, 11),
            SOA_2006_SURRENDER_BY_DURATION_7YR_SC
        )
    end
end


"""
    get_sc_cliff_multiplier(years_to_sc_end) -> Float64

Get surrender charge cliff multiplier from SOA 2006 Table 5.

[T2] The cliff effect is the spike in surrenders when SC expires.

# Arguments
- `years_to_sc_end::Int`: Years until surrender charge expires
  - Positive: years remaining in SC period
  - Zero: SC just expired (cliff year)
  - Negative: years after SC expired

# Returns
- `Float64`: Multiplier relative to normal in-SC surrender rate

# Examples
```julia
get_sc_cliff_multiplier(3)   # 3+ years remaining → 1.0
get_sc_cliff_multiplier(0)   # SC just expired → 2.48 (the cliff!)
get_sc_cliff_multiplier(-1)  # 1 year after SC → ~1.91
```
"""
function get_sc_cliff_multiplier(years_to_sc_end::Int)
    base_rate = SOA_2006_SC_POSITION[:years_remaining_3plus]

    if years_to_sc_end >= 3
        return 1.0  # Base rate
    elseif years_to_sc_end == 2
        return SOA_2006_SC_POSITION[:years_remaining_2] / base_rate
    elseif years_to_sc_end == 1
        return SOA_2006_SC_POSITION[:years_remaining_1] / base_rate
    elseif years_to_sc_end == 0
        return SOA_2006_SC_CLIFF_MULTIPLIER  # 2.48x
    elseif years_to_sc_end == -1
        return SOA_2006_SC_POSITION[:post_sc_year_1] / base_rate
    elseif years_to_sc_end == -2
        return SOA_2006_SC_POSITION[:post_sc_year_2] / base_rate
    else  # years_to_sc_end <= -3
        return SOA_2006_SC_POSITION[:post_sc_year_3plus] / base_rate
    end
end


"""
    get_post_sc_decay_factor(years_after_sc) -> Float64

Get post-SC decay factor relative to cliff year.

[T2] After the SC cliff, surrender rates decay over 3 years.

# Arguments
- `years_after_sc::Int`: Years after SC expiration (0 = cliff year)

# Returns
- `Float64`: Decay factor relative to cliff year (1.0 at cliff)

# Examples
```julia
get_post_sc_decay_factor(0)  # Cliff year → 1.0
get_post_sc_decay_factor(1)  # Year after → 0.77
get_post_sc_decay_factor(5)  # 5 years after → 0.60
```
"""
function get_post_sc_decay_factor(years_after_sc::Int)
    if years_after_sc <= 0
        return SOA_2006_POST_SC_DECAY[0]
    elseif years_after_sc == 1
        return SOA_2006_POST_SC_DECAY[1]
    elseif years_after_sc == 2
        return SOA_2006_POST_SC_DECAY[2]
    else
        return SOA_2006_POST_SC_DECAY[3]
    end
end


"""
    interpolate_surrender_by_age(age; surrender_type=:full) -> Float64

Interpolate surrender rate by owner age from SOA 2006 Table 8.

[T2] Full surrender is flat by age; partial withdrawal increases with age.

# Arguments
- `age::Int`: Owner age
- `surrender_type::Symbol=:full`: Either :full or :partial

# Returns
- `Float64`: Annual surrender/withdrawal rate (decimal)

# Examples
```julia
interpolate_surrender_by_age(65, surrender_type=:full)     # → 0.058
interpolate_surrender_by_age(72, surrender_type=:partial)  # → 0.315 (peak at RMD age)
```
"""
function interpolate_surrender_by_age(age::Int; surrender_type::Symbol=:full)
    if surrender_type == :full
        return linear_interpolate(age, SOA_2006_FULL_SURRENDER_BY_AGE)
    elseif surrender_type == :partial
        return linear_interpolate(age, SOA_2006_PARTIAL_WITHDRAWAL_BY_AGE)
    else
        throw(ArgumentError("surrender_type must be :full or :partial, got $surrender_type"))
    end
end


# =============================================================================
# GLWB Utilization Functions (SOA 2018)
# =============================================================================

"""
    interpolate_utilization_by_duration(duration) -> Float64

Interpolate GLWB utilization from SOA 2018 Table 1-17.

[T2] Utilization ramps from 11% (year 1) to 54% (year 10+).

# Arguments
- `duration::Int`: Contract duration in years (1-indexed)

# Returns
- `Float64`: Utilization rate (decimal, e.g., 0.50 = 50%)

# Examples
```julia
interpolate_utilization_by_duration(1)   # → 0.111
interpolate_utilization_by_duration(10)  # → 0.518
```
"""
function interpolate_utilization_by_duration(duration::Int)
    duration > 0 || throw(ArgumentError("Duration must be positive, got $duration"))

    if haskey(SOA_2018_GLWB_UTILIZATION_BY_DURATION, duration)
        return SOA_2018_GLWB_UTILIZATION_BY_DURATION[duration]
    end

    # Extrapolate for durations > 11
    if duration > 11
        return SOA_2018_GLWB_UTILIZATION_BY_DURATION[11]
    end

    return linear_interpolate(duration, SOA_2018_GLWB_UTILIZATION_BY_DURATION)
end


"""
    interpolate_utilization_by_age(age) -> Float64

Interpolate GLWB utilization from SOA 2018 Table 1-18.

[T2] Utilization increases with age: 5% at 55 to 65% at 77.

# Arguments
- `age::Int`: Current age of annuitant

# Returns
- `Float64`: Utilization rate (decimal)

# Examples
```julia
interpolate_utilization_by_age(55)  # → 0.05
interpolate_utilization_by_age(72)  # → 0.59
```
"""
function interpolate_utilization_by_age(age::Int)
    return linear_interpolate(age, SOA_2018_GLWB_UTILIZATION_BY_AGE)
end


"""
    get_itm_sensitivity_factor(moneyness; continuous=false) -> Float64

Get ITM sensitivity multiplier from SOA 2018 Figure 1-44.

[T2] Withdrawal rates increase when guarantee is in-the-money.

# Arguments
- `moneyness::Real`: GWB / AV ratio (>1 means ITM guarantee)
  - <= 1.0: Not ITM (baseline)
  - 1.0-1.25: Shallow ITM
  - 1.25-1.50: Moderate ITM
  - > 1.50: Deep ITM
- `continuous::Bool=false`: If true, use smooth interpolation

# Returns
- `Float64`: Multiplier to apply to base utilization rate

# Examples
```julia
get_itm_sensitivity_factor(0.9)   # OTM → 1.0
get_itm_sensitivity_factor(1.1)   # Shallow ITM → 1.39
get_itm_sensitivity_factor(1.6)   # Deep ITM → 2.11
```
"""
function get_itm_sensitivity_factor(moneyness::Real; continuous::Bool=false)
    if continuous
        return _get_itm_sensitivity_continuous(moneyness)
    else
        return _get_itm_sensitivity_discrete(moneyness)
    end
end

function _get_itm_sensitivity_discrete(moneyness::Real)
    if moneyness <= 1.0
        return SOA_2018_ITM_SENSITIVITY[:not_itm]
    elseif moneyness <= 1.25
        return SOA_2018_ITM_SENSITIVITY[:itm_100_125]
    elseif moneyness <= 1.50
        return SOA_2018_ITM_SENSITIVITY[:itm_125_150]
    else
        return SOA_2018_ITM_SENSITIVITY[:itm_150_plus]
    end
end

function _get_itm_sensitivity_continuous(moneyness::Real)
    if moneyness <= 1.0
        return 1.0
    end

    # Linear interpolation between breakpoints
    for i in 1:(length(SOA_2018_ITM_BREAKPOINTS) - 1)
        x0, y0 = SOA_2018_ITM_BREAKPOINTS[i]
        x1, y1 = SOA_2018_ITM_BREAKPOINTS[i + 1]
        if x0 <= moneyness <= x1
            t = (moneyness - x0) / (x1 - x0)
            return y0 + t * (y1 - y0)
        end
    end

    # Beyond last breakpoint
    return SOA_2018_ITM_BREAKPOINTS[end][2]
end


# =============================================================================
# Combined Utilization Calculation
# =============================================================================

"""
    combined_utilization(duration, age; moneyness=1.0, method=:multiplicative) -> Float64

Combine duration, age, and ITM effects for total utilization.

[T2] Combines SOA 2018 data for comprehensive utilization estimate.

# Arguments
- `duration::Int`: Contract duration in years
- `age::Int`: Current age of annuitant
- `moneyness::Real=1.0`: GWB / AV ratio (for ITM sensitivity)
- `method::Symbol=:multiplicative`: How to combine factors

# Returns
- `Float64`: Combined utilization rate (capped at 1.0)

# Example
```julia
combined_utilization(5, 70, moneyness=1.0)  # Duration=21.5%, Age=59%
```

# Notes
The multiplicative method assumes factors are independent:
    util = base_duration × (age_factor / base_age) × itm_factor

This prevents double-counting the base utilization effect.
"""
function combined_utilization(
    duration::Int,
    age::Int;
    moneyness::Real = 1.0,
    method::Symbol = :multiplicative
)
    # Get base components
    util_duration = interpolate_utilization_by_duration(duration)
    util_age = interpolate_utilization_by_age(age)
    itm_factor = get_itm_sensitivity_factor(moneyness)

    if method == :multiplicative
        # Use duration as base, adjust for age deviation from 67
        # Reference age is 67 (SOA midpoint for mature utilization)
        base_age_util = interpolate_utilization_by_age(67)

        # Scale duration by relative age effect
        age_adjustment = base_age_util > 0 ? (util_age / base_age_util) : 1.0

        # Apply factors
        combined = util_duration * age_adjustment * itm_factor

    elseif method == :additive
        # Simple average of duration and age effects, scaled by ITM
        combined = ((util_duration + util_age) / 2) * itm_factor

    else
        throw(ArgumentError("method must be :multiplicative or :additive, got $method"))
    end

    # Cap at 100%
    return min(combined, 1.0)
end


# =============================================================================
# Diagnostic Functions
# =============================================================================

"""
    get_surrender_curve(; sc_length=7, max_duration=15) -> Dict{Int,Float64}

Generate full surrender rate curve for given SC length.

# Arguments
- `sc_length::Int=7`: Surrender charge period length
- `max_duration::Int=15`: Maximum duration to calculate

# Returns
- `Dict{Int,Float64}`: Mapping of duration to surrender rate
"""
function get_surrender_curve(; sc_length::Int=7, max_duration::Int=15)
    return Dict(
        d => interpolate_surrender_by_duration(d; sc_length=sc_length)
        for d in 1:max_duration
    )
end


"""
    get_utilization_curve(; age=70, max_duration=15) -> Dict{Int,Float64}

Generate GLWB utilization curve by duration for fixed age.

# Arguments
- `age::Int=70`: Annuitant age (for age adjustment)
- `max_duration::Int=15`: Maximum duration to calculate

# Returns
- `Dict{Int,Float64}`: Mapping of duration to utilization rate
"""
function get_utilization_curve(; age::Int=70, max_duration::Int=15)
    return Dict(
        d => combined_utilization(d, age; moneyness=1.0)
        for d in 1:max_duration
    )
end
