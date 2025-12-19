"""
Treasury spread analysis for competitive rates.

Provides functions for:
- Spread calculation (product rate - treasury rate)
- Market spread distribution
- Spread-based positioning
- Treasury curve interpolation

Key concepts:
- Spread in basis points (bps) = (product_rate - treasury_rate) * 10000
- Negative spreads are allowed (product rate < treasury)
- Treasury interpolation uses linear interpolation with flat extrapolation
"""

using Dates
using Statistics: mean, median, std, quantile

#=============================================================================
# Treasury Curve Types
=============================================================================#

"""
Treasury curve represented as Dict{Int, Float64} mapping duration (years) to rate.
"""
const TreasuryCurve = Dict{Int, Float64}

#=============================================================================
# Treasury Interpolation
=============================================================================#

"""
    interpolate_treasury(duration::Int, curve::TreasuryCurve) -> Float64

Get treasury rate for a given duration, interpolating if necessary.

# Algorithm [T1]
1. If exact duration exists, return it
2. If duration < min, return min rate (flat extrapolation)
3. If duration > max, return max rate (flat extrapolation)
4. Otherwise, linear interpolation between adjacent points

# Arguments
- `duration`: Term in years
- `curve`: Treasury curve (duration => rate)

# Returns
- Interpolated treasury rate

# Example
```julia
curve = Dict(1 => 0.04, 2 => 0.042, 5 => 0.045)
interpolate_treasury(3, curve)  # Linear interpolation between 2 and 5
interpolate_treasury(10, curve) # 0.045 (flat extrapolation from 5)
```
"""
function interpolate_treasury(duration::Int, curve::TreasuryCurve)::Float64
    isempty(curve) && error("CRITICAL: Treasury curve is empty")
    duration < 1 && error("CRITICAL: duration must be >= 1, got $duration")

    # Exact match
    haskey(curve, duration) && return curve[duration]

    durations = sort(collect(keys(curve)))

    # Flat extrapolation at bounds
    duration < first(durations) && return curve[first(durations)]
    duration > last(durations) && return curve[last(durations)]

    # Linear interpolation
    lower = maximum(d for d in durations if d < duration)
    upper = minimum(d for d in durations if d > duration)

    weight = (duration - lower) / (upper - lower)
    curve[lower] + weight * (curve[upper] - curve[lower])
end

"""
    build_treasury_curve(rates::Dict{String, Float64}) -> TreasuryCurve

Build treasury curve from FRED series rates.

# Arguments
- `rates`: Dict mapping FRED series (e.g., "DGS5") to rate

# Returns
- TreasuryCurve (duration => rate)

# Example
```julia
fred_rates = Dict("DGS1" => 0.04, "DGS5" => 0.045, "DGS10" => 0.048)
curve = build_treasury_curve(fred_rates)
# Dict(1 => 0.04, 5 => 0.045, 10 => 0.048)
```
"""
function build_treasury_curve(rates::Dict{String, Float64})::TreasuryCurve
    result = TreasuryCurve()
    for (duration, series) in TREASURY_SERIES
        if haskey(rates, series)
            result[duration] = rates[series]
        end
    end
    result
end

"""
    build_treasury_curve(rates::Vector{Tuple{Int, Float64}}) -> TreasuryCurve

Build treasury curve from (duration, rate) tuples.
"""
function build_treasury_curve(rates::Vector{Tuple{Int, Float64}})::TreasuryCurve
    TreasuryCurve(d => r for (d, r) in rates)
end

"""
    build_treasury_curve(durations::Vector{Int}, rates::Vector{Float64}) -> TreasuryCurve

Build treasury curve from parallel duration and rate vectors.
"""
function build_treasury_curve(durations::Vector{Int}, rates::Vector{Float64})::TreasuryCurve
    length(durations) == length(rates) || error("CRITICAL: durations and rates must have same length")
    TreasuryCurve(zip(durations, rates))
end

#=============================================================================
# Spread Calculation
=============================================================================#

