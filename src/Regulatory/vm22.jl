#=============================================================================
# VM-22 Calculator - Phase 9
#
# [PROTOTYPE] EDUCATIONAL USE ONLY - NOT FOR PRODUCTION REGULATORY FILING
# =========================================================================
# This module provides a simplified implementation of NAIC VM-22 (PBR for
# fixed annuities) for educational purposes. NOT suitable for regulatory filings.
#
# VM-22 TIMELINE:
# - January 1, 2026: Voluntary adoption begins
# - January 1, 2029: Mandatory for all fixed annuities
#
# MISSING FOR COMPLIANCE:
# - NAIC-prescribed scenario generator (transition to GOES effective 2026)
# - Full asset-liability matching model
# - Prescribed lapse formulas with dynamic adjustments
# - Company experience studies and credibility weighting
#
# See: docs/regulatory/AG43_COMPLIANCE_GAP.md
# =========================================================================
#
# [T1] VM-22 reserve determination:
# 1. Stochastic Exclusion Test (SET) - if pass, use DR
# 2. Single Scenario Test (SST) - if pass, use DR
# 3. If both fail → Stochastic Reserve (SR)
#
# [T1] Reserve = max(DR, SR if required, Net Premium Reserve)
=============================================================================#

using Random
using Statistics

#=============================================================================
# VM-22 Calculator
=============================================================================#

"""
    VM22Calculator

VM-22 reserve calculator for fixed annuities.

[PROTOTYPE] EDUCATIONAL USE ONLY
--------------------------------
This calculator is for educational/research purposes only.
NOT suitable for regulatory filings.
VM-22 mandatory compliance begins January 1, 2029.

[T1] VM-22 uses principle-based reserving:
- Stochastic Exclusion Test determines reserve type
- Deterministic Reserve for simple products
- Stochastic Reserve for complex products

# Fields
- `n_scenarios::Int`: Number of scenarios for stochastic reserve
- `projection_years::Int`: Years to project
- `seed::Union{Int, Nothing}`: Random seed for reproducibility
- `scenario_generator::ScenarioGenerator`: Scenario generator instance

# Example
```julia
calc = VM22Calculator(seed=42)
policy = FixedAnnuityPolicy(premium=100_000, guaranteed_rate=0.04, term_years=5)
result = calculate_reserve(calc, policy)
result.reserve > 0  # true
```
"""
mutable struct VM22Calculator
    n_scenarios::Int
    projection_years::Int
    seed::Union{Int, Nothing}
    scenario_generator::ScenarioGenerator

    function VM22Calculator(n_scenarios::Int, projection_years::Int, seed::Union{Int, Nothing})
        sg = ScenarioGenerator(n_scenarios=n_scenarios, projection_years=projection_years, seed=seed)
        new(n_scenarios, projection_years, seed, sg)
    end
end

# Keyword constructor
function VM22Calculator(;
    n_scenarios::Int = 1000,
    projection_years::Int = 30,
    seed::Union{Int, Nothing} = nothing
)
    VM22Calculator(n_scenarios, projection_years, seed)
end


#=============================================================================
# Core Calculations
=============================================================================#

