"""
Rate recommendation engine for MYGA products.

Provides rate recommendations based on:
- Target competitive percentile
- Treasury spread targets
- Margin/profitability constraints

Uses WINKProduct data from the Competitive module.

[T1] Rate positioning is relative to duration-matched comparables.
[T2] Typical MYGA spreads over Treasury: 100-200 bps (from WINK data).

See: CONSTITUTION.md Section 5
See: docs/knowledge/domain/competitive_analysis.md
"""

using Statistics: quantile, mean

#=============================================================================
# Rate Recommender Configuration
=============================================================================#

"""
    RateRecommenderConfig{T<:Real}

Configuration for rate recommendation engine.

# Fields
- `default_expense_load::T`: Default expense load in decimal (default 0.0050 = 50 bps)
- `duration_tolerance::Int`: Years tolerance for duration matching (default 1)
- `min_comparables::Int`: Minimum comparable products required (default 5)

# Example
```julia
config = RateRecommenderConfig(
    default_expense_load = 0.0050,
    duration_tolerance = 1,
    min_comparables = 10
)
```
"""
struct RateRecommenderConfig{T<:Real}
    default_expense_load::T
    duration_tolerance::Int
    min_comparables::Int

    function RateRecommenderConfig(;
        default_expense_load::T = 0.0050,
        duration_tolerance::Int = 1,
        min_comparables::Int = 5
    ) where T<:Real
        default_expense_load >= 0 || error("CRITICAL: default_expense_load must be >= 0")
        duration_tolerance >= 0 || error("CRITICAL: duration_tolerance must be >= 0")
        min_comparables >= 1 || error("CRITICAL: min_comparables must be >= 1")
        new{T}(default_expense_load, duration_tolerance, min_comparables)
    end
end

# Default configuration
const DEFAULT_RECOMMENDER_CONFIG = RateRecommenderConfig(
    default_expense_load = 0.0050,
    duration_tolerance = 1,
    min_comparables = 5
)


#=============================================================================
# Core Recommendation Functions
=============================================================================#

"""
    recommend_rate(guarantee_duration, target_percentile, market_data; kwargs...) -> RateRecommendation

Recommend rate to achieve target competitive percentile.

[T1] Rate is calculated as the percentile of the distribution of comparable rates.

# Arguments
- `guarantee_duration::Int`: Product duration in years
- `target_percentile::Real`: Target percentile (0-100, higher = more competitive)
- `market_data::Vector{WINKProduct}`: Comparable MYGA products

# Keyword Arguments
- `treasury_rate::Union{Real, Nothing}=nothing`: Treasury yield for matching duration (decimal)
- `min_margin_bps::Real=50.0`: Minimum acceptable margin in basis points
- `config::RateRecommenderConfig=DEFAULT_RECOMMENDER_CONFIG`: Recommender configuration

# Returns
- `RateRecommendation`: Complete recommendation with rationale

# Example
```julia
products = [
    WINKProduct("Company A", "MYGA 5", 0.045, 5, "MYGA", :current),
    WINKProduct("Company B", "MYGA 5", 0.048, 5, "MYGA", :current),
    WINKProduct("Company C", "MYGA 5", 0.050, 5, "MYGA", :current),
]

rec = recommend_rate(5, 75.0, products, treasury_rate=0.04)
println(rec.recommended_rate)  # ~0.0485
```
"""
function recommend_rate(
    guarantee_duration::Int,
    target_percentile::Real,
    market_data::Vector{WINKProduct};
    treasury_rate::Union{Real, Nothing} = nothing,
    min_margin_bps::Real = 50.0,
    config::RateRecommenderConfig = DEFAULT_RECOMMENDER_CONFIG
)::RateRecommendation
    # Validate inputs
    0 <= target_percentile <= 100 || error("CRITICAL: target_percentile must be 0-100, got $target_percentile")
    guarantee_duration > 0 || error("CRITICAL: guarantee_duration must be > 0, got $guarantee_duration")

    # Filter to comparable products
    comparables = get_comparables(market_data, guarantee_duration, config)

    if isempty(comparables)
        error(
            "CRITICAL: No comparable MYGA products found for " *
            "duration $guarantee_duration ± $(config.duration_tolerance) years. " *
            "Check market_data filters."
        )
    end

    rates = [p.rate for p in comparables]

    if isempty(rates)
        error("CRITICAL: All rate values are missing in comparable products.")
    end

    # Calculate rate at target percentile
    # Note: Julia's quantile uses fraction (0-1), Python uses 0-100
    recommended_rate = Float64(quantile(rates, target_percentile / 100.0))

    # Calculate spread over Treasury
    spread_bps = nothing
    if treasury_rate !== nothing
        spread_bps = (recommended_rate - Float64(treasury_rate)) * 10000
    end

    # Estimate margin (MYGA has no option cost)
    margin_bps = nothing
    if spread_bps !== nothing
        expense_bps = config.default_expense_load * 10000
        margin_bps = spread_bps - expense_bps
    end

    # Determine confidence
    confidence = assess_confidence(length(rates), target_percentile, margin_bps)

    # Build rationale
    rationale = build_rationale(
        recommended_rate = recommended_rate,
        target_percentile = Float64(target_percentile),
        spread_bps = spread_bps,
        margin_bps = margin_bps,
        min_margin_bps = Float64(min_margin_bps),
        comparable_count = length(rates)
    )

    RateRecommendation(
        recommended_rate = recommended_rate,
        target_percentile = Float64(target_percentile),
        spread_over_treasury = spread_bps,
        margin_estimate = margin_bps,
        confidence = confidence,
        rationale = rationale,
        comparable_count = length(rates)
    )
