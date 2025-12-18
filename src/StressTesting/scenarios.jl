"""
Standard Stress Scenarios.

Provides pre-defined stress scenarios:
- ORSA (Own Risk and Solvency Assessment) standard scenarios
- Custom scenario builders
- Scenario combination utilities
"""

# ============================================================================
# ORSA Standard Scenarios [T2]
# ============================================================================

"""
ORSA Moderate Adverse scenario (~1-in-10 year event).

[T2] Based on industry ORSA practice:
- Equity: -15% decline
- Rates: -50 bps parallel shift
- Volatility: 30% increase
- Behavioral: No change assumed
"""
const ORSA_MODERATE_ADVERSE = StressScenario(
    name = "orsa_moderate_adverse",
    display_name = "ORSA Moderate Adverse",
    equity_shock = -0.15,
    rate_shock = -0.0050,
    vol_shock = 1.3,
    lapse_multiplier = 1.0,
    withdrawal_multiplier = 1.0,
    scenario_type = ORSA
)

"""
ORSA Severely Adverse scenario (~1-in-25 year event).

[T2] Based on industry ORSA practice:
- Equity: -30% decline
- Rates: -100 bps parallel shift
- Volatility: 100% increase (2x)
- Lapse: 10% increase
- Withdrawal: 20% increase
"""
const ORSA_SEVERELY_ADVERSE = StressScenario(
    name = "orsa_severely_adverse",
    display_name = "ORSA Severely Adverse",
    equity_shock = -0.30,
    rate_shock = -0.0100,
    vol_shock = 2.0,
    lapse_multiplier = 1.1,
    withdrawal_multiplier = 1.2,
    scenario_type = ORSA
)

"""
ORSA Extremely Adverse scenario (~1-in-100 year event).

[T2] Based on industry ORSA practice:
- Equity: -50% decline (near 2008 GFC levels)
- Rates: -200 bps parallel shift
- Volatility: 300% increase (4x baseline)
- Lapse: 20% increase
- Withdrawal: 50% increase
"""
const ORSA_EXTREMELY_ADVERSE = StressScenario(
    name = "orsa_extremely_adverse",
    display_name = "ORSA Extremely Adverse",
    equity_shock = -0.50,
    rate_shock = -0.0200,
    vol_shock = 4.0,
    lapse_multiplier = 1.2,
    withdrawal_multiplier = 1.5,
    scenario_type = ORSA
)

"""
All ORSA standard scenarios.
"""
const ORSA_SCENARIOS = [
    ORSA_MODERATE_ADVERSE,
    ORSA_SEVERELY_ADVERSE,
    ORSA_EXTREMELY_ADVERSE
]

# ============================================================================
# Scenario Builders
# ============================================================================

"""
    create_equity_shock(shock; name=nothing)

Create a scenario with only equity shock.

# Arguments
- `shock::Float64`: Equity shock (e.g., -0.20 for -20%)
- `name::String`: Optional scenario name

# Example
```julia
scenario = create_equity_shock(-0.25)  # 25% equity decline
```
"""
function create_equity_shock(shock::Float64; name::Union{String, Nothing} = nothing)
    scenario_name = isnothing(name) ? "equity_$(round(Int, shock * 100))" : name
    display = "Equity $(round(Int, shock * 100))%"

    StressScenario(
        name = scenario_name,
        display_name = display,
        equity_shock = shock,
        rate_shock = 0.0,
        scenario_type = CUSTOM
    )
end

"""
    create_rate_shock(shock_bps; name=nothing)

Create a scenario with only interest rate shock.

# Arguments
- `shock_bps::Float64`: Rate shock in basis points (e.g., -100 for -100 bps)
- `name::String`: Optional scenario name

# Example
```julia
scenario = create_rate_shock(-150)  # -150 bps rate drop
```
"""
function create_rate_shock(shock_bps::Float64; name::Union{String, Nothing} = nothing)
    shock_decimal = shock_bps / 10000.0
    scenario_name = isnothing(name) ? "rate_$(round(Int, shock_bps))bps" : name
    display = "Rate $(shock_bps > 0 ? "+" : "")$(round(Int, shock_bps)) bps"

    StressScenario(
        name = scenario_name,
        display_name = display,
        equity_shock = 0.0,
        rate_shock = shock_decimal,
        scenario_type = CUSTOM
    )
end

"""
    create_vol_shock(multiplier; name=nothing)

Create a scenario with only volatility shock.

# Arguments
- `multiplier::Float64`: Vol multiplier (e.g., 2.0 for 2x vol)
- `name::String`: Optional scenario name

# Example
```julia
scenario = create_vol_shock(2.5)  # 2.5x volatility
```
"""
function create_vol_shock(multiplier::Float64; name::Union{String, Nothing} = nothing)
    scenario_name = isnothing(name) ? "vol_$(round(Int, multiplier * 100))pct" : name
    display = "Vol $(round(Int, multiplier * 100))%"

    StressScenario(
        name = scenario_name,
        display_name = display,
        equity_shock = 0.0,
        rate_shock = 0.0,
        vol_shock = multiplier,
        scenario_type = CUSTOM
    )
