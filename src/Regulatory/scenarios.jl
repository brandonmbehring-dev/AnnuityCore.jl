#=============================================================================
# Scenario Generation - Phase 9
#
# [PROTOTYPE] EDUCATIONAL USE ONLY - NOT FOR NAIC REGULATORY FILING
# =========================================================================
# This module generates economic scenarios using standard academic models
# for educational purposes. It is NOT NAIC-compliant for regulatory filings.
#
# CRITICAL LIMITATION:
# This generator uses custom Vasicek + GBM models, NOT the NAIC-prescribed
# scenario generators required for VM-21/VM-22 compliance:
#
# - Current requirement: AAA Economic Scenario Generator (ESG)
# - Future requirement: GOES (Generator of Economic Scenarios)
#   Effective date: December 31, 2026
#
# See: docs/regulatory/AG43_COMPLIANCE_GAP.md
# =========================================================================
=============================================================================#

using Random
using Statistics

#=============================================================================
# Scenario Generator
=============================================================================#

"""
    ScenarioGenerator

Economic scenario generator for VM-21/AG43.

[PROTOTYPE] NOT NAIC-COMPLIANT
------------------------------
This generator uses academic Vasicek + GBM models, NOT the NAIC-prescribed
AAA ESG or GOES generators required for regulatory compliance.
Use for education and research only.

# Fields
- `n_scenarios::Int`: Number of scenarios to generate
- `projection_years::Int`: Years to project in each scenario
- `seed::Union{Int, Nothing}`: Random seed for reproducibility
- `rng::AbstractRNG`: Random number generator

# Example
```julia
gen = ScenarioGenerator(n_scenarios=1000, seed=42)
scenarios = generate_ag43_scenarios(gen)
length(scenarios.scenarios)  # 1000
```
"""
mutable struct ScenarioGenerator
    n_scenarios::Int
    projection_years::Int
    seed::Union{Int, Nothing}
    rng::AbstractRNG

    function ScenarioGenerator(n_scenarios::Int, projection_years::Int, seed::Union{Int, Nothing})
        n_scenarios > 0 || error("CRITICAL: n_scenarios must be positive, got $n_scenarios")
        projection_years > 0 || error("CRITICAL: projection_years must be positive, got $projection_years")
        rng = seed === nothing ? Random.default_rng() : MersenneTwister(seed)
        new(n_scenarios, projection_years, seed, rng)
    end
end

# Keyword constructor
function ScenarioGenerator(;
    n_scenarios::Int = 1000,
    projection_years::Int = 30,
    seed::Union{Int, Nothing} = nothing
)
    ScenarioGenerator(n_scenarios, projection_years, seed)
end


"""
    generate_ag43_scenarios(gen; initial_rate, initial_equity, rate_params, equity_params, correlation)

Generate AG43-compliant scenarios.

[T1] AG43 requires correlated interest rate and equity scenarios.

# Arguments
- `gen::ScenarioGenerator`: The scenario generator

# Keyword Arguments
- `initial_rate::Float64=0.04`: Starting interest rate
- `initial_equity::Float64=100.0`: Starting equity index level
- `rate_params::VasicekParams=VasicekParams()`: Interest rate model parameters
- `equity_params::EquityParams=EquityParams()`: Equity model parameters
- `correlation::Float64=-0.20`: Correlation between rate and equity shocks

# Returns
- `AG43Scenarios`: Collection of economic scenarios

# Example
```julia
gen = ScenarioGenerator(n_scenarios=100, seed=42)
scenarios = generate_ag43_scenarios(gen)
length(scenarios.scenarios)  # 100
```
"""
function generate_ag43_scenarios(
    gen::ScenarioGenerator;
    initial_rate::Float64 = 0.04,
    initial_equity::Float64 = 100.0,
    rate_params::VasicekParams = VasicekParams(),
    equity_params::EquityParams = EquityParams(),
    correlation::Float64 = -0.20
)::AG43Scenarios
    -1 <= correlation <= 1 || error("CRITICAL: Correlation must be in [-1, 1], got $correlation")

    # Generate correlated shocks
    rate_shocks, equity_shocks = _generate_correlated_shocks(gen, correlation)

    # Generate rate and equity paths
    rate_paths = _generate_vasicek_paths(gen, initial_rate, rate_params, rate_shocks)
    equity_paths = _generate_gbm_returns(gen, equity_params, equity_shocks)

    # Build scenario objects
    scenarios = EconomicScenario[]
    for i in 1:gen.n_scenarios
        scenario = EconomicScenario(
            rates = rate_paths[i, :],
            equity_returns = equity_paths[i, :],
            scenario_id = i
        )
        push!(scenarios, scenario)
    end

    AG43Scenarios(scenarios, gen.n_scenarios, gen.projection_years)
