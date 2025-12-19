"""
Market positioning analysis for competitive rates.

Provides functions for:
- Percentile-based positioning
- Quartile classification
- Distribution statistics
- Peer comparison
- Flexible product filtering

Key algorithms:
- Percentile: count-based (count(<=value)/total*100) [T1]
- Rank: 1-based where 1 = highest rate (best)
- Quartile: Q1 >= 75%, Q2 >= 50%, Q3 >= 25%, Q4 < 25%
"""

#=============================================================================
# Core Calculation Functions
=============================================================================#

"""
    calculate_percentile(value::Float64, distribution::Vector{Float64}) -> Float64

Calculate count-based percentile of value within distribution.

Uses count method: (count of values <= value) / total * 100
This matches Python's scipy.stats.percentileofscore with kind='weak'.

# Arguments
- `value`: The value to calculate percentile for
- `distribution`: Vector of comparison values

# Returns
- Percentile in range [0, 100]

# Example
```julia
rates = [0.03, 0.04, 0.05, 0.06]
calculate_percentile(0.05, rates)  # 75.0 (3 of 4 values <= 0.05)
```

# Note
[T1] Count-based percentile is standard for competitive positioning.
"""
function calculate_percentile(value::Float64, distribution::Vector{Float64})::Float64
    isempty(distribution) && error("CRITICAL: Cannot calculate percentile of empty distribution")
    count(x -> x <= value, distribution) / length(distribution) * 100.0
end

"""
    calculate_rank(value::Float64, distribution::Vector{Float64}) -> Int

Calculate rank of value within distribution (1 = highest/best).

# Arguments
- `value`: The value to rank
- `distribution`: Vector of comparison values

# Returns
- Rank (1-based, where 1 = highest value)

# Example
```julia
rates = [0.03, 0.04, 0.05, 0.06]
calculate_rank(0.05, rates)  # 2 (only 0.06 is higher)
```
"""
function calculate_rank(value::Float64, distribution::Vector{Float64})::Int
    isempty(distribution) && error("CRITICAL: Cannot calculate rank in empty distribution")
    count(x -> x > value, distribution) + 1
end

"""
    calculate_quartile(percentile::Float64) -> Int

Convert percentile to quartile (1-4).

# Thresholds [T1]
- Q1: percentile >= 75% (top quartile)
- Q2: 50% <= percentile < 75%
- Q3: 25% <= percentile < 50%
- Q4: percentile < 25% (bottom quartile)

# Example
```julia
calculate_quartile(80.0)  # 1
calculate_quartile(60.0)  # 2
calculate_quartile(30.0)  # 3
calculate_quartile(10.0)  # 4
```
"""
function calculate_quartile(percentile::Float64)::Int
    (0.0 <= percentile <= 100.0) || error("CRITICAL: percentile must be in [0,100], got $percentile")

    percentile >= 75.0 ? 1 :
    percentile >= 50.0 ? 2 :
    percentile >= 25.0 ? 3 : 4
end

"""
    get_position_label(percentile::Float64) -> String

Convert percentile to human-readable position label.

# Labels
- "Top 10%": percentile >= 90
- "Top Quartile": percentile >= 75
- "Above Median": percentile >= 50
- "Below Median": percentile >= 25
- "Bottom Quartile": percentile < 25

# Example
```julia
get_position_label(95.0)  # "Top 10%"
get_position_label(60.0)  # "Above Median"
```
"""
function get_position_label(percentile::Float64)::String
    (0.0 <= percentile <= 100.0) || error("CRITICAL: percentile must be in [0,100], got $percentile")

    percentile >= 90.0 ? "Top 10%" :
    percentile >= 75.0 ? "Top Quartile" :
    percentile >= 50.0 ? "Above Median" :
    percentile >= 25.0 ? "Below Median" : "Bottom Quartile"
end

#=============================================================================
# Filter Functions
=============================================================================#

