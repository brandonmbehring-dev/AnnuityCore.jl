"""
Sensitivity Analysis for Stress Testing.

Implements One-at-a-Time (OAT) sensitivity analysis:
- Parameter sweeps with impact calculation
- Tornado diagram data generation
- Default parameters calibrated for annuity products
"""

using Statistics: mean

# ============================================================================
# Default Sensitivity Parameters [T2]
# ============================================================================

"""
Default equity shock parameter for sensitivity analysis.

[T2] Range based on historical crises:
- Low: -60% (near 2008 GFC trough)
- High: -10% (mild correction)
"""
const DEFAULT_EQUITY_PARAM = SensitivityParameter(
    name = "equity_shock",
    display_name = "Equity Shock",
    base_value = -0.30,
    range_low = -0.60,
    range_high = -0.10,
    unit = "%"
)

"""
Default rate shock parameter for sensitivity analysis.

[T2] Range based on historical rate movements:
- Low: -200 bps (2008 GFC level)
- High: +100 bps (2022 rising rate scenario)
"""
const DEFAULT_RATE_PARAM = SensitivityParameter(
    name = "rate_shock",
    display_name = "Rate Shock",
    base_value = -0.0050,  # -50 bps
    range_low = -0.0200,   # -200 bps
    range_high = 0.0100,   # +100 bps
    unit = "bps"
)

"""
Default volatility shock parameter.

[T2] Range based on VIX observations:
- Low: 1.0x (no change)
- High: 4.0x (extreme, ~80 VIX equivalent)
"""
const DEFAULT_VOL_PARAM = SensitivityParameter(
    name = "vol_shock",
    display_name = "Vol Multiplier",
    base_value = 1.5,
    range_low = 1.0,
    range_high = 4.0,
    unit = "x"
)

"""
Default lapse multiplier parameter.

[T2] Range based on SOA 2006 study behavior:
- Low: 0.8x (reduced lapse in ITM scenarios)
- High: 2.0x (stressed lapse environment)
"""
const DEFAULT_LAPSE_PARAM = SensitivityParameter(
    name = "lapse_multiplier",
    display_name = "Lapse Multiplier",
    base_value = 1.0,
    range_low = 0.8,
    range_high = 2.0,
    unit = "x"
)

"""
Default withdrawal multiplier parameter.

[T2] Range based on SOA 2018 GLWB study:
- Low: 0.8x (conservative utilization)
- High: 2.0x (maximum withdrawal scenario)
"""
const DEFAULT_WITHDRAWAL_PARAM = SensitivityParameter(
    name = "withdrawal_multiplier",
    display_name = "Withdrawal Multiplier",
    base_value = 1.0,
    range_low = 0.8,
    range_high = 2.0,
    unit = "x"
)

"""
All default sensitivity parameters.
"""
const DEFAULT_SENSITIVITY_PARAMS = [
    DEFAULT_EQUITY_PARAM,
    DEFAULT_RATE_PARAM,
    DEFAULT_VOL_PARAM,
    DEFAULT_LAPSE_PARAM,
    DEFAULT_WITHDRAWAL_PARAM
]

# ============================================================================
# OAT Sensitivity Analysis
# ============================================================================

"""
    run_sensitivity_sweep(param, impact_fn; n_points=21)

Run one-at-a-time sensitivity sweep for a single parameter.

# Arguments
- `param::SensitivityParameter`: Parameter to vary
- `impact_fn::Function`: Function mapping parameter value to metric
- `n_points::Int`: Number of points in sweep (default 21)

# Returns
- `SensitivityResult`: Sweep results with values and impacts

# Example
```julia
param = DEFAULT_EQUITY_PARAM
impact_fn = shock -> calculate_reserve_impact(shock)
result = run_sensitivity_sweep(param, impact_fn)
```
"""
function run_sensitivity_sweep(
    param::SensitivityParameter,
    impact_fn::Function;
    n_points::Int = 21
)::SensitivityResult
    # Generate parameter values
    values = range(param.range_low, param.range_high, length=n_points) |> collect

    # Calculate impact at each value
    impacts = [impact_fn(v) for v in values]

    # Get base metric (at base value)
    base_metric = impact_fn(param.base_value)

    SensitivityResult(param, values, impacts, base_metric)