end


"""
    generate_risk_neutral_scenarios(gen; yield_curve, dividend_yield, equity_sigma, rate_params, correlation)

Generate scenarios using risk-neutral equity drift.

[T1] Risk-neutral drift = r - q (forward rate - dividend yield).

This is the correct approach for pricing purposes (VM-21, GLWB valuation).
Use generate_ag43_scenarios() for real-world scenarios (stress testing).

# Arguments
- `gen::ScenarioGenerator`: The scenario generator

# Keyword Arguments
- `yield_curve::Union{YieldCurve, Nothing}=nothing`: Yield curve for drift. If nothing, uses flat 4%.
- `dividend_yield::Float64=0.02`: Continuous dividend yield
- `equity_sigma::Float64=0.18`: Equity volatility
- `rate_params::VasicekParams=VasicekParams()`: Interest rate model parameters
- `correlation::Float64=-0.20`: Correlation between rate and equity shocks

# Returns
- `AG43Scenarios`: Collection of risk-neutral scenarios
"""
function generate_risk_neutral_scenarios(
    gen::ScenarioGenerator;
    yield_curve::Union{YieldCurve, Nothing} = nothing,
    dividend_yield::Float64 = 0.02,
    equity_sigma::Float64 = 0.18,
    rate_params::VasicekParams = VasicekParams(),
    correlation::Float64 = -0.20
)::AG43Scenarios
    -1 <= correlation <= 1 || error("CRITICAL: Correlation must be in [-1, 1], got $correlation")

    # Default to flat 4% curve
    if yield_curve === nothing
        yield_curve = flat_curve(0.04)
    end

    initial_rate = get_rate(yield_curve, 1.0)

    # Create risk-neutral equity params using yield curve
    # [T1] Under risk-neutral: mu = r - q
    rn_equity_params = RiskNeutralEquityParams(
        risk_free_rate = initial_rate,
        dividend_yield = dividend_yield,
        sigma = equity_sigma
    )

    # Generate correlated shocks
    rate_shocks, equity_shocks = _generate_correlated_shocks(gen, correlation)

    # Generate rate paths from Vasicek
    rate_paths = _generate_vasicek_paths(gen, initial_rate, rate_params, rate_shocks)

    # Generate equity returns using risk-neutral drift
    equity_paths = _generate_gbm_returns(gen, to_equity_params(rn_equity_params), equity_shocks)

    # Build scenario objects
    scenarios = EconomicScenario[]
    for i in 1:gen.n_scenarios
        scenario = EconomicScenario(
            rates = rate_paths[i, :],
            equity_returns = equity_paths[i, :],
            scenario_id = i
        )
        push!(scenarios, scenario)
    end

    AG43Scenarios(scenarios, gen.n_scenarios, gen.projection_years)
end


