#=============================================================================
# VM-21 Calculator - Phase 9
#
# [PROTOTYPE] EDUCATIONAL USE ONLY - NOT FOR PRODUCTION REGULATORY FILING
# =========================================================================
# This module provides a simplified implementation of NAIC VM-21/AG43
# for educational purposes. NOT suitable for regulatory filings.
#
# MISSING FOR COMPLIANCE:
# - NAIC-prescribed scenario generator (GOES/AAA ESG)
# - Full CDHS (Conditional Dynamic Hedging Scenarios)
# - Complete policy data model with all contract features
# - Prescribed mortality tables with improvement scales
# - Asset portfolio modeling and hedge effectiveness
#
# See: docs/regulatory/AG43_COMPLIANCE_GAP.md
# =========================================================================
#
# [T1] VM-21 requires:
# - CTE(70) over stochastic scenarios
# - Standard Scenario Amount (SSA)
# - Reserve = max(CTE70, SSA, CSV floor)
#
# [T1] CTE(α) = E[X | X ≥ VaR(α)]
#      = Average of worst (1-α)% of scenarios
=============================================================================#

using Random
using Statistics

#=============================================================================
# VM-21 Calculator
=============================================================================#

"""
    VM21Calculator

VM-21 reserve calculator for variable annuities.

[PROTOTYPE] EDUCATIONAL USE ONLY
--------------------------------
This calculator is for educational/research purposes only.
NOT suitable for regulatory filings.

[T1] VM-21 Reserve = max(CTE70, SSA, CSV floor)

# Fields
- `n_scenarios::Int`: Number of scenarios for CTE calculation
- `projection_years::Int`: Years to project
- `seed::Union{Int, Nothing}`: Random seed for reproducibility
- `scenario_generator::ScenarioGenerator`: Scenario generator instance

# Example
```julia
calc = VM21Calculator(n_scenarios=1000, seed=42)
policy = PolicyData(av=100_000, gwb=110_000, age=70)
result = calculate_reserve(calc, policy)
result.reserve > 0  # true
```
"""
mutable struct VM21Calculator
    n_scenarios::Int
    projection_years::Int
    seed::Union{Int, Nothing}
    scenario_generator::ScenarioGenerator

    function VM21Calculator(n_scenarios::Int, projection_years::Int, seed::Union{Int, Nothing})
        n_scenarios > 0 || error("CRITICAL: n_scenarios must be positive, got $n_scenarios")
        sg = ScenarioGenerator(n_scenarios=n_scenarios, projection_years=projection_years, seed=seed)
        new(n_scenarios, projection_years, seed, sg)
    end
end

# Keyword constructor
function VM21Calculator(;
    n_scenarios::Int = 1000,
    projection_years::Int = 30,
    seed::Union{Int, Nothing} = nothing
)
    VM21Calculator(n_scenarios, projection_years, seed)
end


#=============================================================================
# Core Calculations
=============================================================================#

"""
    calculate_cte(calc, scenario_results; alpha=0.70)

Calculate CTE (Conditional Tail Expectation).

[T1] CTE(α) = Average of worst (1-α)% of scenarios

# Arguments
- `calc::VM21Calculator`: The calculator
- `scenario_results::Vector{Float64}`: PV of liability for each scenario (positive = liability)

# Keyword Arguments
- `alpha::Float64=0.70`: CTE level (0.70 for CTE70)

# Returns
- `Float64`: CTE at specified alpha

# Example
```julia
calc = VM21Calculator()
results = [100.0, 200.0, 300.0, 400.0, 500.0, 600.0, 700.0, 800.0, 900.0, 1000.0]
calculate_cte(calc, results, alpha=0.70)  # ≈ 900.0
```
"""
function calculate_cte(
    calc::VM21Calculator,
    scenario_results::Vector{Float64};
    alpha::Float64 = 0.70
)::Float64
    0 < alpha < 1 || error("CRITICAL: Alpha must be in (0, 1), got $alpha")
    !isempty(scenario_results) || error("CRITICAL: scenario_results cannot be empty")

    # Sort descending (worst = highest liability first)
    sorted_results = sort(scenario_results, rev=true)

    # Take worst (1-α)% of scenarios
    n_tail = max(1, Int(floor(length(sorted_results) * (1 - alpha))))
    tail_values = sorted_results[1:n_tail]

    mean(tail_values)
