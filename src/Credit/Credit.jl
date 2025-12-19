"""
Credit Risk Module for AnnuityCore.

Provides credit risk assessment for annuity products:
- AM Best rating to probability of default mapping [T2]
- State guaranty fund coverage limits [T2]
- Credit Valuation Adjustment (CVA) calculations [T1]

# Core Types
- `AMBestRating`: Enum of AM Best FSR ratings (A++ to S)
- `RatingPD`: Probability of default data for a rating
- `CoverageType`: Enum of insurance coverage types
- `GuarantyFundCoverage`: State-specific coverage limits
- `CVAResult`: Comprehensive CVA calculation result

# Rating Functions
- `rating_from_string(str)`: Parse rating string to enum
- `get_annual_pd(rating)`: 1-year probability of default
- `get_cumulative_pd(rating, years)`: Cumulative PD with interpolation
- `get_hazard_rate(rating)`: Continuous hazard rate
- `is_secure(rating)`: Check if rating is investment grade

# Guaranty Fund Functions
- `get_state_coverage(state)`: Get coverage limits for a state
- `calculate_covered_amount(benefit, state, type)`: Amount covered
- `calculate_uncovered_amount(benefit, state, type)`: Amount at risk
- `get_coverage_ratio(benefit, state, type)`: Coverage ratio (0-1)

# CVA Functions
- `calculate_cva(exposure, rating; kwargs...)`: Main CVA calculation
- `calculate_credit_adjusted_price(price, rating; kwargs...)`: Adjusted price
- `calculate_credit_spread(rating; lgd)`: Implied credit spread
- `calculate_exposure_profile(principal, rate, term)`: MYGA exposure profile

# Example Usage
```julia
using AnnuityCore

# Parse rating
rating = rating_from_string("A+")
pd = get_annual_pd(rating)  # 0.0002 (0.02%)

# Check guaranty coverage
covered = calculate_covered_amount(300000.0, "CA", ANNUITY_DEFERRED)
# 200000.0 (80% of 250k limit)

# Calculate CVA
result = calculate_cva(
    250000.0, A,
    term_years = 5,
    state = "TX"
)
println("Net CVA: \$(result.cva_net)")

# Credit-adjusted price
adj_price = calculate_credit_adjusted_price(
    100000.0, A,
    term_years = 5,
    state = "NY"
)
```

# Key Data Sources
- [T2] AM Best Impairment Rate Study (1977-2023)
- [T2] NOLHGA state guaranty fund limits
- [T1] Hull Ch.24 (CVA methodology)

See: docs/knowledge/domain/credit_risk.md
"""

# Load in dependency order

# 1. Types first (defines enums, structs, constants)
include("types.jl")

# 2. Default probability (depends on types)
include("default_prob.jl")

# 3. Guaranty funds (depends on types)
include("guaranty_funds.jl")

# 4. CVA calculations (depends on all above)
include("cva.jl")
