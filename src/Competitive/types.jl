"""
Type definitions for Competitive Analysis module.

Provides data types for:
- Product data (WINKProduct, ProductData)
- Positioning results (PositionResult, DistributionStats)
- Ranking results (CompanyRanking, ProductRanking)
- Spread results (SpreadResult, SpreadDistribution)

All result types use inner constructors with validation.
"""

using Dates
using Statistics: mean, median, std, quantile

#=============================================================================
# Product Data Types
=============================================================================#

"""
    WINKProduct

Represents a single annuity product from WINK competitive data.

# Fields
- `company::String`: Insurance company name
- `product::String`: Product name
- `rate::Float64`: Credited rate (decimal, e.g., 0.045 for 4.5%)
- `duration::Int`: Term duration in years
- `product_group::String`: Product category (e.g., "MYGA", "FIA", "RILA")
- `status::Symbol`: `:current` or `:discontinued`

# Example
```julia
product = WINKProduct(
    company = "Athene",
    product = "Protector 5",
    rate = 0.0525,
    duration = 5,
    product_group = "MYGA",
    status = :current
)
```
"""
struct WINKProduct
    company::String
    product::String
    rate::Float64
    duration::Int
    product_group::String
    status::Symbol

    function WINKProduct(;
        company::String,
        product::String,
        rate::Float64,
        duration::Int,
        product_group::String,
        status::Symbol = :current
    )
        # Validation
        isempty(company) && error("CRITICAL: company cannot be empty")
        isempty(product) && error("CRITICAL: product cannot be empty")
        duration < 1 && error("CRITICAL: duration must be >= 1, got $duration")
        status in (:current, :discontinued) || error("CRITICAL: status must be :current or :discontinued, got $status")

        new(company, product, rate, duration, product_group, status)
    end
end

# Convenience constructor with positional arguments
function WINKProduct(
    company::String,
    product::String,
    rate::Float64,
    duration::Int,
    product_group::String,
    status::Symbol = :current
)
    WINKProduct(
        company = company,
        product = product,
        rate = rate,
        duration = duration,
        product_group = product_group,
        status = status
    )
end

"""
Collection type alias for product data.
Replaces pandas DataFrame in Python implementation.
"""
const ProductData = Vector{WINKProduct}

#=============================================================================
# Positioning Result Types
=============================================================================#

"""
    PositionResult

Result of market position analysis for a given rate.

# Fields
- `rate::Float64`: The analyzed rate
- `percentile::Float64`: Position as percentile (0-100), higher = better
- `rank::Int`: Position as rank (1 = best/highest rate)
- `total_products::Int`: Number of products in comparison set
- `quartile::Int`: Position quartile (1-4, where 1 = top 25%)
- `position_label::String`: Human-readable position description

# Validation
- percentile must be in [0, 100]
- rank must be >= 1
- quartile must be in [1, 4]
"""
struct PositionResult
    rate::Float64
    percentile::Float64
    rank::Int
    total_products::Int
    quartile::Int
    position_label::String

    function PositionResult(;
        rate::Float64,
        percentile::Float64,
        rank::Int,
        total_products::Int,
        quartile::Int,
        position_label::String
    )
        # Validation
        (0.0 <= percentile <= 100.0) || error("CRITICAL: percentile must be in [0,100], got $percentile")
        rank >= 1 || error("CRITICAL: rank must be >= 1, got $rank")
        (1 <= quartile <= 4) || error("CRITICAL: quartile must be 1-4, got $quartile")
        total_products >= 1 || error("CRITICAL: total_products must be >= 1, got $total_products")
        rank <= total_products || error("CRITICAL: rank ($rank) cannot exceed total_products ($total_products)")

        new(rate, percentile, rank, total_products, quartile, position_label)
    end
end

"""
    DistributionStats

Statistical summary of rate distribution in the market.

# Fields
- `min::Float64`: Minimum rate
- `max::Float64`: Maximum rate
- `mean::Float64`: Average rate
- `median::Float64`: Median rate
- `std::Float64`: Standard deviation
- `q1::Float64`: First quartile (25th percentile)
- `q3::Float64`: Third quartile (75th percentile)
- `count::Int`: Number of products
"""
struct DistributionStats
    min::Float64
    max::Float64
    mean::Float64
    median::Float64
    std::Float64
    q1::Float64
    q3::Float64
    count::Int

    function DistributionStats(;
        min::Float64,
        max::Float64,
        mean::Float64,
        median::Float64,
        std::Float64,
        q1::Float64,
        q3::Float64,
        count::Int
    )
        count >= 1 || error("CRITICAL: count must be >= 1, got $count")
        min <= max || error("CRITICAL: min ($min) cannot exceed max ($max)")

        new(min, max, mean, median, std, q1, q3, count)
    end
end

"""
Construct DistributionStats from a vector of rates.
"""
function DistributionStats(rates::Vector{Float64})
    isempty(rates) && error("CRITICAL: Cannot compute distribution stats from empty data")

    DistributionStats(
        min = minimum(rates),
        max = maximum(rates),
        mean = mean(rates),
        median = median(rates),
        std = length(rates) > 1 ? std(rates) : 0.0,
        q1 = quantile(rates, 0.25),
        q3 = quantile(rates, 0.75),
        count = length(rates)
    )
end

#=============================================================================
# Ranking Result Types
=============================================================================#