end

"""
    create_behavioral_shock(lapse_mult, withdrawal_mult; name=nothing)

Create a scenario with only behavioral shocks.

# Arguments
- `lapse_mult::Float64`: Lapse rate multiplier
- `withdrawal_mult::Float64`: Withdrawal rate multiplier
- `name::String`: Optional scenario name

# Example
```julia
scenario = create_behavioral_shock(1.5, 2.0)  # 50% more lapses, 2x withdrawals
```
"""
function create_behavioral_shock(
    lapse_mult::Float64,
    withdrawal_mult::Float64;
    name::Union{String, Nothing} = nothing
)
    scenario_name = isnothing(name) ? "behavioral_l$(round(Int, lapse_mult*100))_w$(round(Int, withdrawal_mult*100))" : name
    display = "Behavioral L:$(round(Int, lapse_mult*100))% W:$(round(Int, withdrawal_mult*100))%"

    StressScenario(
        name = scenario_name,
        display_name = display,
        equity_shock = 0.0,
        rate_shock = 0.0,
        lapse_multiplier = lapse_mult,
        withdrawal_multiplier = withdrawal_mult,
        scenario_type = CUSTOM
    )
end

"""
    create_combined_scenario(; name, display_name, kwargs...)

Create a custom combined scenario.

# Example
```julia
scenario = create_combined_scenario(
    name = "stagflation",
    display_name = "Stagflation Scenario",
    equity_shock = -0.20,
    rate_shock = 0.0150,  # Rising rates
    vol_shock = 1.5,
    lapse_multiplier = 1.3
)
```
"""
function create_combined_scenario(;
    name::String,
    display_name::String,
    equity_shock::Float64 = 0.0,
    rate_shock::Float64 = 0.0,
    vol_shock::Float64 = 1.0,
    lapse_multiplier::Float64 = 1.0,
    withdrawal_multiplier::Float64 = 1.0
)
    StressScenario(
        name = name,
        display_name = display_name,
        equity_shock = equity_shock,
        rate_shock = rate_shock,
        vol_shock = vol_shock,
        lapse_multiplier = lapse_multiplier,
        withdrawal_multiplier = withdrawal_multiplier,
        scenario_type = CUSTOM
    )
end

# ============================================================================
# Scenario Combinations
# ============================================================================

"""
    combine_scenarios(s1, s2; name=nothing)

Combine two scenarios by summing shocks (multiplicative for multipliers).

# Arguments
- `s1::StressScenario`: First scenario
- `s2::StressScenario`: Second scenario
- `name::String`: Optional name for combined scenario

# Returns
- `StressScenario`: Combined scenario

# Example
```julia
equity_stress = create_equity_shock(-0.20)
rate_stress = create_rate_shock(-100.0)
combined = combine_scenarios(equity_stress, rate_stress, name="combined_stress")
```
"""
function combine_scenarios(
    s1::StressScenario,
    s2::StressScenario;
    name::Union{String, Nothing} = nothing
)
    combined_name = isnothing(name) ? "$(s1.name)+$(s2.name)" : name
    display = "$(s1.display_name) + $(s2.display_name)"

    StressScenario(
        name = combined_name,
        display_name = display,
        equity_shock = s1.equity_shock + s2.equity_shock,
        rate_shock = s1.rate_shock + s2.rate_shock,
        vol_shock = s1.vol_shock * s2.vol_shock,  # Multiplicative
        lapse_multiplier = s1.lapse_multiplier * s2.lapse_multiplier,
        withdrawal_multiplier = s1.withdrawal_multiplier * s2.withdrawal_multiplier,
        scenario_type = CUSTOM
    )
end

"""
    scale_scenario(scenario, factor; name=nothing)

Scale all shocks in a scenario by a factor.

# Arguments
- `scenario::StressScenario`: Base scenario
- `factor::Float64`: Scaling factor
- `name::String`: Optional name

# Example
```julia
mild_gfc = scale_scenario(crisis_to_scenario(CRISIS_2008_GFC), 0.5)  # Half-intensity
```
"""
function scale_scenario(
    scenario::StressScenario,
    factor::Float64;
    name::Union{String, Nothing} = nothing
)
    pct = round(Int, factor * 100)
    scaled_name = isnothing(name) ? "$(scenario.name)_$(pct)pct" : name
    display = "$(scenario.display_name) ($(pct)%)"

    StressScenario(
        name = scaled_name,
        display_name = display,
        equity_shock = scenario.equity_shock * factor,
        rate_shock = scenario.rate_shock * factor,
        vol_shock = 1.0 + (scenario.vol_shock - 1.0) * factor,  # Scale excess vol
        lapse_multiplier = 1.0 + (scenario.lapse_multiplier - 1.0) * factor,
        withdrawal_multiplier = 1.0 + (scenario.withdrawal_multiplier - 1.0) * factor,
        scenario_type = CUSTOM
    )