end

"""
    run_multi_sensitivity(params, scenario_builder, metric_fn; n_points=21)

Run sensitivity analysis for multiple parameters.

# Arguments
- `params::Vector{SensitivityParameter}`: Parameters to analyze
- `scenario_builder::Function`: Function (param_name, value) -> StressScenario
- `metric_fn::Function`: Function (scenario) -> metric value
- `n_points::Int`: Points per parameter sweep

# Returns
- `Vector{SensitivityResult}`: Results for each parameter

# Example
```julia
results = run_multi_sensitivity(
    DEFAULT_SENSITIVITY_PARAMS,
    (name, val) -> build_scenario(name, val),
    scenario -> run_stress_test(scenario).reserve_impact
)
```
"""
function run_multi_sensitivity(
    params::Vector{SensitivityParameter},
    scenario_builder::Function,
    metric_fn::Function;
    n_points::Int = 21
)::Vector{SensitivityResult}
    results = SensitivityResult[]

    for param in params
        # Create impact function that varies only this parameter
        impact_fn = function(value)
            scenario = scenario_builder(param.name, value)
            metric_fn(scenario)
        end

        push!(results, run_sensitivity_sweep(param, impact_fn; n_points))
    end

    results
end

# ============================================================================
# Tornado Diagram Generation
# ============================================================================

"""
    build_tornado_data(results)

Build tornado diagram data from sensitivity results.

# Arguments
- `results::Vector{SensitivityResult}`: Sensitivity analysis results

# Returns
- `TornadoData`: Data formatted for tornado visualization

# Example
```julia
results = run_multi_sensitivity(...)
tornado = build_tornado_data(results)
```
"""
function build_tornado_data(results::Vector{SensitivityResult})::TornadoData
    parameters = String[]
    low_impacts = Float64[]
    high_impacts = Float64[]

    for result in results
        push!(parameters, result.parameter.display_name)
        push!(low_impacts, result.impacts[1])      # Impact at range_low
        push!(high_impacts, result.impacts[end])   # Impact at range_high
    end

    # Use first result's base metric (should be same for all)
    base_value = isempty(results) ? 0.0 : results[1].base_metric

    TornadoData(;
        parameters,
        low_impacts,
        high_impacts,
        base_value
    )
end

"""
    sort_tornado!(tornado; descending=true)

Sort tornado data by impact range (in-place).

# Arguments
- `tornado::TornadoData`: Tornado data to sort
- `descending::Bool`: If true, largest impact first

# Returns
- `TornadoData`: New sorted tornado data
"""
function sort_tornado(tornado::TornadoData; descending::Bool = true)
    n = length(tornado.parameters)
    ranges = [impact_range(tornado, i) for i in 1:n]

    # Get sort indices
    indices = sortperm(ranges, rev=descending)

    TornadoData(;
        parameters = tornado.parameters[indices],
        low_impacts = tornado.low_impacts[indices],
        high_impacts = tornado.high_impacts[indices],
        base_value = tornado.base_value
    )
end

"""
    top_n_tornado(tornado, n)

Get top N most impactful parameters from tornado.

# Arguments
- `tornado::TornadoData`: Full tornado data
- `n::Int`: Number of parameters to keep

# Returns
- `TornadoData`: Truncated tornado with top N parameters
"""
function top_n_tornado(tornado::TornadoData, n::Int)
    sorted = sort_tornado(tornado)
    n_keep = min(n, length(sorted.parameters))

    TornadoData(;
        parameters = sorted.parameters[1:n_keep],
        low_impacts = sorted.low_impacts[1:n_keep],
        high_impacts = sorted.high_impacts[1:n_keep],
        base_value = sorted.base_value
    )
end

# ============================================================================
# Sensitivity Metrics
# ============================================================================

