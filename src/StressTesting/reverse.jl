"""
Reverse Stress Testing.

Finds parameter values that cause a target condition to fail:
- Bisection search for breaking points
- Multiple parameter analysis
- Vulnerability reporting
"""

# ============================================================================
# Predefined Targets [T2]
# ============================================================================

"""
Reserve exhaustion target (reserve ratio falls to zero).

[T2] Based on industry practice - find shock that exhausts reserves.
"""
const RESERVE_EXHAUSTION = ReverseStressTarget(
    name = "reserve_exhaustion",
    display_name = "Reserve Exhaustion",
    threshold = 0.0,
    direction = :below,
    metric = :reserve_ratio
)

"""
RBC ratio falls below 200% (regulatory action level).

[T2] Based on NAIC RBC requirements:
- 200% = Company Action Level
- 150% = Regulatory Action Level
- 100% = Authorized Control Level
"""
const RBC_BREACH_200 = ReverseStressTarget(
    name = "rbc_200",
    display_name = "RBC Below 200%",
    threshold = 2.0,
    direction = :below,
    metric = :rbc_ratio
)

"""
RBC ratio falls below 300% (company action consideration).

[T2] Many companies target 300%+ as management threshold.
"""
const RBC_BREACH_300 = ReverseStressTarget(
    name = "rbc_300",
    display_name = "RBC Below 300%",
    threshold = 3.0,
    direction = :below,
    metric = :rbc_ratio
)

"""
Reserve ratio falls below 50% (severe depletion).
"""
const RESERVE_RATIO_50 = ReverseStressTarget(
    name = "reserve_50",
    display_name = "Reserve Below 50%",
    threshold = 0.5,
    direction = :below,
    metric = :reserve_ratio
)

"""
All predefined reverse stress targets.
"""
const PREDEFINED_TARGETS = [
    RESERVE_EXHAUSTION,
    RBC_BREACH_200,
    RBC_BREACH_300,
    RESERVE_RATIO_50
]

# ============================================================================
# Bisection Search
# ============================================================================

"""
    find_breaking_point(target, param, metric_fn; max_iter=50, tol=1e-4)

Find parameter value where target condition triggers using bisection.

# Arguments
- `target::ReverseStressTarget`: Target condition to find
- `param::SensitivityParameter`: Parameter to vary
- `metric_fn::Function`: Function (parameter_value) -> metric_value
- `max_iter::Int`: Maximum bisection iterations
- `tol::Float64`: Convergence tolerance

# Returns
- `ReverseStressResult`: Result including breaking point if found

# Algorithm
Bisection search with O(log((range_high - range_low)/tol)) convergence.

# Example
```julia
target = RBC_BREACH_200
param = DEFAULT_EQUITY_PARAM
metric_fn = shock -> calculate_rbc_ratio(shock)
result = find_breaking_point(target, param, metric_fn)
```
"""
function find_breaking_point(
    target::ReverseStressTarget,
    param::SensitivityParameter,
    metric_fn::Function;
    max_iter::Int = 50,
    tol::Float64 = 1e-4
)::ReverseStressResult
    low = param.range_low
    high = param.range_high

    # Check if breaking point exists in range
    metric_low = metric_fn(low)
    metric_high = metric_fn(high)

    triggers_low = triggers_target(target, metric_low)
    triggers_high = triggers_target(target, metric_high)

    # If both or neither trigger, breaking point not in range
    if triggers_low == triggers_high
        return ReverseStressResult(
            target,
            param.name,
            nothing,  # No breaking point found
            0,
            false
        )
    end

    # Ensure: low = safe (doesn't trigger), high = triggers
    # If it's the opposite, swap them
    if triggers_low && !triggers_high
        low, high = high, low
    end

    # Bisection search
    # Invariant: low doesn't trigger, high triggers
    # We're looking for the boundary between them
    iterations = 0
    for i in 1:max_iter
        iterations = i
        mid = (low + high) / 2.0

        if abs(high - low) < tol
            # Converged - return the boundary point
            return ReverseStressResult(
                target,
                param.name,
                mid,
                iterations,
                true
            )
        end

        metric_mid = metric_fn(mid)
        if triggers_target(target, metric_mid)
            # mid is in trigger zone, narrow from that side
            high = mid
        else
            # mid is safe, narrow from that side
            low = mid
        end
    end

    # Max iterations reached
    mid = (low + high) / 2.0
    ReverseStressResult(
        target,
        param.name,
        mid,
        iterations,
        abs(high - low) < tol * 10  # Relaxed convergence check
    )
