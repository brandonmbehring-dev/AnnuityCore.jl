"""
Stress Testing Type Definitions.

Core types for stress testing framework:
- Scenario types and classifications
- Market shock representations
- Historical crisis data structures
- Sensitivity analysis results
- Reverse stress testing targets
"""

# ============================================================================
# Enums
# ============================================================================

"""
Classification of stress scenarios by source/methodology.
"""
@enum ScenarioType begin
    HISTORICAL      # Based on actual historical crisis
    ORSA           # Own Risk and Solvency Assessment standard
    REGULATORY     # Required by regulators (VM-21, etc.)
    CUSTOM         # User-defined scenario
end

"""
Recovery pattern types for historical crises.

[T2] Classifications based on empirical observation:
- V_SHAPED: Quick rebound (e.g., 2020 COVID)
- U_SHAPED: Extended bottom (e.g., 2008 GFC)
- L_SHAPED: No/minimal recovery (e.g., Japan 1990s)
- W_SHAPED: Double-dip pattern (e.g., 2011 Euro debt)
"""
@enum RecoveryType begin
    V_SHAPED
    U_SHAPED
    L_SHAPED
    W_SHAPED
end

# ============================================================================
# Stress Scenario
# ============================================================================

"""
    StressScenario

Market shock representation for stress testing.

# Fields
- `name::String`: Internal identifier (e.g., "2008_gfc")
- `display_name::String`: Human-readable name (e.g., "2008 Global Financial Crisis")
- `equity_shock::Float64`: Equity return shock (e.g., -0.30 = -30%)
- `rate_shock::Float64`: Interest rate shock in decimal (e.g., -0.0100 = -100 bps)
- `vol_shock::Float64`: Volatility multiplier (e.g., 2.0 = 2x baseline vol)
- `lapse_multiplier::Float64`: Lapse rate multiplier (e.g., 1.5 = 50% increase)
- `withdrawal_multiplier::Float64`: Withdrawal rate multiplier
- `scenario_type::ScenarioType`: Classification of scenario source

# Example
```julia
scenario = StressScenario(
    name = "moderate_adverse",
    display_name = "Moderate Adverse",
    equity_shock = -0.15,
    rate_shock = -0.0050,
    vol_shock = 1.3,
    scenario_type = ORSA
)
```
"""
struct StressScenario
    name::String
    display_name::String
    equity_shock::Float64
    rate_shock::Float64
    vol_shock::Float64
    lapse_multiplier::Float64
    withdrawal_multiplier::Float64
    scenario_type::ScenarioType

    function StressScenario(;
        name::String,
        display_name::String,
        equity_shock::Float64,
        rate_shock::Float64,
        vol_shock::Float64 = 1.0,
        lapse_multiplier::Float64 = 1.0,
        withdrawal_multiplier::Float64 = 1.0,
        scenario_type::ScenarioType = CUSTOM
    )
        # Validate bounds
        equity_shock > 1.0 && error("equity_shock $equity_shock > 100% gain is unrealistic")
        equity_shock < -1.0 && error("equity_shock $equity_shock < -100% impossible")
        vol_shock < 0.0 && error("vol_shock must be non-negative")
        lapse_multiplier < 0.0 && error("lapse_multiplier must be non-negative")
        withdrawal_multiplier < 0.0 && error("withdrawal_multiplier must be non-negative")

        new(name, display_name, equity_shock, rate_shock, vol_shock,
            lapse_multiplier, withdrawal_multiplier, scenario_type)
    end
end

# Convenience constructor with positional args
function StressScenario(
    name::String,
    display_name::String,
    equity_shock::Float64,
    rate_shock::Float64;
    vol_shock::Float64 = 1.0,
    lapse_multiplier::Float64 = 1.0,
    withdrawal_multiplier::Float64 = 1.0,
    scenario_type::ScenarioType = CUSTOM
)
    StressScenario(;
        name, display_name, equity_shock, rate_shock,
        vol_shock, lapse_multiplier, withdrawal_multiplier, scenario_type
    )
end

# ============================================================================
# Historical Crisis Types
# ============================================================================

"""
    CrisisProfile

Monthly evolution during a historical crisis.

# Fields
- `month::Float64`: Month index from crisis start (0 = onset)
- `equity_cumulative::Float64`: Cumulative equity return from start
- `rate_level::Float64`: Interest rate level at this point
- `vix_level::Float64`: VIX level at this point
"""
struct CrisisProfile
    month::Float64
    equity_cumulative::Float64
    rate_level::Float64
    vix_level::Float64
end

