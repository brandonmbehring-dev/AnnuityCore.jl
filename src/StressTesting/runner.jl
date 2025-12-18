"""
Stress Test Runner.

Orchestrates complete stress testing workflow:
- Run scenarios against impact model
- Execute sensitivity analysis
- Perform reverse stress testing
- Generate comprehensive reports
"""

using Statistics: mean, std

# ============================================================================
# Simplified Impact Model [T3]
# ============================================================================

"""
    calculate_reserve_impact(scenario, base_reserve)

Calculate stressed reserve using simplified impact model.

[T3] Simplified model based on typical annuity sensitivities:
- Equity shock: Direct impact on account values
- Rate shock: Duration-based reserve impact
- Vol shock: Option value impact
- Lapse: Liability release/cost
- Withdrawal: Accelerated payouts

Coefficients calibrated to approximate VA/FIA reserve behavior.

# Arguments
- `scenario::StressScenario`: Stress scenario to apply
- `base_reserve::Float64`: Starting reserve value

# Returns
Named tuple with:
- `stressed_reserve::Float64`: Reserve after stress
- `total_impact::Float64`: Total percentage impact
- `components::Dict{String, Float64}`: Individual impact components
"""
function calculate_reserve_impact(
    scenario::StressScenario,
    base_reserve::Float64
)
    # Impact coefficients [T3 - calibrated to typical VA sensitivities]
    # These represent approximate reserve sensitivities:
    # - 80% equity beta (reserves ~80% sensitive to equity)
    # - 10 duration (1% rate = 10% reserve)
    # - 15% vol sensitivity (vol doubling = 15% impact)
    # - 10% lapse sensitivity
    # - 16% withdrawal sensitivity (for GLWB products)

    equity_impact = -scenario.equity_shock * 0.80
    rate_impact = -scenario.rate_shock * 10.0
    vol_impact = (scenario.vol_shock - 1.0) * 0.15
    lapse_impact = -(scenario.lapse_multiplier - 1.0) * 0.10
    withdrawal_impact = (scenario.withdrawal_multiplier - 1.0) * 0.16

    total_impact = equity_impact + rate_impact + vol_impact + lapse_impact + withdrawal_impact

    stressed_reserve = base_reserve * (1.0 + total_impact)

    (
        stressed_reserve = max(0.0, stressed_reserve),  # Floor at zero
        total_impact = total_impact,
        components = Dict(
            "equity" => equity_impact,
            "rate" => rate_impact,
            "vol" => vol_impact,
            "lapse" => lapse_impact,
            "withdrawal" => withdrawal_impact
        )
    )
end

"""
    calculate_rbc_ratio(scenario, base_reserve, required_capital)

Calculate RBC ratio under stress.

# Arguments
- `scenario::StressScenario`: Stress scenario
- `base_reserve::Float64`: Starting reserve
- `required_capital::Float64`: Required capital (denominator for RBC)

# Returns
- `Float64`: RBC ratio (reserve / required_capital)
"""
function calculate_rbc_ratio(
    scenario::StressScenario,
    base_reserve::Float64,
    required_capital::Float64
)
    required_capital <= 0.0 && error("required_capital must be positive")

    result = calculate_reserve_impact(scenario, base_reserve)
    result.stressed_reserve / required_capital
end

# ============================================================================
# Stress Test Runner
# ============================================================================

"""
    StressTestRunner

Orchestrates stress testing workflow.

# Fields
- `config::StressTestConfig`: Runner configuration
- `scenarios::Vector{StressScenario}`: Scenarios to run
- `impact_fn::Union{Function, Nothing}`: Custom impact function (optional)
"""
struct StressTestRunner
    config::StressTestConfig
    scenarios::Vector{StressScenario}
    impact_fn::Union{Function, Nothing}

    function StressTestRunner(;
        config::StressTestConfig,
        scenarios::Vector{StressScenario} = StressScenario[],
        impact_fn::Union{Function, Nothing} = nothing
    )
        new(config, scenarios, impact_fn)
    end
end

"""
Create runner with ORSA scenarios.
"""
function orsa_runner(config::StressTestConfig)
    StressTestRunner(;
        config,
        scenarios = ORSA_SCENARIOS
    )
end

"""
Create runner with historical scenarios.
"""
function historical_runner(config::StressTestConfig)
    StressTestRunner(;
        config,
        scenarios = historical_scenarios()
    )
