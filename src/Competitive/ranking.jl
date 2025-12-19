"""
Company and product ranking analysis.

Provides functions for:
- Company rankings by best rate, average rate, or product count
- Product rankings by rate
- Market summary statistics
- Rate leaders by duration
- Competitive landscape analysis
- Tier classification (Leader/Competitive/Follower)
"""

using Statistics: mean

#=============================================================================
# Tier Classification
=============================================================================#

"""
    calculate_tier(percentile::Float64) -> String

Classify company/product into competitive tier based on percentile.

# Tiers
- "Leader": percentile >= 75% (top quartile)
- "Competitive": 50% <= percentile < 75%
- "Follower": percentile < 50%

# Example
```julia
calculate_tier(80.0)  # "Leader"
calculate_tier(60.0)  # "Competitive"
calculate_tier(30.0)  # "Follower"
```
"""
function calculate_tier(percentile::Float64)::String
    (0.0 <= percentile <= 100.0) || error("CRITICAL: percentile must be in [0,100], got $percentile")

    percentile >= 75.0 ? "Leader" :
    percentile >= 50.0 ? "Competitive" : "Follower"
end

#=============================================================================
# Grouping Utilities
=============================================================================#

"""
    group_by_company(data::ProductData) -> Dict{String, ProductData}

Group products by company name.

# Example
```julia
by_company = group_by_company(data)
athene_products = by_company["Athene"]
```
"""
function group_by_company(data::ProductData)::Dict{String, ProductData}
    result = Dict{String, ProductData}()
    for p in data
        push!(get!(result, p.company, WINKProduct[]), p)
    end
    result
end

"""
    group_by_duration(data::ProductData) -> Dict{Int, ProductData}

Group products by duration.

# Example
```julia
by_duration = group_by_duration(data)
five_year = by_duration[5]
```
"""
function group_by_duration(data::ProductData)::Dict{Int, ProductData}
    result = Dict{Int, ProductData}()
    for p in data
        push!(get!(result, p.duration, WINKProduct[]), p)
    end
    result
end

#=============================================================================
# Company Ranking Functions
=============================================================================#

"""
Ranking criteria for company rankings.
"""
@enum RankBy begin
    BEST_RATE
    AVG_RATE
    PRODUCT_COUNT
end

"""
    rank_companies(data::ProductData; rank_by::RankBy=BEST_RATE, top_n::Union{Int, Nothing}=nothing, kwargs...) -> Vector{CompanyRanking}

Rank companies by specified criteria.

# Arguments
- `data`: Product data
- `rank_by`: Ranking criterion (BEST_RATE, AVG_RATE, PRODUCT_COUNT)
- `top_n`: Limit to top N companies (nothing = all)

# Keyword Arguments
Same as `filter_products` for filtering.

# Returns
- Vector of CompanyRanking, sorted by rank

# Example
```julia
rankings = rank_companies(market_data, rank_by = BEST_RATE, top_n = 10)
println("Leader: \$(rankings[1].company) at \$(rankings[1].best_rate)")
```
"""
function rank_companies(
    data::ProductData;
    rank_by::RankBy = BEST_RATE,
    top_n::Union{Int, Nothing} = nothing,
    product_group::Union{String, Nothing} = nothing,
    duration::Union{Int, Nothing} = nothing,
    duration_tolerance::Int = 1,
    status::Symbol = :current
)::Vector{CompanyRanking}
    # Filter data
    filtered = filter_products(
        data,
        product_group = product_group,
        duration = duration,
        duration_tolerance = duration_tolerance,
        status = status
    )

    isempty(filtered) && error("CRITICAL: No products match filter criteria")

    # Group by company
    by_company = group_by_company(filtered)

    # Calculate metrics per company
    company_metrics = [(
        company = company,
        best_rate = maximum(p.rate for p in products),
        avg_rate = mean([p.rate for p in products]),
        product_count = length(products),
        duration_coverage = Tuple(sort(unique([p.duration for p in products])))
    ) for (company, products) in by_company]

    # Sort by criterion
    sort_fn = if rank_by == BEST_RATE
        m -> -m.best_rate  # Descending
    elseif rank_by == AVG_RATE
        m -> -m.avg_rate   # Descending
    else  # PRODUCT_COUNT
        m -> -m.product_count  # Descending
    end
    sorted_metrics = sort(company_metrics, by = sort_fn)

    # Apply top_n limit
    if !isnothing(top_n)
        sorted_metrics = sorted_metrics[1:min(top_n, length(sorted_metrics))]
    end

    # Create rankings
    [
        CompanyRanking(
            company = m.company,
            rank = i,
            best_rate = m.best_rate,
            avg_rate = m.avg_rate,
            product_count = m.product_count,
            duration_coverage = m.duration_coverage
        )
        for (i, m) in enumerate(sorted_metrics)
    ]
end