"""
    calculate_reserve(calc, policy; market_rate, yield_curve, lapse_rate)

Calculate VM-22 reserve.

[T1] Reserve = max(NPR, DR or SR based on exclusion tests)

# Arguments
- `calc::VM22Calculator`: The calculator
- `policy::FixedAnnuityPolicy`: Policy data

# Keyword Arguments
- `market_rate::Union{Float64, Nothing}=nothing`: Current market rate. If nothing, derived from yield_curve.
- `yield_curve::Union{YieldCurve, Nothing}=nothing`: Yield curve. If nothing, uses flat 4%.
- `lapse_rate::Float64=0.05`: Assumed annual lapse rate

# Returns
- `VM22Result`: Complete VM-22 result

# Example
```julia
calc = VM22Calculator(seed=42)
policy = FixedAnnuityPolicy(premium=100_000, guaranteed_rate=0.04, term_years=5)
result = calculate_reserve(calc, policy)
result.reserve >= 0  # true
```
"""
function calculate_reserve(
    calc::VM22Calculator,
    policy::FixedAnnuityPolicy;
    market_rate::Union{Float64, Nothing} = nothing,
    yield_curve::Union{YieldCurve, Nothing} = nothing,
    lapse_rate::Float64 = 0.05
)::VM22Result
    # Default to flat 4% yield curve if neither provided
    if yield_curve === nothing && market_rate === nothing
        yield_curve = flat_curve(0.04)
        market_rate = 0.04
    elseif yield_curve !== nothing && market_rate === nothing
        # Derive market rate from yield curve
        market_rate = get_rate(yield_curve, Float64(policy.term_years))
    end
    # If market_rate provided but yield_curve not, use market_rate directly

    # Calculate Net Premium Reserve (floor)
    npr = calculate_net_premium_reserve(calc, policy, market_rate)

    # Run Stochastic Exclusion Test
    set_result = stochastic_exclusion_test(calc, policy, market_rate)

    # Run Single Scenario Test if SET fails
    sst_passed = true
    if !set_result.passed
        sst_passed = single_scenario_test(calc, policy, market_rate, lapse_rate)
    end

    # Determine reserve type
    if set_result.passed || sst_passed
        # Use Deterministic Reserve
        dr = calculate_deterministic_reserve(calc, policy, market_rate, lapse_rate)
        reserve = max(npr, dr)
        return VM22Result(
            reserve = reserve,
            net_premium_reserve = npr,
            deterministic_reserve = dr,
            stochastic_reserve = nothing,
            reserve_type = DETERMINISTIC,
            set_passed = set_result.passed,
            sst_passed = sst_passed
        )
    else
        # Use Stochastic Reserve
        dr = calculate_deterministic_reserve(calc, policy, market_rate, lapse_rate)
        sr = calculate_stochastic_reserve(calc, policy, market_rate, lapse_rate)
        reserve = max(npr, dr, sr)
        return VM22Result(
            reserve = reserve,
            net_premium_reserve = npr,
            deterministic_reserve = dr,
            stochastic_reserve = sr,
            reserve_type = STOCHASTIC,
            set_passed = set_result.passed,
            sst_passed = sst_passed
        )
    end
end


"""
    calculate_net_premium_reserve(calc, policy, market_rate)

Calculate Net Premium Reserve (NPR).

[T1] NPR = PV of future guaranteed benefits at valuation rate

# Arguments
- `calc::VM22Calculator`: The calculator
- `policy::FixedAnnuityPolicy`: Policy data
- `market_rate::Float64`: Valuation rate

# Returns
- `Float64`: Net Premium Reserve
"""
function calculate_net_premium_reserve(
    calc::VM22Calculator,
    policy::FixedAnnuityPolicy,
    market_rate::Float64
)::Float64
    # NPR = PV of guaranteed maturity value
    remaining_years = policy.term_years - policy.current_year

    # Guaranteed maturity value
    av = get_av(policy)
    gmv = av * ((1 + policy.guaranteed_rate) ^ remaining_years)

    # Discount to present
    npr = gmv * exp(-market_rate * remaining_years)

    npr
end


"""
    calculate_deterministic_reserve(calc, policy, market_rate, lapse_rate)

Calculate Deterministic Reserve (DR).

[T1] DR = PV of liabilities under deterministic scenarios.

# Arguments
- `calc::VM22Calculator`: The calculator
- `policy::FixedAnnuityPolicy`: Policy data
- `market_rate::Float64`: Market rate
- `lapse_rate::Float64`: Annual lapse rate

# Returns
- `Float64`: Deterministic Reserve
"""
function calculate_deterministic_reserve(
    calc::VM22Calculator,
    policy::FixedAnnuityPolicy,
    market_rate::Float64,
    lapse_rate::Float64
)::Float64
    scenarios = generate_deterministic_scenarios(
        n_years = calc.projection_years,
        base_rate = market_rate
    )

    # Run each scenario
    pvs = Float64[]
    for scenario in scenarios
        pv = _run_fixed_scenario(calc, policy, scenario.rates, lapse_rate)
        push!(pvs, pv)
    end

    # DR = max of deterministic scenarios
    maximum(pvs)
end


"""
    calculate_stochastic_reserve(calc, policy, market_rate, lapse_rate)

Calculate Stochastic Reserve (SR).

[T1] SR = CTE70 over stochastic scenarios.

# Arguments
- `calc::VM22Calculator`: The calculator
- `policy::FixedAnnuityPolicy`: Policy data
- `market_rate::Float64`: Initial market rate
- `lapse_rate::Float64`: Annual lapse rate

# Returns
- `Float64`: Stochastic Reserve
"""
function calculate_stochastic_reserve(
    calc::VM22Calculator,
    policy::FixedAnnuityPolicy,
    market_rate::Float64,
    lapse_rate::Float64
)::Float64
    ag43 = generate_ag43_scenarios(calc.scenario_generator, initial_rate=market_rate)

    # Run each scenario
    pvs = Float64[]
    for scenario in ag43.scenarios
        pv = _run_fixed_scenario(calc, policy, scenario.rates, lapse_rate)
        push!(pvs, pv)
    end

    # CTE70 = average of worst 30%
    sorted_pvs = sort(pvs, rev=true)
    n_tail = max(1, Int(floor(length(sorted_pvs) * 0.30)))
    mean(sorted_pvs[1:n_tail])