"""
    calculate_spread(product_rate::Float64, treasury_rate::Float64, duration::Int; as_of_date::Date=today()) -> SpreadResult

Calculate spread between product rate and treasury rate.

# Arguments
- `product_rate`: Product credited rate (decimal)
- `treasury_rate`: Treasury rate for matching duration (decimal)
- `duration`: Term in years
- `as_of_date`: Date of treasury rate (default: today)

# Returns
- SpreadResult with spread in bps and percentage

# Example
```julia
result = calculate_spread(0.055, 0.045, 5)
println("Spread: \$(result.spread_bps) bps")  # 100 bps
```
"""
function calculate_spread(
    product_rate::Float64,
    treasury_rate::Float64,
    duration::Int;
    as_of_date::Date = today()
)::SpreadResult
    spread = product_rate - treasury_rate
    spread_bps = spread * 10000.0

    SpreadResult(
        product_rate = product_rate,
        treasury_rate = treasury_rate,
        spread_bps = spread_bps,
        spread_pct = spread * 100.0,
        duration = duration,
        as_of_date = as_of_date
    )
end

"""
    calculate_product_spread(product::WINKProduct, curve::TreasuryCurve; as_of_date::Date=today()) -> SpreadResult

Calculate spread for a single product.

# Arguments
- `product`: Product to analyze
- `curve`: Treasury curve for rate lookup
- `as_of_date`: Date of treasury rates

# Returns
- SpreadResult
"""
function calculate_product_spread(
    product::WINKProduct,
    curve::TreasuryCurve;
    as_of_date::Date = today()
)::SpreadResult
    treasury_rate = interpolate_treasury(product.duration, curve)
    calculate_spread(product.rate, treasury_rate, product.duration, as_of_date = as_of_date)
end

#=============================================================================
# Market Spread Analysis
=============================================================================#

"""
    ProductSpread

Spread result with product identification.
"""
struct ProductSpread
    company::String
    product::String
    spread::SpreadResult
end

"""
    calculate_market_spreads(data::ProductData, curve::TreasuryCurve; as_of_date::Date=today(), kwargs...) -> Vector{ProductSpread}

Calculate spreads for all products in the market.

# Arguments
- `data`: Product data
- `curve`: Treasury curve
- `as_of_date`: Date of treasury rates

# Keyword Arguments
Same as `filter_products` for filtering.

# Returns
- Vector of ProductSpread

# Example
```julia
spreads = calculate_market_spreads(market_data, treasury_curve)
for ps in spreads
    println("\$(ps.company): \$(ps.spread.spread_bps) bps over Treasury")
end
```
"""
function calculate_market_spreads(
    data::ProductData,
    curve::TreasuryCurve;
    as_of_date::Date = today(),
    product_group::Union{String, Nothing} = nothing,
    duration::Union{Int, Nothing} = nothing,
    duration_tolerance::Int = 1,
    status::Symbol = :current
)::Vector{ProductSpread}
    filtered = filter_products(
        data,
        product_group = product_group,
        duration = duration,
        duration_tolerance = duration_tolerance,
        status = status
    )

    isempty(filtered) && error("CRITICAL: No products match filter criteria")

    [
        ProductSpread(
            p.company,
            p.product,
            calculate_product_spread(p, curve, as_of_date = as_of_date)
        )
        for p in filtered
    ]
end

"""
    get_spread_distribution(data::ProductData, curve::TreasuryCurve; kwargs...) -> SpreadDistribution

Get statistical distribution of spreads in the market.

# Arguments
- `data`: Product data
- `curve`: Treasury curve

# Keyword Arguments
Same as `filter_products` for filtering.

# Returns
- SpreadDistribution with min, max, mean, median, std, quartiles

# Example
```julia
dist = get_spread_distribution(market_data, treasury_curve, product_group = "MYGA")
println("Average spread: \$(dist.mean_bps) bps")
```
"""
function get_spread_distribution(
    data::ProductData,
    curve::TreasuryCurve;
    product_group::Union{String, Nothing} = nothing,
    duration::Union{Int, Nothing} = nothing,
    duration_tolerance::Int = 1,
    status::Symbol = :current
)::SpreadDistribution
    spreads = calculate_market_spreads(
        data,
        curve,
        product_group = product_group,
        duration = duration,
        duration_tolerance = duration_tolerance,
        status = status
    )

    spread_bps = [ps.spread.spread_bps for ps in spreads]
    SpreadDistribution(spread_bps)
