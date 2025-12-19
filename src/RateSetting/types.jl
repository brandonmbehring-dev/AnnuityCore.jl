"""
Types for Rate Setting module.

Provides result types for rate recommendations:
- RateRecommendation: Complete rate recommendation with rationale
- MarginAnalysis: Margin breakdown for a given rate
- ConfidenceLevel: Recommendation confidence enum
"""

#=============================================================================
# Confidence Level
=============================================================================#

"""
    ConfidenceLevel

Confidence level of a rate recommendation.

# Values
- `HIGH`: High confidence (large sample, good margin)
- `MEDIUM`: Medium confidence (default)
- `LOW`: Low confidence (small sample, extreme percentile, or negative margin)
"""
@enum ConfidenceLevel HIGH MEDIUM LOW

"""Convert confidence level to string."""
confidence_string(c::ConfidenceLevel) = lowercase(string(c))


#=============================================================================
# Rate Recommendation
=============================================================================#

"""
    RateRecommendation{T<:Real}

Immutable rate recommendation result.

[T1] Rate positioning is relative to duration-matched comparables.
[T2] Typical MYGA spreads over Treasury: 100-200 bps (from WINK data).

# Fields
- `recommended_rate::T`: Recommended rate (decimal)
- `target_percentile::T`: Target competitive percentile achieved (0-100)
- `spread_over_treasury::Union{T, Nothing}`: Spread over matched-duration Treasury (bps)
- `margin_estimate::Union{T, Nothing}`: Estimated margin (bps) after expense costs
- `confidence::ConfidenceLevel`: Confidence level (HIGH, MEDIUM, LOW)
- `rationale::String`: Explanation of recommendation
- `comparable_count::Int`: Number of comparable products in analysis

# Example
```julia
rec = RateRecommendation(
    recommended_rate = 0.048,
    target_percentile = 75.0,
    spread_over_treasury = 80.0,
    margin_estimate = 30.0,
    confidence = HIGH,
    rationale = "Rate 4.800% targets 75th percentile among 50 comparables",
    comparable_count = 50
)
```
"""
struct RateRecommendation{T<:Real}
    recommended_rate::T
    target_percentile::T
    spread_over_treasury::Union{T, Nothing}
    margin_estimate::Union{T, Nothing}
    confidence::ConfidenceLevel
    rationale::String
    comparable_count::Int

    function RateRecommendation(;
        recommended_rate::T,
        target_percentile::T,
        spread_over_treasury::Union{T, Nothing} = nothing,
        margin_estimate::Union{T, Nothing} = nothing,
        confidence::ConfidenceLevel = MEDIUM,
        rationale::String = "",
        comparable_count::Int = 0
    ) where T<:Real
        recommended_rate >= 0 || error("CRITICAL: recommended_rate must be >= 0, got $recommended_rate")
        0 <= target_percentile <= 100 || error("CRITICAL: target_percentile must be 0-100, got $target_percentile")
        comparable_count >= 0 || error("CRITICAL: comparable_count must be >= 0, got $comparable_count")

        new{T}(
            recommended_rate,
            target_percentile,
            spread_over_treasury,
            margin_estimate,
            confidence,
            rationale,
            comparable_count
        )
    end
end


#=============================================================================
# Margin Analysis
=============================================================================#

"""
    MarginAnalysis{T<:Real}

Margin breakdown for a given rate.

# Fields
- `gross_spread::T`: Spread over Treasury (bps)
- `option_cost::T`: Estimated hedging/option cost (bps) - 0 for MYGA
- `expense_load::T`: Operating expense load (bps)
- `net_margin::T`: Net margin after costs (bps)

# Example
```julia
margin = MarginAnalysis(
    gross_spread = 80.0,
    option_cost = 0.0,
    expense_load = 50.0,
    net_margin = 30.0
)
```
"""
struct MarginAnalysis{T<:Real}
    gross_spread::T
    option_cost::T
    expense_load::T
    net_margin::T

    function MarginAnalysis(;
        gross_spread::T,
        option_cost::T,
        expense_load::T,
        net_margin::T
    ) where T<:Real
        new{T}(gross_spread, option_cost, expense_load, net_margin)
    end