end


"""
    recommend_for_spread(guarantee_duration, treasury_rate, target_spread_bps, market_data; kwargs...) -> RateRecommendation

Recommend rate to achieve target spread over Treasury.

# Arguments
- `guarantee_duration::Int`: Product duration in years
- `treasury_rate::Real`: Treasury yield for matching duration (decimal)
- `target_spread_bps::Real`: Target spread in basis points
- `market_data::Vector{WINKProduct}`: Comparable MYGA products

# Keyword Arguments
- `config::RateRecommenderConfig=DEFAULT_RECOMMENDER_CONFIG`: Recommender configuration

# Returns
- `RateRecommendation`: Complete recommendation

# Example
```julia
rec = recommend_for_spread(5, 0.04, 100.0, products)
# Recommends rate = 0.04 + 0.01 = 0.05 (5%)
```
"""
function recommend_for_spread(
    guarantee_duration::Int,
    treasury_rate::Real,
    target_spread_bps::Real,
    market_data::Vector{WINKProduct};
    config::RateRecommenderConfig = DEFAULT_RECOMMENDER_CONFIG
)::RateRecommendation
    treasury_rate >= 0 || error("CRITICAL: treasury_rate must be >= 0, got $treasury_rate")

    # Calculate rate from spread target
    recommended_rate = Float64(treasury_rate) + (Float64(target_spread_bps) / 10000)

    # Get comparables to determine percentile
    comparables = get_comparables(market_data, guarantee_duration, config)

    if isempty(comparables)
        error("CRITICAL: No comparable products for duration $guarantee_duration")
    end

    rates = [p.rate for p in comparables]

    # Calculate percentile for this rate
    percentile = calculate_rate_percentile(recommended_rate, rates)

    # Estimate margin
    expense_bps = config.default_expense_load * 10000
    margin_bps = Float64(target_spread_bps) - expense_bps

    confidence = assess_confidence(length(rates), percentile, margin_bps)

    rationale = "Rate $(round(recommended_rate * 100, digits=3))% achieves $(round(target_spread_bps, digits=0))bps spread " *
                "over $(guarantee_duration)-year Treasury ($(round(Float64(treasury_rate) * 100, digits=3))%). " *
                "Positions at $(round(percentile, digits=0))th percentile among $(length(rates)) comparables."

    RateRecommendation(
        recommended_rate = recommended_rate,
        target_percentile = percentile,
        spread_over_treasury = Float64(target_spread_bps),
        margin_estimate = margin_bps,
        confidence = confidence,
        rationale = rationale,
        comparable_count = length(rates)
    )
end