end

"""
    analyze_spread_position(spread_bps::Float64, data::ProductData, curve::TreasuryCurve; kwargs...) -> PositionResult

Analyze competitive position based on spread.

# Arguments
- `spread_bps`: Spread in basis points to analyze
- `data`: Product data
- `curve`: Treasury curve

# Keyword Arguments
Same as `filter_products` for filtering.

# Returns
- PositionResult based on spread ranking

# Example
```julia
position = analyze_spread_position(100.0, market_data, treasury_curve)
println("Your spread is in the \$(position.position_label)")
```
"""
function analyze_spread_position(
    spread_bps::Float64,
    data::ProductData,
    curve::TreasuryCurve;
    product_group::Union{String, Nothing} = nothing,
    duration::Union{Int, Nothing} = nothing,
    duration_tolerance::Int = 1,
    status::Symbol = :current
)::PositionResult
    market_spreads = calculate_market_spreads(
        data,
        curve,
        product_group = product_group,
        duration = duration,
        duration_tolerance = duration_tolerance,
        status = status
    )

    all_spreads_bps = [ps.spread.spread_bps for ps in market_spreads]

    # Calculate position metrics (higher spread = better position)
    percentile = calculate_percentile(spread_bps, all_spreads_bps)
    rank = calculate_rank(spread_bps, all_spreads_bps)
    quartile = calculate_quartile(percentile)
    label = get_position_label(percentile)

    PositionResult(
        rate = spread_bps / 10000.0,  # Store spread as "rate" for consistency
        percentile = percentile,
        rank = rank,
        total_products = length(market_spreads),
        quartile = quartile,
        position_label = label
    )
end

"""
    DurationSpreadSummary

Spread summary for a single duration.
"""
struct DurationSpreadSummary
    duration::Int
    product_count::Int
    treasury_rate::Float64
    distribution::SpreadDistribution
end

"""
    spread_by_duration(data::ProductData, curve::TreasuryCurve; kwargs...) -> Dict{Int, DurationSpreadSummary}

Analyze spreads grouped by duration.

# Arguments
- `data`: Product data
- `curve`: Treasury curve

# Keyword Arguments
Same as `filter_products` for filtering (except duration).

# Returns
- Dict mapping duration => DurationSpreadSummary

# Example
```julia
by_duration = spread_by_duration(market_data, treasury_curve, product_group = "MYGA")
for (dur, summary) in sort(collect(by_duration))
    println("\$(dur)-year: avg spread = \$(summary.distribution.mean_bps) bps")
end
```
"""
function spread_by_duration(
    data::ProductData,
    curve::TreasuryCurve;
    product_group::Union{String, Nothing} = nothing,
    status::Symbol = :current
)::Dict{Int, DurationSpreadSummary}
    filtered = filter_products(
        data,
        product_group = product_group,
        status = status
    )

    isempty(filtered) && error("CRITICAL: No products match filter criteria")

    # Group by duration
    by_duration = group_by_duration(filtered)

    result = Dict{Int, DurationSpreadSummary}()
    for (dur, products) in by_duration
        treasury_rate = interpolate_treasury(dur, curve)
        spread_bps = [(p.rate - treasury_rate) * 10000.0 for p in products]

        result[dur] = DurationSpreadSummary(
            dur,
            length(products),
            treasury_rate,
            SpreadDistribution(spread_bps)
        )
    end

    result
end

#=============================================================================
# Spread Comparison Functions
=============================================================================#

"""
    SpreadComparison

Comparison of a product's spread to market.
"""
struct SpreadComparison
    product_spread::SpreadResult
    market_position::PositionResult
    gap_to_best::Float64      # bps
    gap_to_median::Float64    # bps
end