"""
    sensitivity_elasticity(result)

Calculate elasticity of metric with respect to parameter.

Returns (Δmetric / metric) / (Δparam / param) at base values.
"""
function sensitivity_elasticity(result::SensitivityResult)::Float64
    param = result.parameter
    base_metric = result.base_metric

    # Use midpoint derivative approximation
    idx_low = findfirst(v -> v <= param.base_value, result.values)
    idx_high = findfirst(v -> v >= param.base_value, result.values)

    isnothing(idx_low) && (idx_low = 1)
    isnothing(idx_high) && (idx_high = length(result.values))

    if idx_low == idx_high
        idx_low = max(1, idx_low - 1)
    end

    # Calculate percentage changes
    param_change = (result.values[idx_high] - result.values[idx_low]) / param.base_value
    metric_change = (result.impacts[idx_high] - result.impacts[idx_low]) / base_metric

    abs(param_change) < 1e-10 ? 0.0 : metric_change / param_change
end

"""
    monotonicity(result)

Check if sensitivity result is monotonic.

# Returns
- `:increasing`: Strictly increasing
- `:decreasing`: Strictly decreasing
- `:non_monotonic`: Not monotonic
"""
function monotonicity(result::SensitivityResult)::Symbol
    diffs = diff(result.impacts)

    all(d >= 0 for d in diffs) && return :increasing
    all(d <= 0 for d in diffs) && return :decreasing
    :non_monotonic
end

"""
    max_impact(result)

Get maximum absolute impact from sensitivity sweep.
"""
function max_impact(result::SensitivityResult)::Float64
    maximum(abs.(result.impacts .- result.base_metric))
end

"""
    impact_at_extreme(result, extreme::Symbol)

Get impact at low or high extreme.

# Arguments
- `result::SensitivityResult`: Sensitivity result
- `extreme::Symbol`: `:low` or `:high`
"""
function impact_at_extreme(result::SensitivityResult, extreme::Symbol)::Float64
    if extreme == :low
        return result.impacts[1]
    elseif extreme == :high
        return result.impacts[end]
    else
        error("extreme must be :low or :high")
    end
end

# ============================================================================
# Sensitivity Analysis Configuration
# ============================================================================

"""
    SensitivityConfig

Configuration for sensitivity analysis.

# Fields
- `parameters::Vector{SensitivityParameter}`: Parameters to analyze
- `n_points::Int`: Points per sweep
- `include_interactions::Bool`: Whether to include 2-way interactions
"""
struct SensitivityConfig
    parameters::Vector{SensitivityParameter}
    n_points::Int
    include_interactions::Bool

    function SensitivityConfig(;
        parameters::Vector{SensitivityParameter} = DEFAULT_SENSITIVITY_PARAMS,
        n_points::Int = 21,
        include_interactions::Bool = false
    )
        n_points < 3 && error("n_points must be >= 3")
        new(parameters, n_points, include_interactions)
    end
end

"""
    SensitivityAnalyzer

Analyzer for running full sensitivity analysis.

# Fields
- `config::SensitivityConfig`: Analysis configuration
- `scenario_builder::Function`: Builds scenario from (param_name, value)
- `metric_fn::Function`: Extracts metric from scenario result
"""
struct SensitivityAnalyzer
    config::SensitivityConfig
    scenario_builder::Function
    metric_fn::Function
end

"""
    run_analysis(analyzer)

Run full sensitivity analysis.

# Returns
Named tuple with:
- `results::Vector{SensitivityResult}`: Individual parameter results
- `tornado::TornadoData`: Tornado diagram data
- `top_driver::String`: Most impactful parameter
- `elasticities::Dict{String, Float64}`: Parameter elasticities
"""
function run_analysis(analyzer::SensitivityAnalyzer)
    # Run sweeps for all parameters
    results = run_multi_sensitivity(
        analyzer.config.parameters,
        analyzer.scenario_builder,
        analyzer.metric_fn;
        n_points = analyzer.config.n_points
    )

    # Build tornado data
    tornado = build_tornado_data(results)
    sorted_tornado = sort_tornado(tornado)

    # Find top driver
    top_driver = isempty(sorted_tornado.parameters) ? "" : sorted_tornado.parameters[1]

    # Calculate elasticities
    elasticities = Dict{String, Float64}()
    for result in results
        elasticities[result.parameter.name] = sensitivity_elasticity(result)
    end

    (
        results = results,
        tornado = sorted_tornado,
        top_driver = top_driver,
        elasticities = elasticities
    )