"""
    analyze_margin(rate, treasury_rate; expense_load=nothing, config=DEFAULT_RECOMMENDER_CONFIG) -> MarginAnalysis

Analyze margin breakdown for a given rate.

# Arguments
- `rate::Real`: Product rate (decimal)
- `treasury_rate::Real`: Treasury yield (decimal)

# Keyword Arguments
- `expense_load::Union{Real, Nothing}=nothing`: Expense load (decimal). Defaults to config.default_expense_load.
- `config::RateRecommenderConfig=DEFAULT_RECOMMENDER_CONFIG`: Recommender configuration

# Returns
- `MarginAnalysis`: Breakdown of gross spread, costs, net margin

# Example
```julia
margin = analyze_margin(0.048, 0.040)
# gross_spread = 80 bps
# expense_load = 50 bps
# net_margin = 30 bps
```
"""
function analyze_margin(
    rate::Real,
    treasury_rate::Real;
    expense_load::Union{Real, Nothing} = nothing,
    config::RateRecommenderConfig = DEFAULT_RECOMMENDER_CONFIG
)::MarginAnalysis
    expense = expense_load === nothing ? config.default_expense_load : Float64(expense_load)

    gross_spread_bps = (Float64(rate) - Float64(treasury_rate)) * 10000
    option_cost_bps = 0.0  # MYGA has no option cost
    expense_bps = expense * 10000
    net_margin_bps = gross_spread_bps - option_cost_bps - expense_bps

    MarginAnalysis(
        gross_spread = gross_spread_bps,
        option_cost = option_cost_bps,
        expense_load = expense_bps,
        net_margin = net_margin_bps
    )
end


"""
    sensitivity_analysis(guarantee_duration, market_data, treasury_rate; kwargs...) -> Vector{SensitivityPoint}

Perform sensitivity analysis across percentile targets.

# Arguments
- `guarantee_duration::Int`: Product duration
- `market_data::Vector{WINKProduct}`: Comparable products
- `treasury_rate::Real`: Treasury yield

# Keyword Arguments
- `percentile_range::Vector{<:Real}=[25.0, 50.0, 75.0, 90.0]`: Percentiles to analyze
- `config::RateRecommenderConfig=DEFAULT_RECOMMENDER_CONFIG`: Recommender configuration

# Returns
- `Vector{SensitivityPoint}`: Analysis at each percentile

# Example
```julia
results = sensitivity_analysis(5, products, 0.04)
for pt in results
    println("\$(pt.percentile)th: \$(pt.rate) → \$(pt.margin_bps) bps margin")
end
```
"""
function sensitivity_analysis(
    guarantee_duration::Int,
    market_data::Vector{WINKProduct},
    treasury_rate::Real;
    percentile_range::Vector{<:Real} = [25.0, 50.0, 75.0, 90.0],
    config::RateRecommenderConfig = DEFAULT_RECOMMENDER_CONFIG
)::Vector{SensitivityPoint{Float64}}
    results = SensitivityPoint{Float64}[]

    for pct in percentile_range
        try
            rec = recommend_rate(
                guarantee_duration,
                Float64(pct),
                market_data,
                treasury_rate = treasury_rate,
                config = config
            )
            push!(results, SensitivityPoint(
                percentile = Float64(pct),
                rate = rec.recommended_rate,
                spread_bps = rec.spread_over_treasury,
                margin_bps = rec.margin_estimate,
                comparable_count = rec.comparable_count,
                error = nothing
            ))
        catch e
            push!(results, SensitivityPoint(
                percentile = Float64(pct),
                rate = nothing,
                spread_bps = nothing,
                margin_bps = nothing,
                comparable_count = 0,
                error = string(e)
            ))
        end
    end

    results
end


#=============================================================================
# Helper Functions
=============================================================================#

"""
    get_comparables(market_data, guarantee_duration, config) -> Vector{WINKProduct}

Filter market data to comparable products.

# Arguments
- `market_data::Vector{WINKProduct}`: Full market data
- `guarantee_duration::Int`: Target duration
- `config::RateRecommenderConfig`: Configuration with tolerance

# Returns
- `Vector{WINKProduct}`: Filtered to comparable products
"""
function get_comparables(
    market_data::Vector{WINKProduct},
    guarantee_duration::Int,
    config::RateRecommenderConfig
)::Vector{WINKProduct}
    filter(market_data) do p
        # Filter to current MYGA products
        p.status == :current &&
        p.product_group == "MYGA" &&
        # Duration matching within tolerance
        abs(p.duration - guarantee_duration) <= config.duration_tolerance
    end