end


"""
    calculate_cte70(calc, scenario_results)

Calculate CTE(70) from scenario results.

[T1] CTE70 = Average of worst 30% of scenarios

# Arguments
- `calc::VM21Calculator`: The calculator
- `scenario_results::Vector{Float64}`: PV of liability for each scenario

# Returns
- `Float64`: CTE(70)
"""
function calculate_cte70(calc::VM21Calculator, scenario_results::Vector{Float64})::Float64
    calculate_cte(calc, scenario_results, alpha=0.70)
end


"""
    calculate_ssa(calc, policy; mortality_table, yield_curve, gender)

Calculate Standard Scenario Amount.

[T1] SSA uses prescribed deterministic scenarios.

# Arguments
- `calc::VM21Calculator`: The calculator
- `policy::PolicyData`: Policy information

# Keyword Arguments
- `mortality_table::Union{MortalityTable, Nothing}=nothing`: Mortality table. If nothing, uses SOA 2012 IAM.
- `yield_curve::Union{YieldCurve, Nothing}=nothing`: Yield curve. If nothing, uses flat 4%.
- `gender::Gender=MALE`: Gender for default mortality table

# Returns
- `Float64`: Standard Scenario Amount
"""
function calculate_ssa(
    calc::VM21Calculator,
    policy::PolicyData;
    mortality_table::Union{MortalityTable, Nothing} = nothing,
    yield_curve::Union{YieldCurve, Nothing} = nothing,
    gender::Gender = MALE
)::Float64
    # Default to SOA 2012 IAM mortality
    if mortality_table === nothing
        mortality_table = soa_2012_iam(gender=gender)
    end

    # Default to flat 4% yield curve
    if yield_curve === nothing
        yield_curve = flat_curve(0.04)
    end

    r = get_rate(yield_curve, 1.0)

    # Standard scenario: equity drops 20%, no recovery for 10 years
    # Then gradual 7% return
    max_age = 100
    n_years = max_age - policy.age

    # Create RNG for this calculation
    rng = calc.seed === nothing ? Random.default_rng() : MersenneTwister(calc.seed + 1000)

    # Project under stress scenario
    av = policy.av
    gwb = policy.gwb
    pv_liability = 0.0

    for t in 0:min(n_years - 1, calc.projection_years - 1)
        current_age = policy.age + t

        # Survival probability
        qx = get_qx(mortality_table, current_age)
        if rand(rng) < qx
            break
        end

        # Standard scenario: -20% year 1, flat for 10 years, then 7%
        if t == 0
            equity_return = -0.20
        elseif t < 10
            equity_return = 0.0
        else
            equity_return = 0.07
        end

        # Update AV
        av = av * (1 + equity_return) * (1 - policy.fee_rate)

        # Guaranteed withdrawal
        guaranteed_wd = gwb * policy.withdrawal_rate

        # If AV < guaranteed withdrawal, liability emerges
        if av <= 0
            df = exp(-r * (t + 1))
            pv_liability += guaranteed_wd * df
        end

        av = max(0, av - guaranteed_wd)
    end

    pv_liability
end