end

# ============================================================================
# Reverse Stress Tester
# ============================================================================

"""
    ReverseStressTester

Orchestrates reverse stress testing across multiple parameters.

# Fields
- `target::ReverseStressTarget`: Target condition to find
- `parameters::Vector{SensitivityParameter}`: Parameters to test
- `metric_fn::Function`: Function (scenario) -> metric value
- `scenario_builder::Function`: Function (param_name, value) -> scenario
"""
struct ReverseStressTester
    target::ReverseStressTarget
    parameters::Vector{SensitivityParameter}
    metric_fn::Function
    scenario_builder::Function
end

"""
    run_reverse_test(tester; max_iter=50, tol=1e-4)

Run reverse stress test for all parameters.

# Returns
- `ReverseStressReport`: Complete report with all parameter results
"""
function run_reverse_test(
    tester::ReverseStressTester;
    max_iter::Int = 50,
    tol::Float64 = 1e-4
)::ReverseStressReport
    results = ReverseStressResult[]

    for param in tester.parameters
        # Create metric function that varies only this parameter
        param_metric_fn = function(value)
            scenario = tester.scenario_builder(param.name, value)
            tester.metric_fn(scenario)
        end

        result = find_breaking_point(
            tester.target,
            param,
            param_metric_fn;
            max_iter,
            tol
        )
        push!(results, result)
    end

    # Find most vulnerable parameter (smallest distance to breaking point)
    most_vulnerable = find_most_vulnerable(results, tester.parameters)

    ReverseStressReport(
        tester.target,
        results,
        most_vulnerable
    )
end

"""
Find the most vulnerable parameter (breaking point closest to base value).
"""
function find_most_vulnerable(
    results::Vector{ReverseStressResult},
    params::Vector{SensitivityParameter}
)::Union{String, Nothing}
    min_distance = Inf
    most_vulnerable = nothing

    for (result, param) in zip(results, params)
        isnothing(result.breaking_point) && continue

        # Normalize distance by parameter range
        range = param.range_high - param.range_low
        distance = abs(result.breaking_point - param.base_value) / range

        if distance < min_distance
            min_distance = distance
            most_vulnerable = result.parameter
        end
    end

    most_vulnerable
end

# ============================================================================
# Multi-Target Analysis
# ============================================================================

"""
    run_multi_target_reverse(targets, params, metric_fns, scenario_builder; kwargs...)

Run reverse stress tests for multiple targets.

# Arguments
- `targets::Vector{ReverseStressTarget}`: Targets to test
- `params::Vector{SensitivityParameter}`: Parameters to vary
- `metric_fns::Dict{Symbol, Function}`: Metric extractors keyed by metric symbol
- `scenario_builder::Function`: Scenario constructor

# Returns
- `Dict{String, ReverseStressReport}`: Reports keyed by target name
"""
function run_multi_target_reverse(
    targets::Vector{ReverseStressTarget},
    params::Vector{SensitivityParameter},
    metric_fns::Dict{Symbol, Function},
    scenario_builder::Function;
    max_iter::Int = 50,
    tol::Float64 = 1e-4
)::Dict{String, ReverseStressReport}
    reports = Dict{String, ReverseStressReport}()

    for target in targets
        metric_fn = get(metric_fns, target.metric, nothing)
        isnothing(metric_fn) && continue

        tester = ReverseStressTester(
            target,
            params,
            metric_fn,
            scenario_builder
        )

        reports[target.name] = run_reverse_test(tester; max_iter, tol)
    end

    reports