end


"""
    calculate_rate_percentile(value, distribution) -> Float64

Calculate percentile of value within distribution.

Uses count-based percentile (percentage of values <= value).
"""
function calculate_rate_percentile(value::Real, distribution::Vector{<:Real})::Float64
    isempty(distribution) && error("CRITICAL: Cannot calculate percentile with empty distribution")
    count_le = count(x -> x <= value, distribution)
    Float64((count_le / length(distribution)) * 100)
end


"""
    assess_confidence(sample_size, percentile, margin_bps) -> ConfidenceLevel

Assess confidence level of recommendation.

# Arguments
- `sample_size::Int`: Number of comparable products
- `percentile::Real`: Target percentile
- `margin_bps::Union{Real, Nothing}`: Estimated margin

# Returns
- `ConfidenceLevel`: HIGH, MEDIUM, or LOW
"""
function assess_confidence(
    sample_size::Int,
    percentile::Real,
    margin_bps::Union{Real, Nothing}
)::ConfidenceLevel
    # Start with medium confidence
    score = 2

    # Sample size factors
    if sample_size >= 50
        score += 1
    elseif sample_size < 10
        score -= 1
    end

    # Extreme percentiles are less reliable
    if percentile > 95 || percentile < 5
        score -= 1
    end

    # Margin factors
    if margin_bps !== nothing
        if margin_bps < 0
            score -= 1
        elseif margin_bps > 100
            score += 1
        end
    end

    # Convert to confidence level
    if score >= 3
        return HIGH
    elseif score <= 1
        return LOW
    else
        return MEDIUM
    end
end


"""
    build_rationale(; kwargs...) -> String

Build human-readable rationale for recommendation.
"""
function build_rationale(;
    recommended_rate::Float64,
    target_percentile::Float64,
    spread_bps::Union{Float64, Nothing},
    margin_bps::Union{Float64, Nothing},
    min_margin_bps::Float64,
    comparable_count::Int
)::String
    rate_pct = round(recommended_rate * 100, digits=3)
    pct_str = round(target_percentile, digits=0)

    parts = [
        "Recommended rate: $(rate_pct)% (targets $(pct_str)th percentile among $comparable_count comparables)"
    ]

    if spread_bps !== nothing
        push!(parts, "Spread over Treasury: $(round(spread_bps, digits=0))bps")
    end

    if margin_bps !== nothing
        if margin_bps >= min_margin_bps
            push!(parts, "Estimated margin: $(round(margin_bps, digits=0))bps (meets $(round(min_margin_bps, digits=0))bps target)")
        else
            push!(parts, "WARNING: Estimated margin $(round(margin_bps, digits=0))bps below $(round(min_margin_bps, digits=0))bps target")
        end
    end

    join(parts, ". ")
end


#=============================================================================
# Convenience Functions
=============================================================================#

"""
    quick_rate_recommendation(duration, target_pct, rates; treasury_rate=nothing) -> RateRecommendation

Quick rate recommendation from a vector of rates (no WINKProduct required).

Useful for testing and simple scenarios.

# Arguments
- `duration::Int`: Product duration
- `target_pct::Real`: Target percentile (0-100)
- `rates::Vector{<:Real}`: Vector of comparable rates

# Keyword Arguments
- `treasury_rate::Union{Real, Nothing}=nothing`: Treasury yield

# Returns
- `RateRecommendation`

# Example
```julia
rec = quick_rate_recommendation(5, 75.0, [0.045, 0.048, 0.050, 0.052])
println(rec.recommended_rate)  # ~0.05
```
"""
function quick_rate_recommendation(
    duration::Int,
    target_pct::Real,
    rates::Vector{<:Real};
    treasury_rate::Union{Real, Nothing} = nothing
)::RateRecommendation
    # Create synthetic WINKProducts
    products = [
        WINKProduct("Synthetic", "Product $i", Float64(r), duration, "MYGA", :current)
        for (i, r) in enumerate(rates)
    ]

    recommend_rate(duration, Float64(target_pct), products, treasury_rate = treasury_rate)