"""
    generate_rate_scenarios(gen; initial_rate, params)

Generate interest rate scenarios using Vasicek model.

[T1] dr = κ(θ - r)dt + σ dW

# Arguments
- `gen::ScenarioGenerator`: The scenario generator

# Keyword Arguments
- `initial_rate::Float64=0.04`: Starting interest rate
- `params::VasicekParams=VasicekParams()`: Model parameters

# Returns
- `Matrix{Float64}`: Rate scenarios [n_scenarios × projection_years]

# Example
```julia
gen = ScenarioGenerator(n_scenarios=100, seed=42)
rates = generate_rate_scenarios(gen)
size(rates)  # (100, 30)
```
"""
function generate_rate_scenarios(
    gen::ScenarioGenerator;
    initial_rate::Float64 = 0.04,
    params::VasicekParams = VasicekParams()
)::Matrix{Float64}
    initial_rate >= 0 || error("CRITICAL: Initial rate cannot be negative, got $initial_rate")

    shocks = randn(gen.rng, gen.n_scenarios, gen.projection_years)
    _generate_vasicek_paths(gen, initial_rate, params, shocks)
end


"""
    generate_equity_scenarios(gen; mu, sigma)

Generate equity return scenarios using GBM.

[T1] Log returns: ln(S_t/S_{t-1}) ~ N(μ - σ²/2, σ²)

# Arguments
- `gen::ScenarioGenerator`: The scenario generator

# Keyword Arguments
- `mu::Float64=0.07`: Expected return (drift)
- `sigma::Float64=0.18`: Volatility

# Returns
- `Matrix{Float64}`: Equity return scenarios [n_scenarios × projection_years]
"""
function generate_equity_scenarios(
    gen::ScenarioGenerator;
    mu::Float64 = 0.07,
    sigma::Float64 = 0.18
)::Matrix{Float64}
    sigma >= 0 || error("CRITICAL: Volatility cannot be negative, got $sigma")

    params = EquityParams(mu, sigma)
    shocks = randn(gen.rng, gen.n_scenarios, gen.projection_years)
    _generate_gbm_returns(gen, params, shocks)
end


#=============================================================================
# Internal Helper Functions
=============================================================================#

"""Generate correlated standard normal shocks using Cholesky decomposition."""
function _generate_correlated_shocks(
    gen::ScenarioGenerator,
    correlation::Float64
)::Tuple{Matrix{Float64}, Matrix{Float64}}
    # Generate independent shocks
    z1 = randn(gen.rng, gen.n_scenarios, gen.projection_years)
    z2 = randn(gen.rng, gen.n_scenarios, gen.projection_years)

    # Apply Cholesky: [z_rate, z_equity] = L @ [z1, z2]
    # L = [[1, 0], [ρ, sqrt(1-ρ²)]]
    rate_shocks = z1
    equity_shocks = correlation .* z1 .+ sqrt(1 - correlation^2) .* z2

    (rate_shocks, equity_shocks)
end


"""
Generate Vasicek rate paths.

[T1] Euler discretization: r_{t+1} = r_t + κ(θ - r_t) + σ * Z
"""
function _generate_vasicek_paths(
    gen::ScenarioGenerator,
    initial_rate::Float64,
    params::VasicekParams,
    shocks::Matrix{Float64}
)::Matrix{Float64}
    n_scenarios, n_years = size(shocks)
    rates = zeros(n_scenarios, n_years)

    # Initialize with first step
    r_prev = fill(initial_rate, n_scenarios)

    for t in 1:n_years
        # Vasicek: r_{t+1} = r_t + κ(θ - r_t)*dt + σ*sqrt(dt)*Z
        # With dt = 1 year:
        r_new = r_prev .+ params.kappa .* (params.theta .- r_prev) .+ params.sigma .* shocks[:, t]
        # Floor at zero (avoid negative rates in this simple model)
        rates[:, t] = max.(r_new, 0.0)
        r_prev = rates[:, t]
    end

    rates
end