"""
    HistoricalCrisis

Complete historical crisis data with monthly profile.

[T2] Calibrated to actual market data from major crises.

# Fields
- `name::String`: Crisis identifier
- `display_name::String`: Human-readable name
- `start_date::String`: Crisis start date (YYYY-MM)
- `equity_shock::Float64`: Peak-to-trough equity decline
- `rate_shock::Float64`: Rate change in decimal
- `vix_peak::Float64`: Maximum VIX during crisis
- `duration_months::Int`: Months to reach trough
- `recovery_months::Int`: Months to recover to pre-crisis level
- `recovery_type::RecoveryType`: Pattern of recovery
- `profile::Vector{CrisisProfile}`: Monthly evolution

# Example
```julia
crisis = HistoricalCrisis(
    name = "2008_gfc",
    display_name = "2008 Global Financial Crisis",
    start_date = "2007-10",
    equity_shock = -0.568,
    rate_shock = -0.0254,
    vix_peak = 80.9,
    duration_months = 17,
    recovery_months = 54,
    recovery_type = U_SHAPED,
    profile = [...]
)
```
"""
struct HistoricalCrisis
    name::String
    display_name::String
    start_date::String
    equity_shock::Float64
    rate_shock::Float64
    vix_peak::Float64
    duration_months::Int
    recovery_months::Int
    recovery_type::RecoveryType
    profile::Vector{CrisisProfile}

    function HistoricalCrisis(;
        name::String,
        display_name::String,
        start_date::String,
        equity_shock::Float64,
        rate_shock::Float64,
        vix_peak::Float64,
        duration_months::Int,
        recovery_months::Int,
        recovery_type::RecoveryType,
        profile::Vector{CrisisProfile} = CrisisProfile[]
    )
        # Validate
        equity_shock > 0.0 && @warn "equity_shock positive ($equity_shock) - crises usually negative"
        duration_months < 0 && error("duration_months must be non-negative")
        recovery_months < 0 && error("recovery_months must be non-negative")
        vix_peak < 0.0 && error("vix_peak must be non-negative")

        new(name, display_name, start_date, equity_shock, rate_shock, vix_peak,
            duration_months, recovery_months, recovery_type, profile)
    end
end

"""
Convert historical crisis to stress scenario (peak impact).
"""
function crisis_to_scenario(crisis::HistoricalCrisis)::StressScenario
    # Estimate vol shock from VIX (baseline ~20)
    vol_shock = crisis.vix_peak / 20.0

    StressScenario(
        name = crisis.name,
        display_name = crisis.display_name,
        equity_shock = crisis.equity_shock,
        rate_shock = crisis.rate_shock,
        vol_shock = vol_shock,
        scenario_type = HISTORICAL
    )
end

# ============================================================================
# Sensitivity Analysis Types
# ============================================================================

"""
    SensitivityParameter

Parameter specification for sensitivity analysis.

# Fields
- `name::String`: Parameter identifier (e.g., "equity_shock")
- `display_name::String`: Human-readable name
- `base_value::Float64`: Starting value
- `range_low::Float64`: Lower bound for sweep
- `range_high::Float64`: Upper bound for sweep
- `unit::String`: Display unit (e.g., "%", "bps")
"""
struct SensitivityParameter
    name::String
    display_name::String
    base_value::Float64
    range_low::Float64
    range_high::Float64
    unit::String

    function SensitivityParameter(;
        name::String,
        display_name::String,
        base_value::Float64,
        range_low::Float64,
        range_high::Float64,
        unit::String = ""
    )
        range_low > range_high && error("range_low ($range_low) > range_high ($range_high)")
        new(name, display_name, base_value, range_low, range_high, unit)
    end
end

"""
    SensitivityResult

Result of single parameter sensitivity analysis.

# Fields
- `parameter::SensitivityParameter`: The varied parameter
- `values::Vector{Float64}`: Parameter values tested
- `impacts::Vector{Float64}`: Resulting metric impacts
- `base_metric::Float64`: Metric at base value
"""
struct SensitivityResult
    parameter::SensitivityParameter
    values::Vector{Float64}
    impacts::Vector{Float64}
    base_metric::Float64
end

"""
    TornadoData

Data for tornado diagram visualization.

# Fields
- `parameters::Vector{String}`: Parameter names
- `low_impacts::Vector{Float64}`: Impact at low parameter value
- `high_impacts::Vector{Float64}`: Impact at high parameter value
- `base_value::Float64`: Base metric value
"""
struct TornadoData
    parameters::Vector{String}
    low_impacts::Vector{Float64}
    high_impacts::Vector{Float64}
    base_value::Float64

    function TornadoData(;
        parameters::Vector{String},
        low_impacts::Vector{Float64},
        high_impacts::Vector{Float64},
        base_value::Float64
    )
        n = length(parameters)
        length(low_impacts) != n && error("low_impacts length mismatch")
        length(high_impacts) != n && error("high_impacts length mismatch")
        new(parameters, low_impacts, high_impacts, base_value)
    end
end

"""
Total impact range for a parameter (for sorting tornado bars).
"""
impact_range(t::TornadoData, i::Int) = abs(t.high_impacts[i] - t.low_impacts[i])

# ============================================================================
# Reverse Stress Testing Types
# ============================================================================