end


"""
    stochastic_exclusion_test(calc, policy, market_rate; threshold)

Perform Stochastic Exclusion Test (SET).

[T1] SET determines if full stochastic modeling is required.
If liability/asset ratio < threshold, product "passes" and can use DR.

# Arguments
- `calc::VM22Calculator`: The calculator
- `policy::FixedAnnuityPolicy`: Policy data
- `market_rate::Float64`: Current market rate

# Keyword Arguments
- `threshold::Float64=1.10`: Ratio threshold for passing

# Returns
- `StochasticExclusionResult`: Test result
"""
function stochastic_exclusion_test(
    calc::VM22Calculator,
    policy::FixedAnnuityPolicy,
    market_rate::Float64;
    threshold::Float64 = 1.10
)::StochasticExclusionResult
    remaining_years = policy.term_years - policy.current_year
    av = get_av(policy)

    # Guaranteed maturity value
    gmv = av * ((1 + policy.guaranteed_rate) ^ remaining_years)

    # Market maturity value (what assets would earn)
    mmv = av * ((1 + market_rate) ^ remaining_years)

    # Ratio = guaranteed / market
    ratio = mmv > 0 ? gmv / mmv : Inf

    # Pass if ratio is below threshold
    passed = ratio < threshold

    StochasticExclusionResult(passed, ratio, threshold)
end


"""
    single_scenario_test(calc, policy, market_rate, lapse_rate)

Perform Single Scenario Test (SST).

[T1] SST uses a prescribed stress scenario.
If DR under stress < threshold, product "passes".

# Arguments
- `calc::VM22Calculator`: The calculator
- `policy::FixedAnnuityPolicy`: Policy data
- `market_rate::Float64`: Current market rate
- `lapse_rate::Float64`: Lapse rate

# Returns
- `Bool`: Whether test passed
"""
function single_scenario_test(
    calc::VM22Calculator,
    policy::FixedAnnuityPolicy,
    market_rate::Float64,
    lapse_rate::Float64
)::Bool
    # Stress scenario: rates drop 2%
    stressed_rate = max(0.0, market_rate - 0.02)

    # Calculate DR under stress
    dr_base = calculate_deterministic_reserve(calc, policy, market_rate, lapse_rate)
    dr_stress = calculate_deterministic_reserve(calc, policy, stressed_rate, lapse_rate)

    # Pass if stress doesn't increase reserve by more than 20%
    if dr_base == 0
        return true
    end

    increase = (dr_stress - dr_base) / dr_base
    increase < 0.20
end


#=============================================================================
# Internal Helper Functions
=============================================================================#

"""
Run a single scenario for fixed annuity.

[T1] PV of liability = discounted guaranteed benefits × survival probability
"""
function _run_fixed_scenario(
    calc::VM22Calculator,
    policy::FixedAnnuityPolicy,
    rate_path::Vector{Float64},
    lapse_rate::Float64
)::Float64
    remaining_years = policy.term_years - policy.current_year
    n_years = min(remaining_years, length(rate_path))

    av = get_av(policy)
    pv_liability = 0.0
    survival = 1.0  # Probability of persistency

    for t in 1:n_years
        discount_rate = t <= length(rate_path) ? rate_path[t] : rate_path[end]

        # Account grows at guaranteed rate
        av = av * (1 + policy.guaranteed_rate)

        # Lapse (surrender)
        sc_decay = max(0.0, 1.0 - (t - 1) / policy.term_years)
        lapse_benefit = av * (1 - policy.surrender_charge_pct * sc_decay)
        pv_lapse = lapse_rate * survival * lapse_benefit * exp(-discount_rate * t)

        # Update survival
        survival *= (1 - lapse_rate)

        # Add to PV
        pv_liability += pv_lapse
    end

    # Terminal benefit for survivors
    if n_years > 0
        final_rate = !isempty(rate_path) ? rate_path[end] : 0.04
        pv_maturity = survival * av * exp(-final_rate * n_years)
        pv_liability += pv_maturity
    end

    pv_liability