end

# Convenience constructor from values
function MarginAnalysis(gross_spread::T, option_cost::T, expense_load::T, net_margin::T) where T<:Real
    MarginAnalysis(
        gross_spread = gross_spread,
        option_cost = option_cost,
        expense_load = expense_load,
        net_margin = net_margin
    )
end


#=============================================================================
# Sensitivity Result
=============================================================================#

"""
    SensitivityPoint{T<:Real}

Single point in sensitivity analysis.

# Fields
- `percentile::T`: Target percentile
- `rate::Union{T, Nothing}`: Recommended rate (nothing if error)
- `spread_bps::Union{T, Nothing}`: Spread over Treasury
- `margin_bps::Union{T, Nothing}`: Estimated margin
- `comparable_count::Int`: Number of comparables
- `error::Union{String, Nothing}`: Error message if calculation failed
"""
struct SensitivityPoint{T<:Real}
    percentile::T
    rate::Union{T, Nothing}
    spread_bps::Union{T, Nothing}
    margin_bps::Union{T, Nothing}
    comparable_count::Int
    error::Union{String, Nothing}

    function SensitivityPoint(;
        percentile::T,
        rate::Union{T, Nothing} = nothing,
        spread_bps::Union{T, Nothing} = nothing,
        margin_bps::Union{T, Nothing} = nothing,
        comparable_count::Int = 0,
        error::Union{String, Nothing} = nothing
    ) where T<:Real
        new{T}(percentile, rate, spread_bps, margin_bps, comparable_count, error)
    end
end


#=============================================================================
# Display Functions
=============================================================================#

"""Print rate recommendation in human-readable format."""
function Base.show(io::IO, rec::RateRecommendation)
    rate_pct = round(rec.recommended_rate * 100, digits=3)
    print(io, "RateRecommendation($(rate_pct)% @ $(round(rec.target_percentile, digits=0))th percentile, ")
    print(io, "confidence=$(confidence_string(rec.confidence)), ")
    print(io, "n=$(rec.comparable_count))")
end

"""Print margin analysis in human-readable format."""
function Base.show(io::IO, m::MarginAnalysis)
    print(io, "MarginAnalysis(gross=$(round(m.gross_spread, digits=1))bps, ")
    print(io, "expenses=$(round(m.expense_load, digits=1))bps, ")
    print(io, "net=$(round(m.net_margin, digits=1))bps)")
end

"""
    print_recommendation(rec::RateRecommendation; io::IO=stdout)

Print detailed rate recommendation.
"""
function print_recommendation(rec::RateRecommendation; io::IO = stdout)
    rate_pct = round(rec.recommended_rate * 100, digits=3)

    println(io, "=" ^ 60)
    println(io, "Rate Recommendation")
    println(io, "=" ^ 60)
    println(io, "Recommended Rate:    $(rate_pct)%")
    println(io, "Target Percentile:   $(round(rec.target_percentile, digits=0))th")
    println(io, "Comparable Products: $(rec.comparable_count)")
    println(io, "Confidence:          $(confidence_string(rec.confidence))")

    if rec.spread_over_treasury !== nothing
        println(io, "Spread over Treasury: $(round(rec.spread_over_treasury, digits=1)) bps")
    end

    if rec.margin_estimate !== nothing
        println(io, "Estimated Margin:    $(round(rec.margin_estimate, digits=1)) bps")
    end

    println(io, "-" ^ 60)
    println(io, "Rationale: $(rec.rationale)")
    println(io, "=" ^ 60)
end

"""
    print_margin_analysis(m::MarginAnalysis; io::IO=stdout)

Print detailed margin analysis.
"""
function print_margin_analysis(m::MarginAnalysis; io::IO = stdout)
    println(io, "Margin Analysis")
    println(io, "-" ^ 30)
    println(io, "Gross Spread:   $(round(m.gross_spread, digits=1)) bps")
    println(io, "Option Cost:    $(round(m.option_cost, digits=1)) bps")
    println(io, "Expense Load:   $(round(m.expense_load, digits=1)) bps")
    println(io, "-" ^ 30)
    println(io, "Net Margin:     $(round(m.net_margin, digits=1)) bps")
end