end

# ============================================================================
# Two-Way Interaction Analysis
# ============================================================================

"""
    run_interaction_analysis(param1, param2, scenario_builder, metric_fn; n_points=11)

Run two-way sensitivity analysis for parameter interactions.

# Arguments
- `param1::SensitivityParameter`: First parameter
- `param2::SensitivityParameter`: Second parameter
- `scenario_builder::Function`: Function (name1, val1, name2, val2) -> scenario
- `metric_fn::Function`: Function scenario -> metric
- `n_points::Int`: Points per parameter (total grid = n^2)

# Returns
Named tuple with:
- `values1::Vector{Float64}`: Parameter 1 values
- `values2::Vector{Float64}`: Parameter 2 values
- `impacts::Matrix{Float64}`: Impact grid [i, j] = f(val1[i], val2[j])
"""
function run_interaction_analysis(
    param1::SensitivityParameter,
    param2::SensitivityParameter,
    scenario_builder::Function,
    metric_fn::Function;
    n_points::Int = 11
)
    values1 = range(param1.range_low, param1.range_high, length=n_points) |> collect
    values2 = range(param2.range_low, param2.range_high, length=n_points) |> collect

    impacts = Matrix{Float64}(undef, n_points, n_points)

    for (i, v1) in enumerate(values1)
        for (j, v2) in enumerate(values2)
            scenario = scenario_builder(param1.name, v1, param2.name, v2)
            impacts[i, j] = metric_fn(scenario)
        end
    end

    (
        param1 = param1,
        param2 = param2,
        values1 = values1,
        values2 = values2,
        impacts = impacts
    )
end

"""
    interaction_effect(interaction_result)

Calculate interaction effect (non-additivity).

Returns the average deviation from additive model:
impact(v1, v2) - (impact(v1, base2) + impact(base1, v2) - impact(base1, base2))
"""
function interaction_effect(result)::Float64
    n1 = length(result.values1)
    n2 = length(result.values2)

    # Find base indices (closest to base value)
    base_idx1 = argmin(abs.(result.values1 .- result.param1.base_value))
    base_idx2 = argmin(abs.(result.values2 .- result.param2.base_value))

    base_impact = result.impacts[base_idx1, base_idx2]

    # Calculate interaction effects
    effects = Float64[]
    for i in 1:n1
        for j in 1:n2
            # Additive prediction
            additive = result.impacts[i, base_idx2] + result.impacts[base_idx1, j] - base_impact
            # Actual impact
            actual = result.impacts[i, j]
            # Interaction = actual - additive
            push!(effects, actual - additive)
        end
    end

    mean(abs.(effects))
end

# ============================================================================
# Utility Functions
# ============================================================================

"""
    print_sensitivity_summary(results)

Print summary of sensitivity analysis results.
"""
function print_sensitivity_summary(results::Vector{SensitivityResult})
    println("Sensitivity Analysis Summary")
    println("="^60)
    println()

    sorted = sort(results, by=max_impact, rev=true)

    for result in sorted
        param = result.parameter
        mi = max_impact(result)
        el = sensitivity_elasticity(result)
        mono = monotonicity(result)

        println("$(param.display_name)")
        println("  Range: $(param.range_low) to $(param.range_high) $(param.unit)")
        println("  Max Impact: $(round(mi, digits=4))")
        println("  Elasticity: $(round(el, digits=3))")
        println("  Monotonic: $(mono)")
        println()
    end
end

"""
    print_tornado(tornado)

Print tornado diagram as text.
"""
function print_tornado(tornado::TornadoData)
    sorted = sort_tornado(tornado)

    println("Tornado Diagram")
    println("Base Value: $(round(sorted.base_value, digits=4))")
    println("="^60)
    println()

    for i in 1:length(sorted.parameters)
        name = sorted.parameters[i]
        low = sorted.low_impacts[i]
        high = sorted.high_impacts[i]
        rng = abs(high - low)

        println("$(name)")
        println("  Low:  $(round(low, digits=4))")
        println("  High: $(round(high, digits=4))")
        println("  Range: $(round(rng, digits=4))")
        println()
    end
end