end


#=============================================================================
# Convenience Functions
=============================================================================#

"""
    compare_reserve_methods(policy; market_rate, lapse_rate, n_scenarios, seed)

Compare different reserve calculation methods.

# Arguments
- `policy::FixedAnnuityPolicy`: Policy data

# Keyword Arguments
- `market_rate::Float64=0.04`: Market rate
- `lapse_rate::Float64=0.05`: Lapse rate
- `n_scenarios::Int=1000`: Number of scenarios
- `seed::Union{Int, Nothing}=nothing`: Random seed

# Returns
- `Dict{String, Any}`: Comparison of reserve methods

# Example
```julia
policy = FixedAnnuityPolicy(premium=100_000, guaranteed_rate=0.04, term_years=5)
comparison = compare_reserve_methods(policy, n_scenarios=100, seed=42)
haskey(comparison, "npr")  # true
```
"""
function compare_reserve_methods(
    policy::FixedAnnuityPolicy;
    market_rate::Float64 = 0.04,
    lapse_rate::Float64 = 0.05,
    n_scenarios::Int = 1000,
    seed::Union{Int, Nothing} = nothing
)::Dict{String, Any}
    calc = VM22Calculator(n_scenarios=n_scenarios, seed=seed)

    npr = calculate_net_premium_reserve(calc, policy, market_rate)
    dr = calculate_deterministic_reserve(calc, policy, market_rate, lapse_rate)
    sr = calculate_stochastic_reserve(calc, policy, market_rate, lapse_rate)
    set_result = stochastic_exclusion_test(calc, policy, market_rate)

    Dict{String, Any}(
        "npr" => npr,
        "deterministic_reserve" => dr,
        "stochastic_reserve" => sr,
        "final_reserve" => max(npr, dr),
        "set_passed" => set_result.passed,
        "set_ratio" => set_result.ratio,
        "sr_vs_dr" => dr > 0 ? (sr - dr) / dr : 0.0
    )
end


"""
    vm22_sensitivity(policy; market_rate, lapse_rate, seed)

Perform VM-22 sensitivity analysis.

# Arguments
- `policy::FixedAnnuityPolicy`: Policy data

# Keyword Arguments
- `market_rate::Float64=0.04`: Base market rate
- `lapse_rate::Float64=0.05`: Base lapse rate
- `seed::Union{Int, Nothing}=nothing`: Random seed

# Returns
- `Dict{String, Any}`: Sensitivity results

# Example
```julia
policy = FixedAnnuityPolicy(premium=100_000, guaranteed_rate=0.04, term_years=5)
sens = vm22_sensitivity(policy, seed=42)
haskey(sens, "base_reserve")  # true
```
"""
function vm22_sensitivity(
    policy::FixedAnnuityPolicy;
    market_rate::Float64 = 0.04,
    lapse_rate::Float64 = 0.05,
    seed::Union{Int, Nothing} = nothing
)::Dict{String, Any}
    calc = VM22Calculator(n_scenarios=500, seed=seed)

    # Base case
    base = calculate_reserve(calc, policy, market_rate=market_rate, lapse_rate=lapse_rate)

    # Rate up +1%
    rate_up = calculate_reserve(calc, policy, market_rate=market_rate + 0.01, lapse_rate=lapse_rate)

    # Rate down -1%
    rate_down = calculate_reserve(calc, policy, market_rate=max(0.0, market_rate - 0.01), lapse_rate=lapse_rate)

    # Lapse up 2x
    lapse_up = calculate_reserve(calc, policy, market_rate=market_rate, lapse_rate=lapse_rate * 2)

    # Lapse down 0.5x
    lapse_down = calculate_reserve(calc, policy, market_rate=market_rate, lapse_rate=lapse_rate * 0.5)

    Dict{String, Any}(
        "base_reserve" => base.reserve,
        "base_type" => string(base.reserve_type),
        "rate_up_1pct" => rate_up.reserve,
        "rate_sensitivity" => base.reserve > 0 ?
            (rate_up.reserve - base.reserve) / base.reserve : 0.0,
        "rate_down_1pct" => rate_down.reserve,
        "lapse_up_2x" => lapse_up.reserve,
        "lapse_sensitivity" => base.reserve > 0 ?
            (lapse_up.reserve - base.reserve) / base.reserve : 0.0,
        "lapse_down_05x" => lapse_down.reserve
    )
end