"""
    ReverseStressTarget

Target condition for reverse stress testing.

# Fields
- `name::String`: Target identifier
- `display_name::String`: Human-readable name
- `threshold::Float64`: Threshold value that defines "failure"
- `direction::Symbol`: :below or :above (which side triggers failure)
- `metric::Symbol`: Metric being tested (e.g., :reserve_ratio, :rbc_ratio)
"""
struct ReverseStressTarget
    name::String
    display_name::String
    threshold::Float64
    direction::Symbol
    metric::Symbol

    function ReverseStressTarget(;
        name::String,
        display_name::String,
        threshold::Float64,
        direction::Symbol = :below,
        metric::Symbol = :reserve_ratio
    )
        direction in (:below, :above) || error("direction must be :below or :above")
        new(name, display_name, threshold, direction, metric)
    end
end

"""
Check if a metric value triggers the target condition.
"""
function triggers_target(target::ReverseStressTarget, value::Float64)::Bool
    if target.direction == :below
        return value < target.threshold
    else
        return value > target.threshold
    end
end

"""
    ReverseStressResult

Result of reverse stress test for a single parameter.

# Fields
- `target::ReverseStressTarget`: The target being tested
- `parameter::String`: Parameter that was varied
- `breaking_point::Union{Float64, Nothing}`: Value where target triggers (nothing if not found)
- `iterations::Int`: Number of bisection iterations
- `converged::Bool`: Whether search converged within tolerance
"""
struct ReverseStressResult
    target::ReverseStressTarget
    parameter::String
    breaking_point::Union{Float64, Nothing}
    iterations::Int
    converged::Bool
end

"""
    ReverseStressReport

Complete reverse stress test report.

# Fields
- `target::ReverseStressTarget`: Target tested
- `results::Vector{ReverseStressResult}`: Results for each parameter
- `most_vulnerable::Union{String, Nothing}`: Parameter with smallest breaking point distance
"""
struct ReverseStressReport
    target::ReverseStressTarget
    results::Vector{ReverseStressResult}
    most_vulnerable::Union{String, Nothing}
end

# ============================================================================
# Stress Test Result Types
# ============================================================================

"""
    StressTestResult

Result of running a stress scenario.

# Fields
- `scenario::StressScenario`: The scenario that was run
- `base_reserve::Float64`: Reserve before stress
- `stressed_reserve::Float64`: Reserve after stress
- `reserve_impact::Float64`: Absolute change
- `reserve_impact_pct::Float64`: Percentage change
- `rbc_ratio::Union{Float64, Nothing}`: Risk-based capital ratio if calculated
- `passed::Bool`: Whether result meets minimum thresholds
"""
struct StressTestResult
    scenario::StressScenario
    base_reserve::Float64
    stressed_reserve::Float64
    reserve_impact::Float64
    reserve_impact_pct::Float64
    rbc_ratio::Union{Float64, Nothing}
    passed::Bool
end

"""
    StressTestConfig

Configuration for stress test runner.

# Fields
- `base_reserve::Float64`: Starting reserve level
- `minimum_reserve_ratio::Float64`: Minimum acceptable reserve ratio
- `rbc_threshold::Float64`: RBC ratio warning threshold (default 200%)
- `run_sensitivity::Bool`: Whether to run sensitivity analysis
- `run_reverse::Bool`: Whether to run reverse stress tests
- `n_sensitivity_points::Int`: Points in sensitivity sweep
"""
struct StressTestConfig
    base_reserve::Float64
    minimum_reserve_ratio::Float64
    rbc_threshold::Float64
    run_sensitivity::Bool
    run_reverse::Bool
    n_sensitivity_points::Int

    function StressTestConfig(;
        base_reserve::Float64,
        minimum_reserve_ratio::Float64 = 0.0,
        rbc_threshold::Float64 = 2.0,
        run_sensitivity::Bool = true,
        run_reverse::Bool = true,
        n_sensitivity_points::Int = 21
    )
        base_reserve <= 0.0 && error("base_reserve must be positive")
        n_sensitivity_points < 3 && error("n_sensitivity_points must be >= 3")
        new(base_reserve, minimum_reserve_ratio, rbc_threshold,
            run_sensitivity, run_reverse, n_sensitivity_points)
    end
end

"""
    StressTestSummary

Summary of complete stress test suite.

# Fields
- `config::StressTestConfig`: Configuration used
- `scenario_results::Vector{StressTestResult}`: Results for each scenario
- `sensitivity::Union{TornadoData, Nothing}`: Sensitivity analysis if run
- `reverse_report::Union{ReverseStressReport, Nothing}`: Reverse stress if run
- `worst_case::Union{StressTestResult, Nothing}`: Scenario with largest impact
- `all_passed::Bool`: Whether all scenarios passed
"""
struct StressTestSummary
    config::StressTestConfig
    scenario_results::Vector{StressTestResult}
    sensitivity::Union{TornadoData, Nothing}
    reverse_report::Union{ReverseStressReport, Nothing}
    worst_case::Union{StressTestResult, Nothing}
    all_passed::Bool
end