"""
Generate GBM returns.

[T1] Log return = (μ - σ²/2) + σZ
"""
function _generate_gbm_returns(
    gen::ScenarioGenerator,
    params::EquityParams,
    shocks::Matrix{Float64}
)::Matrix{Float64}
    # Log return: (μ - σ²/2) + σZ
    log_returns = (params.mu - 0.5 * params.sigma^2) .+ params.sigma .* shocks
    # Convert to simple returns: exp(log_return) - 1
    returns = exp.(log_returns) .- 1
    returns
end


#=============================================================================
# Convenience Functions
=============================================================================#

"""
    generate_deterministic_scenarios(; n_years, base_rate, base_equity)

Generate deterministic stress scenarios for VM-22.

[T1] VM-22 deterministic reserve uses prescribed stress scenarios.

# Keyword Arguments
- `n_years::Int=30`: Projection years
- `base_rate::Float64=0.04`: Base interest rate
- `base_equity::Float64=0.07`: Base equity return

# Returns
- `Vector{EconomicScenario}`: Deterministic scenarios (base, up, down)

# Example
```julia
scenarios = generate_deterministic_scenarios()
length(scenarios)  # 3
```
"""
function generate_deterministic_scenarios(;
    n_years::Int = 30,
    base_rate::Float64 = 0.04,
    base_equity::Float64 = 0.07
)::Vector{EconomicScenario}
    scenarios = EconomicScenario[]

    # Base scenario
    push!(scenarios, EconomicScenario(
        rates = fill(base_rate, n_years),
        equity_returns = fill(base_equity, n_years),
        scenario_id = 0
    ))

    # Rate up scenario (+2%)
    push!(scenarios, EconomicScenario(
        rates = fill(base_rate + 0.02, n_years),
        equity_returns = fill(base_equity - 0.02, n_years),  # Inverse correlation
        scenario_id = 1
    ))

    # Rate down scenario (-2%)
    push!(scenarios, EconomicScenario(
        rates = fill(max(0.0, base_rate - 0.02), n_years),
        equity_returns = fill(base_equity + 0.02, n_years),
        scenario_id = 2
    ))

    scenarios
end


"""
    calculate_scenario_statistics(scenarios::AG43Scenarios)

Calculate summary statistics for scenarios.

# Arguments
- `scenarios::AG43Scenarios`: Generated scenarios

# Returns
- `Dict{String, Any}`: Statistics including means, std devs, percentiles

# Example
```julia
gen = ScenarioGenerator(n_scenarios=100, seed=42)
scenarios = generate_ag43_scenarios(gen)
stats = calculate_scenario_statistics(scenarios)
haskey(stats, "rate_mean")  # true
```
"""
function calculate_scenario_statistics(scenarios::AG43Scenarios)::Dict{String, Any}
    rate_matrix = get_rate_matrix(scenarios)
    equity_matrix = get_equity_matrix(scenarios)

    # Terminal values (last year)
    terminal_rates = rate_matrix[:, end]
    cumulative_equity = prod(1 .+ equity_matrix, dims=2) .- 1

    Dict{String, Any}(
        # Rate statistics
        "rate_mean" => mean(rate_matrix),
        "rate_std" => std(rate_matrix),
        "rate_min" => minimum(rate_matrix),
        "rate_max" => maximum(rate_matrix),
        "terminal_rate_mean" => mean(terminal_rates),
        "terminal_rate_5pct" => quantile(vec(terminal_rates), 0.05),
        "terminal_rate_95pct" => quantile(vec(terminal_rates), 0.95),
        # Equity statistics
        "equity_return_mean" => mean(equity_matrix),
        "equity_return_std" => std(equity_matrix),
        "cumulative_return_mean" => mean(cumulative_equity),
        "cumulative_return_5pct" => quantile(vec(cumulative_equity), 0.05),
        "cumulative_return_95pct" => quantile(vec(cumulative_equity), 0.95),
        # Counts
        "n_scenarios" => scenarios.n_scenarios,
        "projection_years" => scenarios.projection_years
    )
end
