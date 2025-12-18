"""
Stress Testing Module for AnnuityCore.

Provides comprehensive stress testing framework:
- Standard ORSA scenarios (moderate, severe, extreme)
- Historical crisis scenarios (2008 GFC, 2020 COVID, etc.)
- Sensitivity analysis with tornado diagrams
- Reverse stress testing to find breaking points

# Example
```julia
using AnnuityCore

# Quick stress test with ORSA scenarios
summary = quick_stress_test(1_000_000.0, scenarios=:orsa)
print_stress_summary(summary)

# Historical crisis scenarios
summary = quick_stress_test(1_000_000.0, scenarios=:historical)

# Custom scenario
scenario = StressScenario(
    name = "custom",
    display_name = "Custom Scenario",
    equity_shock = -0.25,
    rate_shock = -0.0100,
    vol_shock = 2.0
)
result = calculate_reserve_impact(scenario, 1_000_000.0)

# Access historical crisis data
println(CRISIS_2008_GFC.equity_shock)  # -0.568
println(CRISIS_2020_COVID.vix_peak)    # 82.69
```
"""

# Load in dependency order
include("types.jl")
include("scenarios.jl")
include("historical.jl")
include("sensitivity.jl")
include("reverse.jl")
include("runner.jl")
