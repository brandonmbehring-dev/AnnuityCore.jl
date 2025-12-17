"""
GLWB Rollup and Ratchet Mechanics.

[T1] Rollup provisions increase the GWB during the deferral period,
providing incentive for delayed withdrawals.

Two primary methods:
- Simple rollup: Linear growth
- Compound rollup: Exponential growth

Ratchet provisions step-up the GWB to the account value on anniversaries,
protecting against market downturns while locking in gains.
"""


"""
    simple_rollup(base, rate, years, cap_years) -> Float64

Calculate GWB using simple (linear) rollup.

[T1] Formula: GWB = base × (1 + rate × min(years, cap_years))

# Arguments
- `base::Float64`: Initial rollup base (typically initial premium)
- `rate::Float64`: Annual rollup rate (e.g., 0.06 for 6%)
- `years::Float64`: Years since issue
- `cap_years::Int`: Maximum years of rollup

# Example
```julia
simple_rollup(100000.0, 0.06, 5.0, 10)  # => 130000.0
simple_rollup(100000.0, 0.06, 15.0, 10) # => 160000.0 (capped at 10 years)
```
"""
function simple_rollup(base::Float64, rate::Float64, years::Float64, cap_years::Int)
    effective_years = min(years, Float64(cap_years))
    return base * (1.0 + rate * effective_years)
end


"""
    compound_rollup(base, rate, years, cap_years) -> Float64

Calculate GWB using compound (exponential) rollup.

[T1] Formula: GWB = base × (1 + rate)^min(years, cap_years)

# Arguments
- `base::Float64`: Initial rollup base
- `rate::Float64`: Annual rollup rate
- `years::Float64`: Years since issue
- `cap_years::Int`: Maximum years of rollup

# Example
```julia
compound_rollup(100000.0, 0.06, 5.0, 10)  # => 133822.56
compound_rollup(100000.0, 0.06, 10.0, 10) # => 179084.77
```
"""
function compound_rollup(base::Float64, rate::Float64, years::Float64, cap_years::Int)
    effective_years = min(years, Float64(cap_years))
    return base * (1.0 + rate)^effective_years
end


"""
    calculate_rollup(state, config) -> Float64

Calculate current GWB based on rollup configuration.

# Arguments
- `state::GWBState`: Current benefit state
- `config::GWBConfig`: Benefit configuration

# Returns
- `Float64`: Rolled-up GWB value
"""
function calculate_rollup(state::GWBState, config::GWBConfig)
    if config.rollup_type == NONE
        return state.gwb
    elseif config.rollup_type == SIMPLE
        return simple_rollup(state.rollup_base, config.rollup_rate,
                            state.years_since_issue, config.rollup_cap_years)
    else  # COMPOUND
        return compound_rollup(state.rollup_base, config.rollup_rate,
                              state.years_since_issue, config.rollup_cap_years)
    end
end


"""
    apply_ratchet(gwb, av) -> Float64

Apply ratchet step-up: GWB = max(GWB, AV).

[T1] The ratchet provision ensures GWB never decreases from market gains
locked in on anniversary dates. This is a one-way adjustment (no step-down).

# Arguments
- `gwb::Float64`: Current GWB
- `av::Float64`: Current account value

# Returns
- `Float64`: New GWB (potentially stepped up)
"""
function apply_ratchet(gwb::Float64, av::Float64)
    return max(gwb, av)
end


"""
    is_anniversary(years_since_issue, dt) -> Bool

Check if current timestep falls on a policy anniversary.

# Arguments
- `years_since_issue::Float64`: Time since issue
- `dt::Float64`: Timestep size in years

# Returns
- `Bool`: True if anniversary occurs this period
"""
function is_anniversary(years_since_issue::Float64, dt::Float64)
    # Anniversary if we've crossed an integer year boundary
    prev_year = floor(years_since_issue)
    curr_year = floor(years_since_issue + dt)
    return curr_year > prev_year
end


"""
    rollup_comparison(base, rate, years, cap_years) -> NamedTuple

Compare simple vs compound rollup for given parameters.

# Returns
NamedTuple with:
- `simple::Float64`: Simple rollup value
- `compound::Float64`: Compound rollup value
- `difference::Float64`: Compound - Simple
- `ratio::Float64`: Compound / Simple
"""
function rollup_comparison(base::Float64, rate::Float64, years::Float64, cap_years::Int)
    simple_val = simple_rollup(base, rate, years, cap_years)
    compound_val = compound_rollup(base, rate, years, cap_years)
    return (
        simple = simple_val,
        compound = compound_val,
        difference = compound_val - simple_val,
        ratio = compound_val / simple_val
    )
end