"""
    filter_products(data::ProductData; kwargs...) -> ProductData

Filter products by various criteria.

# Keyword Arguments
- `product_group::Union{String, Nothing}=nothing`: Filter by product group (e.g., "MYGA")
- `duration::Union{Int, Nothing}=nothing`: Filter by duration
- `duration_tolerance::Int=1`: Tolerance for duration matching (±years)
- `status::Symbol=:current`: Filter by status (:current or :discontinued)
- `exclude_company::Union{String, Nothing}=nothing`: Exclude specific company

# Example
```julia
filtered = filter_products(data,
    product_group = "MYGA",
    duration = 5,
    status = :current
)
```
"""
function filter_products(
    data::ProductData;
    product_group::Union{String, Nothing} = nothing,
    duration::Union{Int, Nothing} = nothing,
    duration_tolerance::Int = 1,
    status::Symbol = :current,
    exclude_company::Union{String, Nothing} = nothing
)::ProductData
    filter(data) do p
        (isnothing(product_group) || p.product_group == product_group) &&
        (isnothing(duration) || abs(p.duration - duration) <= duration_tolerance) &&
        p.status == status &&
        (isnothing(exclude_company) || lowercase(p.company) != lowercase(exclude_company))
    end
end

#=============================================================================
# Main Positioning Functions
=============================================================================#

"""
    analyze_position(rate::Float64, data::ProductData; kwargs...) -> PositionResult

Analyze competitive position for a given rate.

# Arguments
- `rate`: The rate to analyze
- `data`: Product data for comparison

# Keyword Arguments
Same as `filter_products` for filtering the comparison set.

# Returns
- `PositionResult` with percentile, rank, quartile, and label

# Example
```julia
result = analyze_position(0.05, market_data,
    product_group = "MYGA",
    duration = 5
)
println("Your rate is in the \$(result.position_label)")
```

# Throws
- Error if no comparable products after filtering
"""
function analyze_position(
    rate::Float64,
    data::ProductData;
    product_group::Union{String, Nothing} = nothing,
    duration::Union{Int, Nothing} = nothing,
    duration_tolerance::Int = 1,
    status::Symbol = :current,
    exclude_company::Union{String, Nothing} = nothing
)::PositionResult
    # Filter to comparison set
    filtered = filter_products(
        data,
        product_group = product_group,
        duration = duration,
        duration_tolerance = duration_tolerance,
        status = status,
        exclude_company = exclude_company
    )

    isempty(filtered) && error("CRITICAL: No comparable products after filtering")

    # Extract rates
    comparison_rates = rates(filtered)

    # Calculate metrics
    percentile = calculate_percentile(rate, comparison_rates)
    rank = calculate_rank(rate, comparison_rates)
    quartile = calculate_quartile(percentile)
    label = get_position_label(percentile)

    PositionResult(
        rate = rate,
        percentile = percentile,
        rank = rank,
        total_products = length(filtered),
        quartile = quartile,
        position_label = label
    )
end

"""
    get_distribution_stats(data::ProductData; kwargs...) -> DistributionStats

Get statistical summary of rate distribution.

# Arguments
- `data`: Product data

# Keyword Arguments
Same as `filter_products` for filtering.

# Returns
- `DistributionStats` with min, max, mean, median, std, quartiles, count

# Example
```julia
stats = get_distribution_stats(market_data, product_group = "MYGA")
println("Market rates range from \$(stats.min) to \$(stats.max)")
```
"""
function get_distribution_stats(
    data::ProductData;
    product_group::Union{String, Nothing} = nothing,
    duration::Union{Int, Nothing} = nothing,
    duration_tolerance::Int = 1,
    status::Symbol = :current,
    exclude_company::Union{String, Nothing} = nothing
)::DistributionStats
    filtered = filter_products(
        data,
        product_group = product_group,
        duration = duration,
        duration_tolerance = duration_tolerance,
        status = status,
        exclude_company = exclude_company
    )

    isempty(filtered) && error("CRITICAL: No products match filter criteria")

    DistributionStats(rates(filtered))
end

