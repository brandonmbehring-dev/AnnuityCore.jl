"""
Type Definitions for Data Loaders.

Core types for mortality tables and yield curves:
- MortalityTable: SOA tables and custom mortality
- YieldCurve: Interest rate curves with interpolation
- NelsonSiegelParams: NS model parameters
"""

# ============================================================================
# Mortality Types
# ============================================================================

"""
Gender specification for mortality tables.
"""
@enum Gender MALE FEMALE UNISEX

"""
    MortalityTable

Immutable mortality table representation.

[T1] qx = probability of death between age x and x+1

# Fields
- `table_name::String`: Table identifier (e.g., "SOA 2012 IAM")
- `min_age::Int`: Minimum age in table
- `max_age::Int`: Maximum age (omega - 1)
- `qx::Vector{Float64}`: Mortality rates by age
- `gender::Gender`: Gender specification

# Example
```julia
table = MortalityTable(
    table_name = "Custom",
    min_age = 0,
    max_age = 120,
    qx = [0.001, 0.001, ...],
    gender = MALE
)
qx_65 = get_qx(table, 65)
```
"""
struct MortalityTable
    table_name::String
    min_age::Int
    max_age::Int
    qx::Vector{Float64}
    gender::Gender

    function MortalityTable(;
        table_name::String,
        min_age::Int,
        max_age::Int,
        qx::Vector{Float64},
        gender::Gender
    )
        # Validate length
        expected_len = max_age - min_age + 1
        length(qx) == expected_len || error(
            "qx array length ($(length(qx))) must equal max_age - min_age + 1 ($expected_len)"
        )

        # Validate bounds
        all(0.0 .<= qx .<= 1.0) || error("All qx values must be in [0, 1]")

        # Validate age range
        min_age >= 0 || error("min_age must be non-negative")
        max_age >= min_age || error("max_age must be >= min_age")

        new(table_name, min_age, max_age, qx, gender)
    end
end

# ============================================================================
# Yield Curve Types
# ============================================================================

"""
Interpolation method for yield curves.
"""
@enum InterpolationMethod LINEAR LOG_LINEAR CUBIC

"""
    YieldCurve

Immutable yield curve representation.

[T1] Zero-coupon yield curve with interpolation.

# Fields
- `maturities::Vector{Float64}`: Maturities in years
- `rates::Vector{Float64}`: Zero rates (continuous compounding)
- `as_of_date::String`: Curve date (YYYY-MM-DD)
- `curve_type::String`: Curve construction method
- `interpolation::InterpolationMethod`: Interpolation method

# Example
```julia
curve = YieldCurve(
    maturities = [0.25, 0.5, 1.0, 2.0, 5.0, 10.0],
    rates = [0.04, 0.042, 0.045, 0.048, 0.05, 0.052],
    as_of_date = "2024-01-15",
    curve_type = "Treasury"
)
r = get_rate(curve, 3.0)  # Interpolated 3-year rate
```
"""
struct YieldCurve
    maturities::Vector{Float64}
    rates::Vector{Float64}
    as_of_date::String
    curve_type::String
    interpolation::InterpolationMethod

    function YieldCurve(;
        maturities::Vector{Float64},
        rates::Vector{Float64},
        as_of_date::String = "",
        curve_type::String = "Custom",
        interpolation::InterpolationMethod = LINEAR
    )
        # Validate lengths match
        length(maturities) == length(rates) || error(
            "Maturities ($(length(maturities))) and rates ($(length(rates))) must have same length"
        )

        # At least one point
        length(maturities) > 0 || error("Curve must have at least one point")

        # Strictly increasing maturities
        issorted(maturities) && allunique(maturities) || error(
            "Maturities must be strictly increasing"
        )

        # Positive maturities
        all(m -> m > 0, maturities) || error("Maturities must be positive")

        new(maturities, rates, as_of_date, curve_type, interpolation)
    end
end

"""
    NelsonSiegelParams

Immutable Nelson-Siegel model parameters.

[T1] y(t) = β₀ + β₁·(1-e^(-t/τ))/(t/τ) + β₂·((1-e^(-t/τ))/(t/τ) - e^(-t/τ))

# Fields
- `beta0::Float64`: Long-term level (asymptotic rate)
- `beta1::Float64`: Short-term component (slope)
- `beta2::Float64`: Medium-term component (curvature)
- `tau::Float64`: Decay parameter (λ)

# Interpretation
- Short rate (t→0): β₀ + β₁
- Long rate (t→∞): β₀
- Hump location: approximately τ

# Example
```julia
params = NelsonSiegelParams(
    beta0 = 0.04,   # 4% long-term
    beta1 = -0.02,  # Upward sloping
    beta2 = 0.01,   # Some curvature
    tau = 2.0       # Medium-term decay
)
```
"""
struct NelsonSiegelParams
    beta0::Float64
    beta1::Float64
    beta2::Float64
    tau::Float64

    function NelsonSiegelParams(;
        beta0::Float64,
        beta1::Float64,
        beta2::Float64,
        tau::Float64
    )
        tau > 0 || error("tau must be positive, got $tau")
        new(beta0, beta1, beta2, tau)
    end
end

# Convenience constructor with positional args
function NelsonSiegelParams(beta0::Float64, beta1::Float64, beta2::Float64, tau::Float64)
    NelsonSiegelParams(; beta0, beta1, beta2, tau)
end

# ============================================================================
# Result Types
# ============================================================================

"""
    CurveShiftResult

Result of shifting a yield curve.
"""
struct CurveShiftResult
    original_curve::YieldCurve
    shifted_curve::YieldCurve
    shift_type::String
    shift_amount::Float64
end

"""
    MortalityComparison

Result of comparing mortality tables.
"""
struct MortalityComparison
    ages::Vector{Int}
    tables::Dict{String, MortalityTable}
    life_expectancies::Dict{String, Vector{Float64}}
end