end


"""
    rate_grid(treasury_rate, spread_range_bps; step_bps=10) -> Vector{Tuple{Float64, Float64}}

Generate a grid of (rate, spread) pairs for analysis.

# Arguments
- `treasury_rate::Real`: Base Treasury rate
- `spread_range_bps::Tuple{Real, Real}`: (min_spread, max_spread) in bps

# Keyword Arguments
- `step_bps::Real=10`: Step size in bps

# Returns
- `Vector{Tuple{Float64, Float64}}`: Vector of (rate, spread_bps) tuples

# Example
```julia
grid = rate_grid(0.04, (50, 150), step_bps=25)
# Returns: [(0.045, 50), (0.0475, 75), (0.05, 100), ...]
```
"""
function rate_grid(
    treasury_rate::Real,
    spread_range_bps::Tuple{Real, Real};
    step_bps::Real = 10
)::Vector{Tuple{Float64, Float64}}
    min_spread, max_spread = spread_range_bps
    spreads = min_spread:step_bps:max_spread

    [(Float64(treasury_rate) + s / 10000, Float64(s)) for s in spreads]
end


"""
    compare_recommendations(recs::Vector{RateRecommendation}; io::IO=stdout)

Compare multiple rate recommendations side by side.
"""
function compare_recommendations(recs::Vector{<:RateRecommendation}; io::IO = stdout)
    isempty(recs) && return

    println(io, "=" ^ 80)
    println(io, "Rate Recommendation Comparison")
    println(io, "=" ^ 80)

    # Header
    println(io, rpad("Percentile", 12), rpad("Rate", 10), rpad("Spread", 12),
            rpad("Margin", 12), rpad("Confidence", 12), "Comparables")
    println(io, "-" ^ 80)

    for rec in recs
        rate_pct = "$(round(rec.recommended_rate * 100, digits=3))%"
        spread = rec.spread_over_treasury !== nothing ? "$(round(rec.spread_over_treasury, digits=0)) bps" : "N/A"
        margin = rec.margin_estimate !== nothing ? "$(round(rec.margin_estimate, digits=0)) bps" : "N/A"

        println(io,
            rpad("$(Int(round(rec.target_percentile)))th", 12),
            rpad(rate_pct, 10),
            rpad(spread, 12),
            rpad(margin, 12),
            rpad(confidence_string(rec.confidence), 12),
            rec.comparable_count
        )
    end

    println(io, "=" ^ 80)
end


"""
    print_sensitivity_analysis(results::Vector{SensitivityPoint}; io::IO=stdout)

Print sensitivity analysis results.
"""
function print_sensitivity_analysis(results::Vector{<:SensitivityPoint}; io::IO = stdout)
    println(io, "Sensitivity Analysis")
    println(io, "-" ^ 60)
    println(io, rpad("Percentile", 12), rpad("Rate", 10), rpad("Spread", 12),
            rpad("Margin", 12), "Status")
    println(io, "-" ^ 60)

    for pt in results
        pct_str = "$(Int(round(pt.percentile)))th"

        if pt.error !== nothing
            println(io, rpad(pct_str, 12), "ERROR: $(pt.error)")
        else
            rate_str = pt.rate !== nothing ? "$(round(pt.rate * 100, digits=3))%" : "N/A"
            spread_str = pt.spread_bps !== nothing ? "$(round(pt.spread_bps, digits=0)) bps" : "N/A"
            margin_str = pt.margin_bps !== nothing ? "$(round(pt.margin_bps, digits=0)) bps" : "N/A"
            status = pt.margin_bps !== nothing && pt.margin_bps > 0 ? "✓" : "⚠"

            println(io,
                rpad(pct_str, 12),
                rpad(rate_str, 10),
                rpad(spread_str, 12),
                rpad(margin_str, 12),
                status
            )
        end
    end

    println(io, "-" ^ 60)
end