end

# ============================================================================
# Breaking Point Utilities
# ============================================================================

"""
    breaking_point_distance(result, param)

Calculate distance from base value to breaking point.

Returns (breaking_point - base_value) / range, or Inf if no breaking point.
"""
function breaking_point_distance(
    result::ReverseStressResult,
    param::SensitivityParameter
)::Float64
    isnothing(result.breaking_point) && return Inf

    range = param.range_high - param.range_low
    abs(result.breaking_point - param.base_value) / range
end

"""
    breaking_point_severity(result, param)

Return severity level based on breaking point distance.

# Returns
- `:critical`: < 20% of range from base
- `:warning`: 20-40% of range from base
- `:moderate`: 40-60% of range from base
- `:low`: > 60% of range from base
- `:none`: No breaking point in range
"""
function breaking_point_severity(
    result::ReverseStressResult,
    param::SensitivityParameter
)::Symbol
    isnothing(result.breaking_point) && return :none

    dist = breaking_point_distance(result, param)

    dist < 0.20 && return :critical
    dist < 0.40 && return :warning
    dist < 0.60 && return :moderate
    return :low
end

"""
    format_breaking_point(result, param)

Format breaking point for display.
"""
function format_breaking_point(
    result::ReverseStressResult,
    param::SensitivityParameter
)::String
    isnothing(result.breaking_point) && return "Not found in range"

    bp = result.breaking_point
    unit = param.unit

    if unit == "%"
        return "$(round(bp * 100, digits=1))%"
    elseif unit == "bps"
        return "$(round(bp * 10000, digits=0)) bps"
    elseif unit == "x"
        return "$(round(bp, digits=2))x"
    else
        return "$(round(bp, digits=4))"
    end
end

# ============================================================================
# Report Generation
# ============================================================================

"""
    print_reverse_report(report, params)

Print reverse stress test report.
"""
function print_reverse_report(
    report::ReverseStressReport,
    params::Vector{SensitivityParameter}
)
    println("Reverse Stress Test Report")
    println("Target: $(report.target.display_name)")
    println("Threshold: $(report.target.threshold) ($(report.target.direction))")
    println("="^60)
    println()

    # Create parameter lookup
    param_dict = Dict(p.name => p for p in params)

    for result in report.results
        param = get(param_dict, result.parameter, nothing)
        isnothing(param) && continue

        println("Parameter: $(param.display_name)")
        println("  Breaking Point: $(format_breaking_point(result, param))")
        println("  Converged: $(result.converged)")
        println("  Iterations: $(result.iterations)")

        if !isnothing(result.breaking_point)
            severity = breaking_point_severity(result, param)
            println("  Severity: $(severity)")
        end
        println()
    end

    if !isnothing(report.most_vulnerable)
        println("Most Vulnerable: $(report.most_vulnerable)")
    end
end

"""
    vulnerability_summary(reports, params)

Generate summary of vulnerabilities across all targets.

# Returns
Named tuple with:
- `critical::Vector{String}`: Critical vulnerabilities
- `warning::Vector{String}`: Warning level vulnerabilities
- `all_results::Dict{String, Dict{String, Symbol}}`: target -> param -> severity
"""
function vulnerability_summary(
    reports::Dict{String, ReverseStressReport},
    params::Vector{SensitivityParameter}
)
    param_dict = Dict(p.name => p for p in params)

    critical = String[]
    warning = String[]
    all_results = Dict{String, Dict{String, Symbol}}()

    for (target_name, report) in reports
        all_results[target_name] = Dict{String, Symbol}()

        for result in report.results
            param = get(param_dict, result.parameter, nothing)
            isnothing(param) && continue

            severity = breaking_point_severity(result, param)
            all_results[target_name][result.parameter] = severity

            if severity == :critical
                push!(critical, "$(target_name): $(result.parameter)")
            elseif severity == :warning
                push!(warning, "$(target_name): $(result.parameter)")
            end
        end
    end

    (
        critical = critical,
        warning = warning,
        all_results = all_results
    )
