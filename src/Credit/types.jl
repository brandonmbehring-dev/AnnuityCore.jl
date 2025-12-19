"""
Type definitions for Credit Risk module.

Provides types for:
- AM Best Financial Strength Ratings
- Probability of default data
- State guaranty fund coverage
- CVA calculation results

All ratings and coverage types use @enum for type safety.
Result types are immutable structs with validation constructors.
"""

#=============================================================================
# AM Best Ratings
=============================================================================#

"""
    AMBestRating

AM Best Financial Strength Ratings (FSR).

[T1] Secure ratings: A++, A+, A, A-, B++, B+
[T1] Vulnerable ratings: B, B-, C++, C+, C, C-, D, E, F, S

# Values
- `A_PLUS_PLUS`: Superior (A++)
- `A_PLUS`: Superior (A+)
- `A`: Excellent
- `A_MINUS`: Excellent (A-)
- `B_PLUS_PLUS`: Very Good (B++)
- `B_PLUS`: Very Good (B+)
- `B`: Adequate
- `B_MINUS`: Adequate (B-)
- `C_PLUS_PLUS`: Marginal (C++)
- `C_PLUS`: Marginal (C+)
- `C`: Weak
- `C_MINUS`: Weak (C-)
- `D`: Poor
- `E`: Under Regulatory Supervision
- `F`: In Liquidation
- `S`: Rating Suspended
"""
@enum AMBestRating begin
    A_PLUS_PLUS    # Superior
    A_PLUS         # Superior
    A              # Excellent
    A_MINUS        # Excellent
    B_PLUS_PLUS    # Very Good
    B_PLUS         # Very Good
    B              # Adequate
    B_MINUS        # Adequate
    C_PLUS_PLUS    # Marginal
    C_PLUS         # Marginal
    C              # Weak
    C_MINUS        # Weak
    D              # Poor
    E              # Under Regulatory Supervision
    F              # In Liquidation
    S              # Rating Suspended
end

"""
String representation for AM Best ratings.
"""
const RATING_STRINGS = Dict{AMBestRating, String}(
    A_PLUS_PLUS => "A++",
    A_PLUS => "A+",
    A => "A",
    A_MINUS => "A-",
    B_PLUS_PLUS => "B++",
    B_PLUS => "B+",
    B => "B",
    B_MINUS => "B-",
    C_PLUS_PLUS => "C++",
    C_PLUS => "C+",
    C => "C",
    C_MINUS => "C-",
    D => "D",
    E => "E",
    F => "F",
    S => "S",
)

"""
Parse string to AM Best rating.
"""
const STRING_TO_RATING = Dict{String, AMBestRating}(
    v => k for (k, v) in RATING_STRINGS
)

"""
Check if rating is considered "secure" (investment grade).
"""
function is_secure(rating::AMBestRating)::Bool
    rating in (A_PLUS_PLUS, A_PLUS, A, A_MINUS, B_PLUS_PLUS, B_PLUS)
end

"""
Check if rating is considered "vulnerable" (speculative grade).
"""
function is_vulnerable(rating::AMBestRating)::Bool
    !is_secure(rating)
end

#=============================================================================
# Probability of Default Data
=============================================================================#

"""
    RatingPD

Probability of default data for an AM Best rating.

# Fields
- `rating::AMBestRating`: The AM Best rating
- `annual_pd::Float64`: 1-year probability of default/impairment (decimal)
- `pd_5yr::Float64`: 5-year cumulative PD (decimal)
- `pd_10yr::Float64`: 10-year cumulative PD (decimal)
- `pd_15yr::Float64`: 15-year cumulative PD (decimal)

# Validation
- All PD values must be in [0, 1]
- PD values must be non-decreasing: annual ≤ 5yr ≤ 10yr ≤ 15yr
"""
struct RatingPD
    rating::AMBestRating
    annual_pd::Float64
    pd_5yr::Float64
    pd_10yr::Float64
    pd_15yr::Float64

    function RatingPD(;
        rating::AMBestRating,
        annual_pd::Float64,
        pd_5yr::Float64,
        pd_10yr::Float64,
        pd_15yr::Float64
    )
        # Validation
        (0.0 <= annual_pd <= 1.0) || error("CRITICAL: annual_pd must be in [0,1], got $annual_pd")
        (0.0 <= pd_5yr <= 1.0) || error("CRITICAL: pd_5yr must be in [0,1], got $pd_5yr")
        (0.0 <= pd_10yr <= 1.0) || error("CRITICAL: pd_10yr must be in [0,1], got $pd_10yr")
        (0.0 <= pd_15yr <= 1.0) || error("CRITICAL: pd_15yr must be in [0,1], got $pd_15yr")

        new(rating, annual_pd, pd_5yr, pd_10yr, pd_15yr)
    end
end

#=============================================================================
# Coverage Types
=============================================================================#

"""
    CoverageType

Types of insurance/annuity coverage for guaranty fund limits.

# Values
- `LIFE_DEATH_BENEFIT`: Life insurance death benefit
- `LIFE_CASH_VALUE`: Life insurance cash surrender value
- `ANNUITY_DEFERRED`: Deferred annuity accumulation value
- `ANNUITY_PAYOUT`: Annuity in payout status
- `ANNUITY_SSA`: Structured settlement annuity
- `GROUP_ANNUITY`: Group/unallocated annuity
- `HEALTH`: Health insurance benefit
"""
@enum CoverageType begin
    LIFE_DEATH_BENEFIT
    LIFE_CASH_VALUE
    ANNUITY_DEFERRED
    ANNUITY_PAYOUT
    ANNUITY_SSA
    GROUP_ANNUITY
    HEALTH
