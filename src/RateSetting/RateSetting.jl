"""
Rate Setting Module for AnnuityCore.

Provides rate recommendation engine for MYGA products:
- Percentile-based rate recommendations [T1]
- Spread-based rate recommendations [T1]
- Margin analysis and sensitivity [T1]

# Core Types
- `RateRecommendation`: Complete rate recommendation with rationale
- `MarginAnalysis`: Margin breakdown for a given rate
- `RateRecommenderConfig`: Configuration for recommender engine
- `SensitivityPoint`: Single point in sensitivity analysis
- `ConfidenceLevel`: HIGH, MEDIUM, LOW

# Main Functions
- `recommend_rate(duration, percentile, products; treasury_rate)`: Percentile-based recommendation
- `recommend_for_spread(duration, treasury_rate, spread_bps, products)`: Spread-based recommendation
- `analyze_margin(rate, treasury_rate)`: Margin breakdown
- `sensitivity_analysis(duration, products, treasury_rate)`: Multi-percentile analysis

# Example Usage
```julia
using AnnuityCore

# Create sample market data
products = [
    WINKProduct("Company A", "MYGA 5", 0.045, 5, "MYGA", :current),
    WINKProduct("Company B", "MYGA 5", 0.048, 5, "MYGA", :current),
    WINKProduct("Company C", "MYGA 5", 0.050, 5, "MYGA", :current),
    WINKProduct("Company D", "MYGA 5", 0.052, 5, "MYGA", :current),
]

# Recommend rate at 75th percentile
rec = recommend_rate(5, 75.0, products, treasury_rate=0.04)
println("Recommended rate: \$(rec.recommended_rate)")
println("Spread: \$(rec.spread_over_treasury) bps")

# Recommend rate for target spread
rec2 = recommend_for_spread(5, 0.04, 100.0, products)
println("Rate for 100bps spread: \$(rec2.recommended_rate)")

# Analyze margin
margin = analyze_margin(0.048, 0.040)
println("Net margin: \$(margin.net_margin) bps")

# Sensitivity analysis
results = sensitivity_analysis(5, products, 0.04)
print_sensitivity_analysis(results)
```

# Key Data Sources
- [T1] MYGA rate positioning (WINK data)
- [T2] Typical spreads: 100-200 bps over matched-duration Treasury

See: docs/knowledge/domain/competitive_analysis.md
"""

# Load in dependency order
include("types.jl")
include("recommender.jl")