end

# ============================================================================
# Combined Search Strategies
# ============================================================================

"""
    binary_search_scenario(target, base_scenario, scale_fn, metric_fn; max_iter=50, tol=1e-4)

Find scenario intensity where target triggers using binary search on scaling.

# Arguments
- `target::ReverseStressTarget`: Target condition
- `base_scenario::StressScenario`: Base scenario to scale
- `scale_fn::Function`: Function (scenario, scale) -> scaled_scenario
- `metric_fn::Function`: Function (scenario) -> metric value

# Returns
Named tuple with:
- `scale::Float64`: Intensity scale where target triggers
- `scenario::StressScenario`: Scenario at that intensity
- `converged::Bool`: Whether search converged
"""
function binary_search_scenario(
    target::ReverseStressTarget,
    base_scenario::StressScenario,
    scale_fn::Function,
    metric_fn::Function;
    scale_low::Float64 = 0.0,
    scale_high::Float64 = 2.0,
    max_iter::Int = 50,
    tol::Float64 = 1e-4
)
    # Check bounds
    metric_low = metric_fn(scale_fn(base_scenario, scale_low))
    metric_high = metric_fn(scale_fn(base_scenario, scale_high))

    triggers_low = triggers_target(target, metric_low)
    triggers_high = triggers_target(target, metric_high)

    if triggers_low == triggers_high
        return (
            scale = nothing,
            scenario = nothing,
            converged = false,
            message = "Target not triggered in scale range"
        )
    end

    # Orient so low doesn't trigger, high does
    if triggers_low && !triggers_high
        scale_low, scale_high = scale_high, scale_low
    end

    # Bisection
    for i in 1:max_iter
        if abs(scale_high - scale_low) < tol
            mid = (scale_low + scale_high) / 2.0
            return (
                scale = mid,
                scenario = scale_fn(base_scenario, mid),
                converged = true,
                message = "Converged in $i iterations"
            )
        end

        mid = (scale_low + scale_high) / 2.0
        metric_mid = metric_fn(scale_fn(base_scenario, mid))

        if triggers_target(target, metric_mid)
            scale_high = mid
        else
            scale_low = mid
        end
    end

    mid = (scale_low + scale_high) / 2.0
    (
        scale = mid,
        scenario = scale_fn(base_scenario, mid),
        converged = false,
        message = "Max iterations reached"
    )
end

"""
    find_minimum_crisis(target, crises, metric_fn)

Find the mildest historical crisis that triggers target.

# Arguments
- `target::ReverseStressTarget`: Target condition
- `crises::Vector{HistoricalCrisis}`: Crises to test
- `metric_fn::Function`: Function (scenario) -> metric value

# Returns
Named tuple with:
- `crisis::Union{HistoricalCrisis, Nothing}`: Mildest triggering crisis
- `metric::Float64`: Metric value at that crisis
- `all_results::Vector`: Results for all crises tested
"""
function find_minimum_crisis(
    target::ReverseStressTarget,
    crises::Vector{HistoricalCrisis},
    metric_fn::Function
)
    results = []

    for crisis in crises
        scenario = crisis_to_scenario(crisis)
        metric = metric_fn(scenario)
        triggers = triggers_target(target, metric)

        push!(results, (
            crisis = crisis,
            scenario = scenario,
            metric = metric,
            triggers = triggers
        ))
    end

    # Sort by severity (least severe first)
    sort!(results, by=r -> abs(r.crisis.equity_shock))

    # Find mildest triggering crisis
    triggering = filter(r -> r.triggers, results)

    if isempty(triggering)
        return (
            crisis = nothing,
            metric = NaN,
            all_results = results
        )
    end

    mildest = first(triggering)
    (
        crisis = mildest.crisis,
        metric = mildest.metric,
        all_results = results
    )
end