"""
    calculate_reserve(calc, policy; scenarios, mortality_table, yield_curve, gender)

Calculate VM-21 reserve.

[T1] Reserve = max(CTE70, SSA, CSV floor)

# Arguments
- `calc::VM21Calculator`: The calculator
- `policy::PolicyData`: Policy information

# Keyword Arguments
- `scenarios::Union{AG43Scenarios, Nothing}=nothing`: Pre-generated scenarios. If nothing, generates new.
- `mortality_table::Union{MortalityTable, Nothing}=nothing`: Mortality table. If nothing, uses SOA 2012 IAM.
- `yield_curve::Union{YieldCurve, Nothing}=nothing`: Yield curve. If nothing, uses flat 4%.
- `gender::Gender=MALE`: Gender for default mortality table

# Returns
- `VM21Result`: Complete VM-21 result

# Example
```julia
calc = VM21Calculator(n_scenarios=100, seed=42)
policy = PolicyData(av=100_000, gwb=110_000, age=70)
result = calculate_reserve(calc, policy)
result.reserve >= result.csv_floor  # true
```
"""
function calculate_reserve(
    calc::VM21Calculator,
    policy::PolicyData;
    scenarios::Union{AG43Scenarios, Nothing} = nothing,
    mortality_table::Union{MortalityTable, Nothing} = nothing,
    yield_curve::Union{YieldCurve, Nothing} = nothing,
    gender::Gender = MALE
)::VM21Result
    # Default to SOA 2012 IAM mortality
    if mortality_table === nothing
        mortality_table = soa_2012_iam(gender=gender)
    end

    # Default to flat 4% yield curve
    if yield_curve === nothing
        yield_curve = flat_curve(0.04)
    end

    r = get_rate(yield_curve, 1.0)

    # Generate scenarios if not provided
    if scenarios === nothing
        scenarios = generate_ag43_scenarios(calc.scenario_generator)
    end

    # Calculate PV of liability for each scenario
    scenario_pvs = _run_scenarios(calc, policy, scenarios, mortality_table, r)

    # Calculate components
    cte70 = calculate_cte70(calc, scenario_pvs)
    ssa = calculate_ssa(calc, policy, mortality_table=mortality_table, yield_curve=yield_curve, gender=gender)
    csv_floor = policy.csv

    # Reserve = max of three components
    reserve = max(cte70, ssa, csv_floor)

    VM21Result(
        cte70 = cte70,
        ssa = ssa,
        csv_floor = csv_floor,
        reserve = reserve,
        scenario_count = length(scenario_pvs),
        mean_pv = mean(scenario_pvs),
        std_pv = std(scenario_pvs),
        worst_pv = maximum(scenario_pvs)
    )
end


#=============================================================================
# Internal Helper Functions
=============================================================================#

"""Run all scenarios and calculate PV of liability for each."""
function _run_scenarios(
    calc::VM21Calculator,
    policy::PolicyData,
    scenarios::AG43Scenarios,
    mortality_table::MortalityTable,
    r::Float64
)::Vector{Float64}
    pvs = Float64[]
    for scenario in scenarios.scenarios
        pv = _run_single_scenario(calc, policy, scenario, mortality_table, r)
        push!(pvs, pv)
    end
    pvs
end


"""
Run single scenario and calculate PV of liability.

[T1] Liability = PV of (guaranteed withdrawals when AV = 0)
"""
function _run_single_scenario(
    calc::VM21Calculator,
    policy::PolicyData,
    scenario::EconomicScenario,
    mortality_table::MortalityTable,
    r::Float64
)::Float64
    max_age = 100
    n_years = min(max_age - policy.age, length(scenario.equity_returns))

    av = policy.av
    gwb = policy.gwb
    pv_liability = 0.0
    alive = true

    # Deterministic RNG per scenario
    seed_val = abs(hash((calc.seed === nothing ? 0 : calc.seed, scenario.scenario_id)))
    rng = MersenneTwister(seed_val % typemax(UInt32))

    for t in 1:n_years
        current_age = policy.age + t - 1

        # Check mortality
        qx = get_qx(mortality_table, current_age)
        if rand(rng) < qx
            alive = false
            break
        end

        # Get equity return for this year
        equity_return = scenario.equity_returns[t]

        # Update AV (market return - fee)
        av = av * (1 + equity_return) * (1 - policy.fee_rate)

        # Guaranteed withdrawal
        guaranteed_wd = gwb * policy.withdrawal_rate

        # If AV is exhausted, insurer pays
        if av <= 0 && alive
            # Use scenario discount rate or fixed rate
            discount_rate = t <= length(scenario.rates) ? scenario.rates[t] : r
            df = exp(-discount_rate * t)
            pv_liability += guaranteed_wd * df
        end

        # Reduce AV by withdrawal
        av = max(0, av - guaranteed_wd)
    end

    pv_liability
end


"""
Default mortality table (Gompertz approximation).

[T2] Approximate US life table.
"""
function _default_mortality(age::Int)::Float64
    # Gompertz: qx = 0.0001 * e^(0.08 * age)
    qx = 0.0001 * exp(0.08 * age)
    min(qx, 1.0)