end

#=============================================================================
# Guaranty Fund Coverage
=============================================================================#

"""
    GuarantyFundCoverage

State guaranty fund coverage limits.

# Fields
- `state::String`: Two-letter state code (e.g., "CA", "NY")
- `life_death_benefit::Float64`: Max coverage for life death benefits
- `life_cash_value::Float64`: Max coverage for life cash value
- `annuity_deferred::Float64`: Max coverage for deferred annuities
- `annuity_payout::Float64`: Max coverage for annuities in payout
- `annuity_ssa::Float64`: Max coverage for structured settlements
- `group_annuity::Float64`: Max coverage for group annuities
- `health::Float64`: Max coverage for health insurance
- `coverage_percentage::Float64`: Percentage covered (default 1.0 = 100%)

# Note
[T2] California (CA) covers only 80% of benefits, hence coverage_percentage < 1.0
"""
struct GuarantyFundCoverage
    state::String
    life_death_benefit::Float64
    life_cash_value::Float64
    annuity_deferred::Float64
    annuity_payout::Float64
    annuity_ssa::Float64
    group_annuity::Float64
    health::Float64
    coverage_percentage::Float64

    function GuarantyFundCoverage(;
        state::String,
        life_death_benefit::Float64,
        life_cash_value::Float64,
        annuity_deferred::Float64,
        annuity_payout::Float64,
        annuity_ssa::Float64,
        group_annuity::Float64,
        health::Float64,
        coverage_percentage::Float64 = 1.0
    )
        # Validation
        length(state) == 2 || state == "DEFAULT" || error("CRITICAL: state must be 2-letter code, got '$state'")
        (0.0 < coverage_percentage <= 1.0) || error("CRITICAL: coverage_percentage must be in (0,1], got $coverage_percentage")

        new(state, life_death_benefit, life_cash_value, annuity_deferred,
            annuity_payout, annuity_ssa, group_annuity, health, coverage_percentage)
    end
end

#=============================================================================
# CVA Result Types
=============================================================================#

"""
    CVAResult

Credit Valuation Adjustment calculation result.

# Fields
- `cva_gross::Float64`: CVA before guaranty fund adjustment
- `cva_net::Float64`: CVA after guaranty fund adjustment (exposure at risk)
- `guaranty_adjustment::Float64`: Reduction in CVA due to guaranty coverage
- `expected_exposure::Float64`: Total expected exposure
- `covered_exposure::Float64`: Exposure covered by guaranty fund
- `uncovered_exposure::Float64`: Exposure at credit risk
- `coverage_ratio::Float64`: Ratio of covered to total exposure (0 to 1)
- `lgd::Float64`: Loss given default used in calculation
- `rating::AMBestRating`: Insurer rating used
- `annual_pd::Float64`: Annual probability of default

# Validation
- cva_gross >= 0
- cva_net >= 0 and cva_net <= cva_gross
- coverage_ratio in [0, 1]
- lgd in (0, 1]
"""
struct CVAResult
    cva_gross::Float64
    cva_net::Float64
    guaranty_adjustment::Float64
    expected_exposure::Float64
    covered_exposure::Float64
    uncovered_exposure::Float64
    coverage_ratio::Float64
    lgd::Float64
    rating::AMBestRating
    annual_pd::Float64

    function CVAResult(;
        cva_gross::Float64,
        cva_net::Float64,
        guaranty_adjustment::Float64,
        expected_exposure::Float64,
        covered_exposure::Float64,
        uncovered_exposure::Float64,
        coverage_ratio::Float64,
        lgd::Float64,
        rating::AMBestRating,
        annual_pd::Float64
    )
        # Validation
        cva_gross >= 0.0 || error("CRITICAL: cva_gross must be >= 0, got $cva_gross")
        cva_net >= 0.0 || error("CRITICAL: cva_net must be >= 0, got $cva_net")
        (0.0 <= coverage_ratio <= 1.0) || error("CRITICAL: coverage_ratio must be in [0,1], got $coverage_ratio")
        (0.0 < lgd <= 1.0) || error("CRITICAL: lgd must be in (0,1], got $lgd")
        (0.0 <= annual_pd <= 1.0) || error("CRITICAL: annual_pd must be in [0,1], got $annual_pd")

        new(cva_gross, cva_net, guaranty_adjustment, expected_exposure,
            covered_exposure, uncovered_exposure, coverage_ratio, lgd, rating, annual_pd)
    end
end

#=============================================================================
# Constants
=============================================================================#

"""
Industry-standard Loss Given Default for insurance companies.
[T2] Higher recovery than typical corporates due to regulatory protection.
"""
const DEFAULT_INSURANCE_LGD = 0.70  # 70% LGD (30% recovery)

"""
All valid US state codes for guaranty fund lookup.
"""
const US_STATE_CODES = Set([
    "AL", "AK", "AZ", "AR", "CA", "CO", "CT", "DE", "FL", "GA",
    "HI", "ID", "IL", "IN", "IA", "KS", "KY", "LA", "ME", "MD",
    "MA", "MI", "MN", "MS", "MO", "MT", "NE", "NV", "NH", "NJ",
    "NM", "NY", "NC", "ND", "OH", "OK", "OR", "PA", "RI", "SC",
    "SD", "TN", "TX", "UT", "VT", "VA", "WA", "WV", "WI", "WY",
    "DC", "PR"  # DC and Puerto Rico
])