"""
    get_percentile_thresholds(data::ProductData; percentiles::Vector{Float64}=[10.0, 25.0, 50.0, 75.0, 90.0], kwargs...) -> Dict{Float64, Float64}

Get rate thresholds at specified percentiles.

# Arguments
- `data`: Product data
- `percentiles`: List of percentiles to calculate (default: 10, 25, 50, 75, 90)

# Keyword Arguments
Same as `filter_products` for filtering.

# Returns
- Dict mapping percentile => rate threshold

# Example
```julia
thresholds = get_percentile_thresholds(market_data, product_group = "MYGA")
println("75th percentile rate: \$(thresholds[75.0])")
```
"""
function get_percentile_thresholds(
    data::ProductData;
    percentiles::Vector{Float64} = [10.0, 25.0, 50.0, 75.0, 90.0],
    product_group::Union{String, Nothing} = nothing,
    duration::Union{Int, Nothing} = nothing,
    duration_tolerance::Int = 1,
    status::Symbol = :current,
    exclude_company::Union{String, Nothing} = nothing
)::Dict{Float64, Float64}
    # Validate percentiles
    for p in percentiles
        (0.0 <= p <= 100.0) || error("CRITICAL: percentile must be in [0,100], got $p")
    end

    filtered = filter_products(
        data,
        product_group = product_group,
        duration = duration,
        duration_tolerance = duration_tolerance,
        status = status,
        exclude_company = exclude_company
    )

    isempty(filtered) && error("CRITICAL: No products match filter criteria")

    rate_values = rates(filtered)
    Dict(p => quantile(rate_values, p / 100.0) for p in percentiles)
end

"""
    compare_to_peers(rate::Float64, company::String, data::ProductData; top_n::Int=5, kwargs...) -> NamedTuple

Compare a rate to peer competitors.

# Arguments
- `rate`: The rate to compare
- `company`: Company to exclude from comparison (to avoid self-comparison)
- `data`: Product data
- `top_n`: Number of top competitors to return (default: 5)

# Keyword Arguments
Same as `filter_products` for filtering (excluding `exclude_company` which uses `company`).

# Returns
Named tuple with:
- `position`: PositionResult for the rate
- `top_competitors`: Vector of (company, product, rate) tuples
- `gap_to_leader`: Difference from highest rate
- `gap_to_median`: Difference from median rate

# Example
```julia
comparison = compare_to_peers(0.05, "MyCompany", market_data,
    product_group = "MYGA",
    duration = 5
)
println("Gap to leader: \$(comparison.gap_to_leader * 100) bps")
```
"""
function compare_to_peers(
    rate::Float64,
    company::String,
    data::ProductData;
    top_n::Int = 5,
    product_group::Union{String, Nothing} = nothing,
    duration::Union{Int, Nothing} = nothing,
    duration_tolerance::Int = 1,
    status::Symbol = :current
)::NamedTuple
    # Get position (excluding own company)
    position = analyze_position(
        rate,
        data,
        product_group = product_group,
        duration = duration,
        duration_tolerance = duration_tolerance,
        status = status,
        exclude_company = company
    )

    # Get filtered peers
    peers = filter_products(
        data,
        product_group = product_group,
        duration = duration,
        duration_tolerance = duration_tolerance,
        status = status,
        exclude_company = company
    )

    # Sort by rate descending
    sorted_peers = sort(peers, by = p -> p.rate, rev = true)

    # Get top N
    top_competitors = [
        (company = p.company, product = p.product, rate = p.rate)
        for p in sorted_peers[1:min(top_n, length(sorted_peers))]
    ]

    # Calculate gaps
    peer_rates = rates(peers)
    leader_rate = maximum(peer_rates)
    median_rate = median(peer_rates)

    (
        position = position,
        top_competitors = top_competitors,
        gap_to_leader = leader_rate - rate,
        gap_to_median = median_rate - rate
    )
end

"""
    position_summary(result::PositionResult) -> String

Generate a summary string for a position result.

# Example
```julia
result = analyze_position(0.05, data)
println(position_summary(result))
# "Rate 5.00% ranks #3 of 50 products (88th percentile, Top Quartile)"
```
"""
function position_summary(result::PositionResult)::String
    rate_pct = round(result.rate * 100, digits = 2)
    "Rate $(rate_pct)% ranks #$(result.rank) of $(result.total_products) products " *
    "($(round(result.percentile, digits=1))th percentile, $(result.position_label))"
end
