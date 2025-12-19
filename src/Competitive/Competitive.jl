"""
Competitive Analysis Module for AnnuityCore.

Provides market positioning, company/product rankings, and Treasury spread analysis
for annuity products using WINK competitive rate data.

# Core Types
- `WINKProduct`: Single annuity product from competitive data
- `ProductData`: Collection of products (Vector{WINKProduct})
- `PositionResult`: Percentile/rank/quartile positioning
- `DistributionStats`: Market rate distribution statistics
- `CompanyRanking`: Company ranking with best/avg rates
- `ProductRanking`: Product ranking by rate
- `SpreadResult`: Product-to-Treasury spread
- `SpreadDistribution`: Market spread statistics

# Positioning Functions
- `analyze_position(rate, data; filters...)`: Get percentile/rank for a rate
- `get_distribution_stats(data; filters...)`: Market statistics
- `get_percentile_thresholds(data; percentiles)`: Rate at each percentile
- `compare_to_peers(rate, company, data)`: Peer comparison with gaps
- `filter_products(data; filters...)`: Filter product data

# Ranking Functions
- `rank_companies(data; rank_by, top_n)`: Company rankings
- `rank_products(data; top_n)`: Product rankings by rate
- `get_company_rank(company, data)`: Single company lookup
- `market_summary(data)`: Overall market stats
- `rate_leaders_by_duration(data)`: Top products per duration
- `competitive_landscape(data)`: Full landscape analysis

# Spread Functions
- `calculate_spread(rate, treasury_rate, duration)`: Single spread
- `calculate_market_spreads(data, curve)`: All product spreads
- `get_spread_distribution(data, curve)`: Spread statistics
- `analyze_spread_position(spread, data, curve)`: Position by spread
- `spread_by_duration(data, curve)`: Spreads grouped by duration
- `build_treasury_curve(rates)`: Create curve from rates

# Example Usage
```julia
using AnnuityCore

# Create test products
products = [
    WINKProduct("Athene", "Protector 5", 0.055, 5, "MYGA", :current),
    WINKProduct("Global Atlantic", "SecureGain 5", 0.054, 5, "MYGA", :current),
    WINKProduct("Oceanview", "Harbourview 5", 0.052, 5, "MYGA", :current),
]

# Analyze position
position = analyze_position(0.053, products, product_group = "MYGA")
# position.percentile ≈ 33.3% (1 of 3 products ≤ 0.053)
# position.rank = 3 (2 products have higher rates)

# Company rankings
rankings = rank_companies(products, rank_by = BEST_RATE)
# rankings[1].company == "Athene"

# Treasury spread analysis
curve = build_treasury_curve([(5, 0.045)])
dist = get_spread_distribution(products, curve)
# dist.mean_bps ≈ 83 bps (avg spread over Treasury)
```

# Key Algorithms
- Percentile: count-based (count of values ≤ target / total × 100) [T1]
- Rank: 1-based where 1 = highest rate (best)
- Quartile: Q1 ≥ 75%, Q2 ≥ 50%, Q3 ≥ 25%, Q4 < 25%
- Treasury interpolation: linear with flat extrapolation at bounds

See: docs/knowledge/domain/competitive_analysis.md
"""

# Load in dependency order

# 1. Types first (defines structs, constants, utility functions)
include("types.jl")

# 2. Positioning (depends on types)
include("positioning.jl")

# 3. Ranking (depends on types, positioning for filter_products)
include("ranking.jl")

# 4. Spreads (depends on types, positioning for calculate_percentile)
include("spreads.jl")