end

"""
Create runner with all standard scenarios (ORSA + historical).
"""
function standard_runner(config::StressTestConfig)
    all_scenarios = vcat(ORSA_SCENARIOS, historical_scenarios())
    StressTestRunner(;
        config,
        scenarios = all_scenarios
    )
end

# ============================================================================
# Running Stress Tests
# ============================================================================

"""
    run_scenario(runner, scenario)

Run a single stress scenario.

# Returns
- `StressTestResult`: Result for this scenario
"""
function run_scenario(
    runner::StressTestRunner,
    scenario::StressScenario
)::StressTestResult
    base_reserve = runner.config.base_reserve

    # Use custom impact function if provided, otherwise default
    if !isnothing(runner.impact_fn)
        result = runner.impact_fn(scenario, base_reserve)
        stressed_reserve = result.stressed_reserve
        total_impact = result.total_impact
    else
        result = calculate_reserve_impact(scenario, base_reserve)
        stressed_reserve = result.stressed_reserve
        total_impact = result.total_impact
    end

    reserve_impact = stressed_reserve - base_reserve
    reserve_impact_pct = base_reserve > 0.0 ? reserve_impact / base_reserve : 0.0

    # Calculate RBC if threshold is set
    rbc_ratio = nothing
    if runner.config.rbc_threshold > 0.0
        # Assume required capital = base_reserve / target_rbc
        # This is simplified; real implementation would use actual required capital
        required_capital = base_reserve / runner.config.rbc_threshold
        rbc_ratio = stressed_reserve / required_capital
    end

    # Check pass/fail
    passed = stressed_reserve >= runner.config.minimum_reserve_ratio * base_reserve
    if !isnothing(rbc_ratio)
        passed = passed && rbc_ratio >= runner.config.rbc_threshold
    end

    StressTestResult(
        scenario,
        base_reserve,
        stressed_reserve,
        reserve_impact,
        reserve_impact_pct,
        rbc_ratio,
        passed
    )
end

"""
    run_all_scenarios(runner)

Run all configured scenarios.

# Returns
- `Vector{StressTestResult}`: Results for all scenarios
"""
function run_all_scenarios(runner::StressTestRunner)::Vector{StressTestResult}
    [run_scenario(runner, s) for s in runner.scenarios]
end

"""
    run_stress_test(runner)

Run complete stress test including optional sensitivity and reverse analysis.

# Returns
- `StressTestSummary`: Complete summary with all analyses
"""
function run_stress_test(runner::StressTestRunner)::StressTestSummary
    # Run all scenarios
    scenario_results = run_all_scenarios(runner)

    # Find worst case (highest stressed reserve = most capital strain)
    # In the impact model, adverse shocks INCREASE reserves (liability perspective)
    worst_result = argmax(r -> r.stressed_reserve, scenario_results)

    # Check if all passed
    all_passed = all(r -> r.passed, scenario_results)

    # Run sensitivity analysis if configured
    sensitivity = nothing
    if runner.config.run_sensitivity
        sensitivity = run_runner_sensitivity(runner)
    end

    # Run reverse stress if configured
    reverse_report = nothing
    if runner.config.run_reverse
        reverse_report = run_runner_reverse(runner)
    end

    StressTestSummary(
        runner.config,
        scenario_results,
        sensitivity,
        reverse_report,
        worst_result,
        all_passed
    )
end

# ============================================================================
# Integrated Sensitivity Analysis
# ============================================================================

"""
Run sensitivity analysis using runner's impact model.
"""
function run_runner_sensitivity(runner::StressTestRunner)::TornadoData
    base = runner.config.base_reserve

    # Build scenario from parameter name and value
    scenario_builder = function(param_name, value)
        if param_name == "equity_shock"
            create_equity_shock(value)
        elseif param_name == "rate_shock"
            create_rate_shock(value * 10000)  # Convert to bps for builder
        elseif param_name == "vol_shock"
            create_vol_shock(value)
        elseif param_name == "lapse_multiplier"
            create_behavioral_shock(value, 1.0)
        elseif param_name == "withdrawal_multiplier"
            create_behavioral_shock(1.0, value)
        else
            error("Unknown parameter: $param_name")
        end
    end

    # Metric function
    metric_fn = function(scenario)
        result = calculate_reserve_impact(scenario, base)
        result.stressed_reserve
    end

    # Run sensitivity
    results = run_multi_sensitivity(
        DEFAULT_SENSITIVITY_PARAMS,
        scenario_builder,
        metric_fn;
        n_points = runner.config.n_sensitivity_points
    )

    sort_tornado(build_tornado_data(results))
