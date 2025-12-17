"""
Product Types for Annuity Pricing.

Defines product specifications and pricing result structures for:
- MYGA (Multi-Year Guaranteed Annuity)
- FIA (Fixed Indexed Annuity)
- RILA (Registered Index-Linked Annuity)
"""


# =============================================================================
# Pricing Results
# =============================================================================

"""
    PricingResult{T<:Real}

Standard pricing result for annuity products.

# Fields
- `present_value::T`: Present value of the product
- `duration::T`: Macaulay duration
- `convexity::Union{T, Nothing}`: Convexity measure (optional)
- `details::Dict{Symbol, Any}`: Additional pricing details
"""
struct PricingResult{T<:Real}
    present_value::T
    duration::T
    convexity::Union{T, Nothing}
    details::Dict{Symbol, Any}

    function PricingResult(
        present_value::T,
        duration::T,
        convexity::Union{T, Nothing},
        details::Dict{Symbol, Any}
    ) where T<:Real
        present_value >= 0 || throw(ArgumentError("present_value must be >= 0, got $present_value"))
        new{T}(present_value, duration, convexity, details)
    end
end


"""
    FIAPricingResult{T<:Real}

Extended pricing result for FIA products.

# Fields
- `present_value::T`: Present value of the product
- `embedded_option_value::T`: Value of embedded index-linked option
- `option_budget::T`: Option budget available for crediting
- `fair_cap::T`: Fair cap rate given option budget
- `fair_participation::T`: Fair participation rate given option budget
- `expected_credit::T`: Expected credited return
- `details::Dict{Symbol, Any}`: Additional pricing details
"""
struct FIAPricingResult{T<:Real}
    present_value::T
    embedded_option_value::T
    option_budget::T
    fair_cap::T
    fair_participation::T
    expected_credit::T
    details::Dict{Symbol, Any}
end


"""
    RILAPricingResult{T<:Real}

Extended pricing result for RILA products.

# Fields
- `present_value::T`: Present value of the product
- `protection_value::T`: Value of downside protection
- `protection_type::Symbol`: :buffer or :floor
- `upside_value::T`: Value of capped upside
- `expected_return::T`: Expected return from product
- `max_loss::T`: Maximum possible loss
- `breakeven_return::T`: Index return needed to break even
- `details::Dict{Symbol, Any}`: Additional pricing details
"""
struct RILAPricingResult{T<:Real}
    present_value::T
    protection_value::T
    protection_type::Symbol
    upside_value::T
    expected_return::T
    max_loss::T
    breakeven_return::T
    details::Dict{Symbol, Any}
end


# =============================================================================
# Market Parameters
# =============================================================================

"""
    MarketParams{T<:Real}

Market parameters for option pricing.

# Fields
- `spot::T`: Current index level
- `risk_free_rate::T`: Risk-free rate (annualized, decimal)
- `dividend_yield::T`: Index dividend yield (annualized, decimal)
- `volatility::T`: Index volatility (annualized, decimal)

# Example
```julia
market = MarketParams(100.0, 0.05, 0.02, 0.20)
# S=100, r=5%, q=2%, σ=20%
```
"""
struct MarketParams{T<:Real}
    spot::T
    risk_free_rate::T
    dividend_yield::T
    volatility::T

    function MarketParams(spot::T, risk_free_rate::T, dividend_yield::T, volatility::T) where T<:Real
        spot > 0 || throw(ArgumentError("spot must be > 0, got $spot"))
        volatility >= 0 || throw(ArgumentError("volatility must be >= 0, got $volatility"))
        new{T}(spot, risk_free_rate, dividend_yield, volatility)
    end
end

# Convenience constructor with keywords (defaults to Float64)
function MarketParams(;
    spot::Real,
    risk_free_rate::Real,
    dividend_yield::Real = 0.0,
    volatility::Real
)
    T = promote_type(typeof(spot), typeof(risk_free_rate), typeof(dividend_yield), typeof(volatility))
    MarketParams(T(spot), T(risk_free_rate), T(dividend_yield), T(volatility))
end


# =============================================================================
# Product Specifications
# =============================================================================

"""
    MYGAProduct{T<:Real}

MYGA (Multi-Year Guaranteed Annuity) product specification.

# Fields
- `fixed_rate::T`: Guaranteed fixed rate (decimal)
- `guarantee_duration::Int`: Term in years
- `company_name::String`: Company name
- `product_name::String`: Product name

# Example
```julia
product = MYGAProduct(0.045, 5, "Example Life", "5-Year MYGA")
```
"""
struct MYGAProduct{T<:Real}
    fixed_rate::T
    guarantee_duration::Int
    company_name::String
    product_name::String

    function MYGAProduct(
        fixed_rate::T,
        guarantee_duration::Int,
        company_name::String,
        product_name::String
    ) where T<:Real
        fixed_rate >= 0 || throw(ArgumentError("fixed_rate must be >= 0"))
        guarantee_duration > 0 || throw(ArgumentError("guarantee_duration must be > 0"))
        new{T}(fixed_rate, guarantee_duration, company_name, product_name)
    end
end

# Keyword constructor
function MYGAProduct(;
    fixed_rate::T,
    guarantee_duration::Int,
    company_name::String = "",
    product_name::String = ""
) where T<:Real
    MYGAProduct(fixed_rate, guarantee_duration, company_name, product_name)
end