"""
    get_company_rank(company::String, data::ProductData; rank_by::RankBy=BEST_RATE, kwargs...) -> Union{CompanyRanking, Nothing}

Get ranking for a specific company.

# Arguments
- `company`: Company name (case-insensitive match)
- `data`: Product data
- `rank_by`: Ranking criterion

# Returns
- CompanyRanking if found, nothing if company not in data

# Example
```julia
ranking = get_company_rank("Athene", market_data)
if !isnothing(ranking)
    println("\$(ranking.company) ranks #\$(ranking.rank)")
end
```
"""
function get_company_rank(
    company::String,
    data::ProductData;
    rank_by::RankBy = BEST_RATE,
    product_group::Union{String, Nothing} = nothing,
    duration::Union{Int, Nothing} = nothing,
    duration_tolerance::Int = 1,
    status::Symbol = :current
)::Union{CompanyRanking, Nothing}
    rankings = rank_companies(
        data,
        rank_by = rank_by,
        product_group = product_group,
        duration = duration,
        duration_tolerance = duration_tolerance,
        status = status
    )

    company_lower = lowercase(company)
    for r in rankings
        if lowercase(r.company) == company_lower
            return r
        end
    end

    nothing
end

#=============================================================================
# Product Ranking Functions
=============================================================================#

"""
    rank_products(data::ProductData; top_n::Union{Int, Nothing}=nothing, kwargs...) -> Vector{ProductRanking}

Rank products by rate (highest = rank 1).

# Arguments
- `data`: Product data
- `top_n`: Limit to top N products (nothing = all)

# Keyword Arguments
Same as `filter_products` for filtering.

# Returns
- Vector of ProductRanking, sorted by rate descending

# Example
```julia
top_products = rank_products(market_data, top_n = 10)
for p in top_products
    println("#\$(p.rank): \$(p.company) \$(p.product) at \$(p.rate)")
end
```
"""
function rank_products(
    data::ProductData;
    top_n::Union{Int, Nothing} = nothing,
    product_group::Union{String, Nothing} = nothing,
    duration::Union{Int, Nothing} = nothing,
    duration_tolerance::Int = 1,
    status::Symbol = :current
)::Vector{ProductRanking}
    # Filter data
    filtered = filter_products(
        data,
        product_group = product_group,
        duration = duration,
        duration_tolerance = duration_tolerance,
        status = status
    )

    isempty(filtered) && error("CRITICAL: No products match filter criteria")

    # Sort by rate descending
    sorted_products = sort(filtered, by = p -> p.rate, rev = true)

    # Apply top_n limit
    if !isnothing(top_n)
        sorted_products = sorted_products[1:min(top_n, length(sorted_products))]
    end

    # Create rankings
    [
        ProductRanking(
            company = p.company,
            product = p.product,
            rank = i,
            rate = p.rate,
            duration = p.duration
        )
        for (i, p) in enumerate(sorted_products)
    ]
end

#=============================================================================
# Market Analysis Functions
=============================================================================#

"""
    MarketSummary

Summary statistics for market analysis.
"""
struct MarketSummary
    total_products::Int
    total_companies::Int
    rate_stats::DistributionStats
    duration_range::Tuple{Int, Int}
    product_groups::Vector{String}
end

"""
    market_summary(data::ProductData; kwargs...) -> MarketSummary

Get overall market summary statistics.

# Arguments
- `data`: Product data

# Keyword Arguments
Same as `filter_products` for filtering.

# Example
```julia
summary = market_summary(market_data, product_group = "MYGA")
println("\$(summary.total_companies) companies offer \$(summary.total_products) products")
```
"""
function market_summary(
    data::ProductData;
    product_group::Union{String, Nothing} = nothing,
    duration::Union{Int, Nothing} = nothing,
    duration_tolerance::Int = 1,
    status::Symbol = :current
)::MarketSummary
    filtered = filter_products(
        data,
        product_group = product_group,
        duration = duration,
        duration_tolerance = duration_tolerance,
        status = status
    )

    isempty(filtered) && error("CRITICAL: No products match filter criteria")

    duration_vals = durations(filtered)

    MarketSummary(
        length(filtered),
        length(unique(companies(filtered))),
        DistributionStats(rates(filtered)),
        (minimum(duration_vals), maximum(duration_vals)),
        sort(unique([p.product_group for p in filtered]))
    )
end

"""
    rate_leaders_by_duration(data::ProductData; top_n::Int=3, kwargs...) -> Dict{Int, Vector{ProductRanking}}

Get top products for each duration.

# Arguments
- `data`: Product data
- `top_n`: Number of leaders per duration (default: 3)

# Returns
- Dict mapping duration => top product rankings

# Example
```julia
leaders = rate_leaders_by_duration(market_data, product_group = "MYGA")
for (duration, products) in sort(collect(leaders))
    println("\$(duration)-year leaders:")
    for p in products
        println("  \$(p.company): \$(p.rate)")
    end
end
```
"""
function rate_leaders_by_duration(
    data::ProductData;
    top_n::Int = 3,
    product_group::Union{String, Nothing} = nothing,
    status::Symbol = :current
)::Dict{Int, Vector{ProductRanking}}
    filtered = filter_products(
        data,
        product_group = product_group,
        status = status
    )

    isempty(filtered) && error("CRITICAL: No products match filter criteria")

    # Group by duration
    by_duration = group_by_duration(filtered)

    # Get top N for each duration
    result = Dict{Int, Vector{ProductRanking}}()
    for (dur, products) in by_duration
        sorted = sort(products, by = p -> p.rate, rev = true)
        result[dur] = [
            ProductRanking(
                company = p.company,
                product = p.product,
                rank = i,
                rate = p.rate,
                duration = p.duration
            )
            for (i, p) in enumerate(sorted[1:min(top_n, length(sorted))])
        ]
    end

    result