end


#=============================================================================
# Convenience Functions
=============================================================================#

"""
    calculate_cte_levels(scenario_results; levels)

Calculate CTE at multiple levels.

# Arguments
- `scenario_results::Vector{Float64}`: PV of liability for each scenario

# Keyword Arguments
- `levels::Vector{Float64}=[0.65, 0.70, 0.75, 0.80, 0.85, 0.90, 0.95]`: CTE levels to calculate

# Returns
- `Dict{String, Float64}`: CTE values at each level

# Example
```julia
results = [100.0, 200.0, 300.0, 400.0, 500.0, 600.0, 700.0, 800.0, 900.0, 1000.0]
ctes = calculate_cte_levels(results)
haskey(ctes, "CTE70")  # true
```
"""
function calculate_cte_levels(
    scenario_results::Vector{Float64};
    levels::Vector{Float64} = [0.65, 0.70, 0.75, 0.80, 0.85, 0.90, 0.95]
)::Dict{String, Float64}
    calc = VM21Calculator()
    ctes = Dict{String, Float64}()

    for level in levels
        key = "CTE$(Int(level * 100))"
        ctes[key] = calculate_cte(calc, scenario_results, alpha=level)
    end

    ctes
end


"""
    vm21_sensitivity_analysis(policy; n_scenarios, seed)

Perform sensitivity analysis on VM-21 reserve.

# Arguments
- `policy::PolicyData`: Base policy data

# Keyword Arguments
- `n_scenarios::Int=1000`: Number of scenarios
- `seed::Union{Int, Nothing}=nothing`: Random seed

# Returns
- `Dict{String, Any}`: Sensitivity results

# Example
```julia
policy = PolicyData(av=100_000, gwb=110_000, age=70)
sens = vm21_sensitivity_analysis(policy, n_scenarios=100, seed=42)
haskey(sens, "base_reserve")  # true
```
"""
function vm21_sensitivity_analysis(
    policy::PolicyData;
    n_scenarios::Int = 1000,
    seed::Union{Int, Nothing} = nothing
)::Dict{String, Any}
    calc = VM21Calculator(n_scenarios=n_scenarios, seed=seed)

    # Base case
    base_result = calculate_reserve(calc, policy)

    # GWB +10%
    policy_gwb_up = PolicyData(
        av = policy.av,
        gwb = policy.gwb * 1.10,
        age = policy.age,
        csv = policy.csv,
        withdrawal_rate = policy.withdrawal_rate,
        fee_rate = policy.fee_rate
    )
    result_gwb_up = calculate_reserve(calc, policy_gwb_up)

    # Age +5
    policy_older = PolicyData(
        av = policy.av,
        gwb = policy.gwb,
        age = policy.age + 5,
        csv = policy.csv,
        withdrawal_rate = policy.withdrawal_rate,
        fee_rate = policy.fee_rate
    )
    result_older = calculate_reserve(calc, policy_older)

    # AV -20%
    policy_av_down = PolicyData(
        av = policy.av * 0.80,
        gwb = policy.gwb,
        age = policy.age,
        csv = policy.csv,
        withdrawal_rate = policy.withdrawal_rate,
        fee_rate = policy.fee_rate
    )
    result_av_down = calculate_reserve(calc, policy_av_down)

    Dict{String, Any}(
        "base_reserve" => base_result.reserve,
        "base_cte70" => base_result.cte70,
        "gwb_up_10pct" => result_gwb_up.reserve,
        "gwb_sensitivity" => base_result.reserve > 0 ?
            (result_gwb_up.reserve - base_result.reserve) / base_result.reserve : 0.0,
        "age_plus_5" => result_older.reserve,
        "age_sensitivity" => base_result.reserve > 0 ?
            (result_older.reserve - base_result.reserve) / base_result.reserve : 0.0,
        "av_down_20pct" => result_av_down.reserve,
        "av_sensitivity" => base_result.reserve > 0 ?
            (result_av_down.reserve - base_result.reserve) / base_result.reserve : 0.0
    )
end