"""
    CompanyRanking

Ranking result for a single company.

# Fields
- `company::String`: Company name
- `rank::Int`: Rank position (1 = best)
- `best_rate::Float64`: Highest rate offered
- `avg_rate::Float64`: Average rate across products
- `product_count::Int`: Number of products
- `duration_coverage::NTuple{N, Int} where N`: Durations offered (sorted)

# Validation
- rank must be >= 1
- product_count must be >= 1
"""
struct CompanyRanking
    company::String
    rank::Int
    best_rate::Float64
    avg_rate::Float64
    product_count::Int
    duration_coverage::Tuple{Vararg{Int}}

    function CompanyRanking(;
        company::String,
        rank::Int,
        best_rate::Float64,
        avg_rate::Float64,
        product_count::Int,
        duration_coverage::Tuple{Vararg{Int}}
    )
        isempty(company) && error("CRITICAL: company cannot be empty")
        rank >= 1 || error("CRITICAL: rank must be >= 1, got $rank")
        product_count >= 1 || error("CRITICAL: product_count must be >= 1, got $product_count")

        new(company, rank, best_rate, avg_rate, product_count, duration_coverage)
    end
end

"""
    ProductRanking

Ranking result for a single product.

# Fields
- `company::String`: Company name
- `product::String`: Product name
- `rank::Int`: Rank position (1 = best/highest rate)
- `rate::Float64`: Product rate
- `duration::Int`: Product duration

# Validation
- rank must be >= 1
"""
struct ProductRanking
    company::String
    product::String
    rank::Int
    rate::Float64
    duration::Int

    function ProductRanking(;
        company::String,
        product::String,
        rank::Int,
        rate::Float64,
        duration::Int
    )
        isempty(company) && error("CRITICAL: company cannot be empty")
        isempty(product) && error("CRITICAL: product cannot be empty")
        rank >= 1 || error("CRITICAL: rank must be >= 1, got $rank")

        new(company, product, rank, rate, duration)
    end
end

#=============================================================================
# Spread Result Types
=============================================================================#

"""
    SpreadResult

Spread analysis result for a single product.

# Fields
- `product_rate::Float64`: Product credited rate
- `treasury_rate::Float64`: Treasury rate for matching duration
- `spread_bps::Float64`: Spread in basis points
- `spread_pct::Float64`: Spread as percentage
- `duration::Int`: Term duration
- `as_of_date::Date`: Date of treasury rate

# Note
Negative spreads are allowed (product rate < treasury rate).
"""
struct SpreadResult
    product_rate::Float64
    treasury_rate::Float64
    spread_bps::Float64
    spread_pct::Float64
    duration::Int
    as_of_date::Date

    function SpreadResult(;
        product_rate::Float64,
        treasury_rate::Float64,
        spread_bps::Float64,
        spread_pct::Float64,
        duration::Int,
        as_of_date::Date
    )
        duration >= 1 || error("CRITICAL: duration must be >= 1, got $duration")

        new(product_rate, treasury_rate, spread_bps, spread_pct, duration, as_of_date)
    end
end

"""
    SpreadDistribution

Statistical summary of spread distribution.

# Fields
- `min_bps::Float64`: Minimum spread in basis points
- `max_bps::Float64`: Maximum spread in basis points
- `mean_bps::Float64`: Average spread
- `median_bps::Float64`: Median spread
- `std_bps::Float64`: Standard deviation
- `q1_bps::Float64`: First quartile
- `q3_bps::Float64`: Third quartile
- `count::Int`: Number of products
"""
struct SpreadDistribution
    min_bps::Float64
    max_bps::Float64
    mean_bps::Float64
    median_bps::Float64
    std_bps::Float64
    q1_bps::Float64
    q3_bps::Float64
    count::Int

    function SpreadDistribution(;
        min_bps::Float64,
        max_bps::Float64,
        mean_bps::Float64,
        median_bps::Float64,
        std_bps::Float64,
        q1_bps::Float64,
        q3_bps::Float64,
        count::Int
    )
        count >= 1 || error("CRITICAL: count must be >= 1, got $count")

        new(min_bps, max_bps, mean_bps, median_bps, std_bps, q1_bps, q3_bps, count)
    end
end

"""
Construct SpreadDistribution from a vector of spreads in basis points.
"""
function SpreadDistribution(spreads_bps::Vector{Float64})
    isempty(spreads_bps) && error("CRITICAL: Cannot compute spread distribution from empty data")

    SpreadDistribution(
        min_bps = minimum(spreads_bps),
        max_bps = maximum(spreads_bps),
        mean_bps = mean(spreads_bps),
        median_bps = median(spreads_bps),
        std_bps = length(spreads_bps) > 1 ? std(spreads_bps) : 0.0,
        q1_bps = quantile(spreads_bps, 0.25),
        q3_bps = quantile(spreads_bps, 0.75),
        count = length(spreads_bps)
    )
end

#=============================================================================
# Constants
=============================================================================#

"""
FRED Treasury series identifiers by duration (years).
"""
const TREASURY_SERIES = Dict{Int, String}(
    1 => "DGS1",
    2 => "DGS2",
    3 => "DGS3",
    5 => "DGS5",
    7 => "DGS7",
    10 => "DGS10"
)

#=============================================================================
# Utility Functions
=============================================================================#

"""
    rates(data::ProductData) -> Vector{Float64}

Extract rates from product data.
"""
rates(data::ProductData) = [p.rate for p in data]

"""
    durations(data::ProductData) -> Vector{Int}

Extract durations from product data.
"""
durations(data::ProductData) = [p.duration for p in data]

"""
    companies(data::ProductData) -> Vector{String}

Extract unique companies from product data.
"""
companies(data::ProductData) = unique([p.company for p in data])
