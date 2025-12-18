"""
Data Loaders for AnnuityCore.

Provides actuarial data loading and construction:
- Mortality tables (SOA 2012 IAM, Gompertz, custom)
- Yield curves (Nelson-Siegel, flat, custom)
- Interpolation utilities

# Core Types
- `MortalityTable`: Mortality rates by age
- `YieldCurve`: Zero-coupon yield curve
- `NelsonSiegelParams`: NS model parameters
- `Gender`: MALE, FEMALE, UNISEX
- `InterpolationMethod`: LINEAR, LOG_LINEAR, CUBIC

# Mortality Functions
- `soa_2012_iam(; gender)`: Load SOA 2012 IAM table
- `get_qx(table, age)`: Mortality rate
- `get_px(table, age)`: Survival rate
- `npx(table, age, n)`: N-year survival
- `life_expectancy(table, age)`: Curtate life expectancy
- `annuity_factor(table, age, r)`: Life annuity factor

# Yield Curve Functions
- `from_nelson_siegel(β0, β1, β2, τ)`: Create NS curve
- `flat_curve(rate)`: Create flat curve
- `from_points(maturities, rates)`: Create from points
- `get_rate(curve, t)`: Interpolated zero rate
- `discount_factor(curve, t)`: Discount factor
- `forward_rate(curve, t1, t2)`: Forward rate

# Example Usage
```julia
using AnnuityCore

# Mortality
table = soa_2012_iam()
qx_65 = get_qx(table, 65)  # 0.0168
ex_65 = life_expectancy(table, 65)  # ~20.1

# Yield curve
curve = from_nelson_siegel(0.04, -0.02, 0.01, 2.0)
r_5y = get_rate(curve, 5.0)  # ~0.039
df_5y = discount_factor(curve, 5.0)  # ~0.82

# Combined: Life annuity pricing
factor = annuity_factor(table, 65, 0.04)
pv = 10_000 * factor  # PV of 10k/year life annuity
```

Validators: actuarialmath, MortalityTables.jl, QuantLib, PyCurve
See: docs/CROSS_VALIDATION_MATRIX.md
"""

# Load in dependency order

# 1. Types first (defines structs and enums)
include("types.jl")

# 2. Data (embedded tables, depends on types)
include("mortality_data.jl")

# 3. Interpolation utilities (used by both mortality and yield_curve)
include("interpolation.jl")

# 4. Mortality functions (depends on types, data, interpolation)
include("mortality.jl")

# 5. Yield curve functions (depends on types, interpolation)
include("yield_curve.jl")