end

"""
    CompetitiveLandscape

Full competitive landscape analysis result.
"""
struct CompetitiveLandscape
    market::MarketSummary
    company_rankings::Vector{CompanyRanking}
    product_rankings::Vector{ProductRanking}
    leaders_by_duration::Dict{Int, Vector{ProductRanking}}
    tier_distribution::Dict{String, Int}
end

"""
    competitive_landscape(data::ProductData; top_companies::Int=10, top_products::Int=20, kwargs...) -> CompetitiveLandscape

Perform full competitive landscape analysis.

# Arguments
- `data`: Product data
- `top_companies`: Number of company rankings to include (default: 10)
- `top_products`: Number of product rankings to include (default: 20)

# Keyword Arguments
Same as `filter_products` for filtering.

# Returns
- CompetitiveLandscape with market summary, rankings, and tier distribution

# Example
```julia
landscape = competitive_landscape(market_data, product_group = "MYGA")
println("Market has \$(landscape.market.total_companies) companies")
println("Leader: \$(landscape.company_rankings[1].company)")
```
"""
function competitive_landscape(
    data::ProductData;
    top_companies::Int = 10,
    top_products::Int = 20,
    product_group::Union{String, Nothing} = nothing,
    duration::Union{Int, Nothing} = nothing,
    duration_tolerance::Int = 1,
    status::Symbol = :current
)::CompetitiveLandscape
    filtered = filter_products(
        data,
        product_group = product_group,
        duration = duration,
        duration_tolerance = duration_tolerance,
        status = status
    )

    isempty(filtered) && error("CRITICAL: No products match filter criteria")

    # Get company rankings
    company_rankings = rank_companies(
        filtered,
        rank_by = BEST_RATE,
        top_n = top_companies
    )

    # Get product rankings
    product_rankings = rank_products(
        filtered,
        top_n = top_products
    )

    # Get leaders by duration (only if no specific duration filter)
    leaders = if isnothing(duration)
        rate_leaders_by_duration(filtered, product_group = product_group, status = status)
    else
        Dict{Int, Vector{ProductRanking}}()
    end

    # Calculate tier distribution
    all_company_rankings = rank_companies(filtered, rank_by = BEST_RATE)
    tier_distribution = Dict{String, Int}(
        "Leader" => 0,
        "Competitive" => 0,
        "Follower" => 0
    )

    for (i, r) in enumerate(all_company_rankings)
        percentile = (1 - i / length(all_company_rankings)) * 100
        tier = calculate_tier(percentile)
        tier_distribution[tier] += 1
    end

    CompetitiveLandscape(
        market_summary(filtered),
        company_rankings,
        product_rankings,
        leaders,
        tier_distribution
    )
end

#=============================================================================
# Display Functions
=============================================================================#

"""
    print_company_rankings(rankings::Vector{CompanyRanking}; io::IO=stdout)

Print company rankings in formatted table.
"""
function print_company_rankings(rankings::Vector{CompanyRanking}; io::IO = stdout)
    println(io, "Company Rankings")
    println(io, "-" ^ 70)
    println(io, rpad("Rank", 6), rpad("Company", 30), rpad("Best Rate", 12), rpad("Avg Rate", 12), "Products")
    println(io, "-" ^ 70)

    for r in rankings
        best_pct = round(r.best_rate * 100, digits = 2)
        avg_pct = round(r.avg_rate * 100, digits = 2)
        println(io,
            rpad("#$(r.rank)", 6),
            rpad(r.company[1:min(28, length(r.company))], 30),
            rpad("$(best_pct)%", 12),
            rpad("$(avg_pct)%", 12),
            r.product_count
        )
    end
end

"""
    print_product_rankings(rankings::Vector{ProductRanking}; io::IO=stdout)

Print product rankings in formatted table.
"""
function print_product_rankings(rankings::Vector{ProductRanking}; io::IO = stdout)
    println(io, "Product Rankings")
    println(io, "-" ^ 80)
    println(io, rpad("Rank", 6), rpad("Company", 25), rpad("Product", 25), rpad("Rate", 10), "Duration")
    println(io, "-" ^ 80)

    for r in rankings
        rate_pct = round(r.rate * 100, digits = 2)
        println(io,
            rpad("#$(r.rank)", 6),
            rpad(r.company[1:min(23, length(r.company))], 25),
            rpad(r.product[1:min(23, length(r.product))], 25),
            rpad("$(rate_pct)%", 10),
            "$(r.duration)Y"
        )
    end
end