"""
    FIAProduct{T<:Real}

FIA (Fixed Indexed Annuity) product specification.

[T1] FIA products have a 0% floor (principal protection).

# Fields
- `cap_rate::Union{T, Nothing}`: Cap rate (decimal, optional)
- `participation_rate::Union{T, Nothing}`: Participation rate (decimal, optional)
- `spread_rate::Union{T, Nothing}`: Spread rate (decimal, optional)
- `trigger_rate::Union{T, Nothing}`: Trigger rate (decimal, optional)
- `term_years::Int`: Investment term in years
- `company_name::String`: Company name
- `product_name::String`: Product name

# Example
```julia
# Cap-style FIA
product = FIAProduct(cap_rate=0.10, term_years=1)

# Participation-style FIA
product = FIAProduct(participation_rate=0.80, term_years=1)
```
"""
struct FIAProduct{T<:Real}
    cap_rate::Union{T, Nothing}
    participation_rate::Union{T, Nothing}
    spread_rate::Union{T, Nothing}
    trigger_rate::Union{T, Nothing}
    term_years::Int
    company_name::String
    product_name::String

    function FIAProduct{T}(
        cap_rate::Union{T, Nothing},
        participation_rate::Union{T, Nothing},
        spread_rate::Union{T, Nothing},
        trigger_rate::Union{T, Nothing},
        term_years::Int,
        company_name::String,
        product_name::String
    ) where T<:Real
        term_years > 0 || throw(ArgumentError("term_years must be > 0"))

        # At least one crediting method required
        has_method = cap_rate !== nothing ||
                     participation_rate !== nothing ||
                     spread_rate !== nothing ||
                     trigger_rate !== nothing
        has_method || throw(ArgumentError(
            "FIA must have at least one crediting method (cap_rate, participation_rate, spread_rate, or trigger_rate)"
        ))

        new{T}(cap_rate, participation_rate, spread_rate, trigger_rate, term_years, company_name, product_name)
    end
end

# Keyword constructor (defaults to Float64)
function FIAProduct(;
    cap_rate::Union{Real, Nothing} = nothing,
    participation_rate::Union{Real, Nothing} = nothing,
    spread_rate::Union{Real, Nothing} = nothing,
    trigger_rate::Union{Real, Nothing} = nothing,
    term_years::Int = 1,
    company_name::String = "",
    product_name::String = ""
)
    # Convert to Float64
    cap = cap_rate === nothing ? nothing : Float64(cap_rate)
    par = participation_rate === nothing ? nothing : Float64(participation_rate)
    spr = spread_rate === nothing ? nothing : Float64(spread_rate)
    trg = trigger_rate === nothing ? nothing : Float64(trigger_rate)
    FIAProduct{Float64}(cap, par, spr, trg, term_years, company_name, product_name)
end


"""
    RILAProduct{T<:Real}

RILA (Registered Index-Linked Annuity) product specification.

[T1] RILA products can have negative returns (partial downside protection).

# Fields
- `buffer_rate::Union{T, Nothing}`: Buffer protection level (decimal, optional)
- `floor_rate::Union{T, Nothing}`: Floor protection level (decimal, negative, optional)
- `cap_rate::Union{T, Nothing}`: Cap rate on upside (decimal, optional)
- `is_buffer::Bool`: true = buffer protection, false = floor protection
- `term_years::Int`: Investment term in years
- `company_name::String`: Company name
- `product_name::String`: Product name

# Example
```julia
# 10% buffer with 20% cap
product = RILAProduct(buffer_rate=0.10, cap_rate=0.20, is_buffer=true, term_years=1)

# -10% floor with 25% cap
product = RILAProduct(floor_rate=-0.10, cap_rate=0.25, is_buffer=false, term_years=1)
```
"""
struct RILAProduct{T<:Real}
    buffer_rate::Union{T, Nothing}
    floor_rate::Union{T, Nothing}
    cap_rate::Union{T, Nothing}
    is_buffer::Bool
    term_years::Int
    company_name::String
    product_name::String

    function RILAProduct{T}(
        buffer_rate::Union{T, Nothing},
        floor_rate::Union{T, Nothing},
        cap_rate::Union{T, Nothing},
        is_buffer::Bool,
        term_years::Int,
        company_name::String,
        product_name::String
    ) where T<:Real
        term_years > 0 || throw(ArgumentError("term_years must be > 0"))

        # Validate protection specified
        if is_buffer
            buffer_rate !== nothing || throw(ArgumentError("buffer_rate required for buffer protection"))
            buffer_rate >= 0 || throw(ArgumentError("buffer_rate must be >= 0"))
        else
            floor_rate !== nothing || throw(ArgumentError("floor_rate required for floor protection"))
            floor_rate <= 0 || throw(ArgumentError("floor_rate must be <= 0 (e.g., -0.10 for -10% floor)"))
        end

        new{T}(buffer_rate, floor_rate, cap_rate, is_buffer, term_years, company_name, product_name)
    end
end

# Keyword constructor (defaults to Float64)
function RILAProduct(;
    buffer_rate::Union{Real, Nothing} = nothing,
    floor_rate::Union{Real, Nothing} = nothing,
    cap_rate::Union{Real, Nothing} = nothing,
    is_buffer::Bool = true,
    term_years::Int = 1,
    company_name::String = "",
    product_name::String = ""
)
    # Convert to Float64
    buf = buffer_rate === nothing ? nothing : Float64(buffer_rate)
    flr = floor_rate === nothing ? nothing : Float64(floor_rate)
    cap = cap_rate === nothing ? nothing : Float64(cap_rate)
    RILAProduct{Float64}(buf, flr, cap, is_buffer, term_years, company_name, product_name)
end