end

# ============================================================================
# Scenario Grid Generation
# ============================================================================

"""
    generate_equity_grid(shocks)

Generate scenarios for a grid of equity shocks.

# Arguments
- `shocks::Vector{Float64}`: Equity shock values

# Returns
- `Vector{StressScenario}`: One scenario per shock value

# Example
```julia
scenarios = generate_equity_grid([-0.10, -0.20, -0.30, -0.40, -0.50])
```
"""
function generate_equity_grid(shocks::Vector{Float64})
    [create_equity_shock(s) for s in shocks]
end

"""
    generate_rate_grid(shocks_bps)

Generate scenarios for a grid of rate shocks.

# Arguments
- `shocks_bps::Vector{Float64}`: Rate shocks in basis points

# Returns
- `Vector{StressScenario}`: One scenario per shock value

# Example
```julia
scenarios = generate_rate_grid([-200.0, -100.0, -50.0, 50.0, 100.0])
```
"""
function generate_rate_grid(shocks_bps::Vector{Float64})
    [create_rate_shock(s) for s in shocks_bps]
end

"""
    generate_2d_grid(equity_shocks, rate_shocks_bps)

Generate 2D grid of combined equity and rate scenarios.

# Arguments
- `equity_shocks::Vector{Float64}`: Equity shock values
- `rate_shocks_bps::Vector{Float64}`: Rate shocks in basis points

# Returns
- `Matrix{StressScenario}`: Scenarios indexed by (equity_idx, rate_idx)

# Example
```julia
grid = generate_2d_grid([-0.20, -0.30], [-100.0, -50.0])
# grid[1,1] = equity -20%, rate -100 bps
# grid[2,1] = equity -30%, rate -100 bps
```
"""
function generate_2d_grid(equity_shocks::Vector{Float64}, rate_shocks_bps::Vector{Float64})
    n_equity = length(equity_shocks)
    n_rate = length(rate_shocks_bps)
    grid = Matrix{StressScenario}(undef, n_equity, n_rate)

    for (i, eq) in enumerate(equity_shocks)
        for (j, rt) in enumerate(rate_shocks_bps)
            grid[i, j] = create_combined_scenario(
                name = "grid_eq$(round(Int, eq*100))_rt$(round(Int, rt))",
                display_name = "E:$(round(Int, eq*100))% R:$(round(Int, rt))bps",
                equity_shock = eq,
                rate_shock = rt / 10000.0
            )
        end
    end

    grid
end

# ============================================================================
# Utility Functions
# ============================================================================

"""
    scenario_summary(scenario)

Return string summary of scenario shocks.
"""
function scenario_summary(s::StressScenario)
    parts = String[]
    s.equity_shock != 0.0 && push!(parts, "Eq:$(round(Int, s.equity_shock*100))%")
    s.rate_shock != 0.0 && push!(parts, "Rt:$(round(Int, s.rate_shock*10000))bps")
    s.vol_shock != 1.0 && push!(parts, "Vol:$(round(s.vol_shock, digits=1))x")
    s.lapse_multiplier != 1.0 && push!(parts, "Lapse:$(round(s.lapse_multiplier, digits=2))x")
    s.withdrawal_multiplier != 1.0 && push!(parts, "Wdrl:$(round(s.withdrawal_multiplier, digits=2))x")

    isempty(parts) ? "No shocks" : join(parts, ", ")
end

"""
    is_adverse(scenario)

Check if scenario represents adverse conditions (negative equity or rates).
"""
function is_adverse(s::StressScenario)
    s.equity_shock < 0.0 || s.rate_shock < 0.0 || s.vol_shock > 1.0
end

"""
    severity_score(scenario)

Compute severity score for ranking scenarios.

Higher score = more severe. Weighted sum of normalized shocks.
"""
function severity_score(s::StressScenario)
    # Normalize each factor to roughly [0, 1] scale
    eq_score = abs(s.equity_shock) / 0.50  # 50% equity drop = 1.0
    rt_score = abs(s.rate_shock) / 0.0200  # 200 bps = 1.0
    vol_score = max(0.0, s.vol_shock - 1.0) / 3.0  # 4x vol = 1.0
    lapse_score = max(0.0, s.lapse_multiplier - 1.0) / 0.50  # 1.5x = 1.0
    wdrl_score = max(0.0, s.withdrawal_multiplier - 1.0) / 1.0  # 2x = 1.0

    # Weighted average (equity most important for annuities)
    0.40 * eq_score + 0.25 * rt_score + 0.15 * vol_score +
    0.10 * lapse_score + 0.10 * wdrl_score
end

"""
    sort_by_severity(scenarios; descending=true)

Sort scenarios by severity score.
"""
function sort_by_severity(scenarios::Vector{StressScenario}; descending::Bool = true)
    sort(scenarios, by=severity_score, rev=descending)
end