"""
    compare_spread_to_market(product::WINKProduct, data::ProductData, curve::TreasuryCurve; kwargs...) -> SpreadComparison

Compare a product's spread to the market.

# Arguments
- `product`: Product to analyze
- `data`: Market product data
- `curve`: Treasury curve

# Keyword Arguments
Same as `filter_products` for filtering.

# Example
```julia
comparison = compare_spread_to_market(my_product, market_data, treasury_curve)
println("Gap to best: \$(comparison.gap_to_best) bps")
```
"""
function compare_spread_to_market(
    product::WINKProduct,
    data::ProductData,
    curve::TreasuryCurve;
    product_group::Union{String, Nothing} = nothing,
    duration::Union{Int, Nothing} = nothing,
    duration_tolerance::Int = 1,
    status::Symbol = :current
)::SpreadComparison
    # Calculate product spread
    product_spread = calculate_product_spread(product, curve)

    # Get market spreads (excluding this product's company)
    market_spreads = calculate_market_spreads(
        data,
        curve,
        product_group = isnothing(product_group) ? product.product_group : product_group,
        duration = isnothing(duration) ? product.duration : duration,
        duration_tolerance = duration_tolerance,
        status = status
    )

    # Exclude own company from comparison
    peer_spreads = filter(ps -> lowercase(ps.company) != lowercase(product.company), market_spreads)
    isempty(peer_spreads) && error("CRITICAL: No peer products for comparison")

    all_spreads_bps = [ps.spread.spread_bps for ps in peer_spreads]

    # Calculate position
    position = analyze_spread_position(
        product_spread.spread_bps,
        filter(p -> lowercase(p.company) != lowercase(product.company), data),
        curve,
        product_group = isnothing(product_group) ? product.product_group : product_group,
        duration = isnothing(duration) ? product.duration : duration,
        duration_tolerance = duration_tolerance,
        status = status
    )

    # Calculate gaps
    best_spread = maximum(all_spreads_bps)
    median_spread = median(all_spreads_bps)

    SpreadComparison(
        product_spread,
        position,
        best_spread - product_spread.spread_bps,
        median_spread - product_spread.spread_bps
    )
end

#=============================================================================
# Display Functions
=============================================================================#

"""
    print_spread_distribution(dist::SpreadDistribution; io::IO=stdout)

Print spread distribution in formatted output.
"""
function print_spread_distribution(dist::SpreadDistribution; io::IO = stdout)
    println(io, "Spread Distribution ($(dist.count) products)")
    println(io, "-" ^ 40)
    println(io, "Min:    $(round(dist.min_bps, digits=1)) bps")
    println(io, "Q1:     $(round(dist.q1_bps, digits=1)) bps")
    println(io, "Median: $(round(dist.median_bps, digits=1)) bps")
    println(io, "Mean:   $(round(dist.mean_bps, digits=1)) bps")
    println(io, "Q3:     $(round(dist.q3_bps, digits=1)) bps")
    println(io, "Max:    $(round(dist.max_bps, digits=1)) bps")
    println(io, "Std:    $(round(dist.std_bps, digits=1)) bps")
end

"""
    print_spread_by_duration(by_duration::Dict{Int, DurationSpreadSummary}; io::IO=stdout)

Print spread summary by duration.
"""
function print_spread_by_duration(by_duration::Dict{Int, DurationSpreadSummary}; io::IO = stdout)
    println(io, "Spreads by Duration")
    println(io, "-" ^ 60)
    println(io, rpad("Duration", 10), rpad("Treasury", 12), rpad("Products", 10), rpad("Mean Spread", 15), "Range")
    println(io, "-" ^ 60)

    for dur in sort(collect(keys(by_duration)))
        s = by_duration[dur]
        tsy_pct = round(s.treasury_rate * 100, digits = 2)
        mean_bps = round(s.distribution.mean_bps, digits = 0)
        min_bps = round(s.distribution.min_bps, digits = 0)
        max_bps = round(s.distribution.max_bps, digits = 0)

        println(io,
            rpad("$(dur)Y", 10),
            rpad("$(tsy_pct)%", 12),
            rpad("$(s.product_count)", 10),
            rpad("$(mean_bps) bps", 15),
            "[$(min_bps), $(max_bps)] bps"
        )
    end
end