end

# ============================================================================
# Integrated Reverse Stress Testing
# ============================================================================

"""
Run reverse stress testing using runner's impact model.
"""
function run_runner_reverse(runner::StressTestRunner)::ReverseStressReport
    base = runner.config.base_reserve

    # Use reserve ratio below 50% as default target
    target = RESERVE_RATIO_50

    # Scenario builder
    scenario_builder = function(param_name, value)
        if param_name == "equity_shock"
            create_equity_shock(value)
        elseif param_name == "rate_shock"
            create_rate_shock(value * 10000)
        elseif param_name == "vol_shock"
            create_vol_shock(value)
        elseif param_name == "lapse_multiplier"
            create_behavioral_shock(value, 1.0)
        elseif param_name == "withdrawal_multiplier"
            create_behavioral_shock(1.0, value)
        else
            error("Unknown parameter: $param_name")
        end
    end

    # Metric function (reserve ratio)
    metric_fn = function(scenario)
        result = calculate_reserve_impact(scenario, base)
        result.stressed_reserve / base
    end

    tester = ReverseStressTester(
        target,
        DEFAULT_SENSITIVITY_PARAMS,
        metric_fn,
        scenario_builder
    )

    run_reverse_test(tester)
end

# ============================================================================
# Report Generation
# ============================================================================

"""
    print_stress_summary(summary)

Print stress test summary report.
"""
function print_stress_summary(summary::StressTestSummary)
    println("="^70)
    println("STRESS TEST SUMMARY")
    println("="^70)
    println()

    println("Configuration:")
    println("  Base Reserve: \$$(round(Int, summary.config.base_reserve))")
    println("  Min Reserve Ratio: $(round(summary.config.minimum_reserve_ratio * 100, digits=1))%")
    println("  RBC Threshold: $(round(summary.config.rbc_threshold * 100, digits=0))%")
    println()

    println("Results: $(length(summary.scenario_results)) scenarios run")
    println("  All Passed: $(summary.all_passed)")
    println()

    # Scenario results table
    println("Scenario Results:")
    println("-"^70)
    println(rpad("Scenario", 35), rpad("Impact %", 12), rpad("Passed", 8))
    println("-"^70)

    for result in summary.scenario_results
        name = first(result.scenario.display_name, 33)
        impact = "$(round(result.reserve_impact_pct * 100, digits=1))%"
        passed = result.passed ? "YES" : "NO"
        println(rpad(name, 35), rpad(impact, 12), rpad(passed, 8))
    end
    println("-"^70)
    println()

    # Worst case
    if !isnothing(summary.worst_case)
        worst = summary.worst_case
        println("Worst Case Scenario:")
        println("  $(worst.scenario.display_name)")
        println("  Reserve: \$$(round(Int, worst.base_reserve)) -> \$$(round(Int, worst.stressed_reserve))")
        println("  Impact: $(round(worst.reserve_impact_pct * 100, digits=1))%")
        println()
    end

    # Sensitivity summary
    if !isnothing(summary.sensitivity)
        tornado = summary.sensitivity
        println("Top Risk Drivers (by sensitivity):")
        n_show = min(3, length(tornado.parameters))
        for i in 1:n_show
            rng = abs(tornado.high_impacts[i] - tornado.low_impacts[i])
            println("  $i. $(tornado.parameters[i]): \$$(round(Int, rng)) range")
        end
        println()
    end

    # Reverse stress summary
    if !isnothing(summary.reverse_report) && !isnothing(summary.reverse_report.most_vulnerable)
        println("Most Vulnerable Parameter: $(summary.reverse_report.most_vulnerable)")
        println()
    end

    println("="^70)
end

"""
    export_results(summary; format=:dict)

Export stress test results in various formats.

# Arguments
- `summary::StressTestSummary`: Results to export
- `format::Symbol`: Output format (:dict, :array)

# Returns
Formatted results (Dict or Array depending on format)
"""
function export_results(summary::StressTestSummary; format::Symbol = :dict)
    if format == :dict
        return Dict(
            "config" => Dict(
                "base_reserve" => summary.config.base_reserve,
                "minimum_reserve_ratio" => summary.config.minimum_reserve_ratio,
                "rbc_threshold" => summary.config.rbc_threshold
            ),
            "all_passed" => summary.all_passed,
            "n_scenarios" => length(summary.scenario_results),
            "scenario_results" => [
                Dict(
                    "name" => r.scenario.name,
                    "display_name" => r.scenario.display_name,
                    "base_reserve" => r.base_reserve,
                    "stressed_reserve" => r.stressed_reserve,
                    "impact_pct" => r.reserve_impact_pct,
                    "passed" => r.passed
                )
                for r in summary.scenario_results
            ],
            "worst_case" => isnothing(summary.worst_case) ? nothing : Dict(
                "name" => summary.worst_case.scenario.name,
                "impact_pct" => summary.worst_case.reserve_impact_pct
            )
        )
    elseif format == :array
        # Return array of result tuples
        return [
            (
                r.scenario.name,
                r.scenario.display_name,
                r.stressed_reserve,
                r.reserve_impact_pct,
                r.passed
            )
            for r in summary.scenario_results
        ]
    else
        error("Unknown format: $format. Use :dict or :array")
    end
end

# ============================================================================
# Quick Analysis Functions
# ============================================================================

"""
    quick_stress_test(base_reserve; scenarios=:orsa)

Run quick stress test with minimal configuration.

# Arguments
- `base_reserve::Float64`: Starting reserve value
- `scenarios::Symbol`: Scenario set (:orsa, :historical, :all)

# Returns
- `StressTestSummary`: Complete results

# Example
```julia
summary = quick_stress_test(1_000_000.0)
print_stress_summary(summary)
```
"""
function quick_stress_test(
    base_reserve::Float64;
    scenarios::Symbol = :orsa
)::StressTestSummary
    config = StressTestConfig(;
        base_reserve,
        run_sensitivity = true,
        run_reverse = true
    )

    runner = if scenarios == :orsa
        orsa_runner(config)
    elseif scenarios == :historical
        historical_runner(config)
    elseif scenarios == :all
        standard_runner(config)
    else
        error("Unknown scenarios: $scenarios. Use :orsa, :historical, or :all")
    end

    run_stress_test(runner)
end

"""
    compare_scenarios(base_reserve, scenarios)

Compare multiple scenarios side-by-side.

# Returns
Named tuple with comparison data.
"""
function compare_scenarios(
    base_reserve::Float64,
    scenarios::Vector{StressScenario}
)
    results = []

    for scenario in scenarios
        impact = calculate_reserve_impact(scenario, base_reserve)
        push!(results, (
            scenario = scenario,
            stressed = impact.stressed_reserve,
            impact_pct = impact.total_impact,
            components = impact.components
        ))
    end

    # Sort by impact (worst first)
    sort!(results, by=r -> r.impact_pct, rev=true)

    (
        results = results,
        worst = first(results),
        best = last(results),
        avg_impact = mean(r.impact_pct for r in results),
        std_impact = std(r.impact_pct for r in results)
    )
end

"""
    stress_test_grid(base_reserve, equity_range, rate_range)

Run stress tests over a 2D grid of equity and rate shocks.

# Arguments
- `base_reserve::Float64`: Starting reserve
- `equity_range::Vector{Float64}`: Equity shock values
- `rate_range::Vector{Float64}`: Rate shock values (bps)

# Returns
Matrix of (stressed_reserve, impact_pct) tuples
"""
function stress_test_grid(
    base_reserve::Float64,
    equity_range::Vector{Float64},
    rate_range::Vector{Float64}
)
    n_eq = length(equity_range)
    n_rt = length(rate_range)

    results = Matrix{NamedTuple}(undef, n_eq, n_rt)

    for (i, eq) in enumerate(equity_range)
        for (j, rt) in enumerate(rate_range)
            scenario = create_combined_scenario(
                name = "grid",
                display_name = "Grid",
                equity_shock = eq,
                rate_shock = rt / 10000.0
            )
            impact = calculate_reserve_impact(scenario, base_reserve)
            results[i, j] = (
                equity = eq,
                rate = rt,
                stressed = impact.stressed_reserve,
                impact_pct = impact.total_impact
            )
        end
    end

    results
end
