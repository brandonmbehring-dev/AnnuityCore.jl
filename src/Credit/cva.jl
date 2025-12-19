"""
Credit Valuation Adjustment (CVA) for annuity products.

[T1] CVA = -LGD x SUM(EE(t) x PD(t) x DF(t))

where:
- LGD = Loss Given Default (1 - recovery rate)
- EE(t) = Expected Exposure at time t
- PD(t) = Probability of default in period ending at t
- DF(t) = Discount factor to time t

For annuities, we adjust for state guaranty fund coverage:
- Adjusted CVA = CVA x (1 - coverage_ratio)

References
----------
[T1] Hull, J. (2018). Options, Futures, and Other Derivatives. Ch. 24.
[T2] Gregory, J. (2015). The xVA Challenge. Wiley.
"""

#=============================================================================
# Exposure Profile Functions
=============================================================================#

"""
    calculate_exposure_profile(principal::Float64, rate::Float64, term_years::Int; payment_frequency::Int=1) -> Vector{Float64}

Calculate expected exposure profile for MYGA.

[T1] For a fixed annuity, exposure = PV of remaining guaranteed payments.
At time t, exposure = Principal x (1 + rate)^t x remaining_factor

# Arguments
- `principal`: Initial principal/premium
- `rate`: Guaranteed rate (decimal)
- `term_years`: Contract term in years
- `payment_frequency`: Payments per year (1 = annual, 12 = monthly)

# Returns
- Exposure at each time point (per period)
"""
function calculate_exposure_profile(
    principal::Float64,
    rate::Float64,
    term_years::Int;
    payment_frequency::Int = 1
)::Vector{Float64}
    principal > 0 || error("CRITICAL: principal must be > 0, got $principal")
    term_years >= 1 || error("CRITICAL: term_years must be >= 1, got $term_years")
    payment_frequency >= 1 || error("CRITICAL: payment_frequency must be >= 1, got $payment_frequency")

    periods = term_years * payment_frequency
    exposures = zeros(periods)

    # Maturity value of the annuity
    maturity_value = principal * (1 + rate)^term_years

    for t in 1:periods
        # Time in years
        years_elapsed = t / payment_frequency
        years_remaining = term_years - years_elapsed

        # Exposure is PV of remaining guaranteed maturity value
        # This decreases as we approach maturity
        remaining_pv = maturity_value / (1 + rate)^years_remaining

        exposures[t] = remaining_pv
    end

    exposures
end

#=============================================================================
# CVA Calculation Functions
=============================================================================#

"""
    calculate_cva(exposure::Float64, rating::AMBestRating; kwargs...) -> CVAResult

Calculate Credit Valuation Adjustment for annuity.

[T1] CVA = LGD x EE x (1 - exp(-h x T))

where h is hazard rate and T is time horizon.

# Arguments
- `exposure`: Expected exposure (contract value)
- `rating`: Insurer AM Best rating

# Keyword Arguments
- `term_years::Int=1`: Contract term/horizon in years
- `lgd::Float64=DEFAULT_INSURANCE_LGD`: Loss given default (default 70%)
- `risk_free_rate::Float64=0.05`: Risk-free rate for discounting
- `state::Union{String, Nothing}=nothing`: State for guaranty adjustment
- `coverage_type::CoverageType=ANNUITY_DEFERRED`: Type of coverage for guaranty limits

# Returns
- `CVAResult` with gross and net CVA

# Example
```julia
result = calculate_cva(
    250000.0, A,
    term_years = 5,
    state = "TX"
)
println("CVA: \$(result.cva_net)")
```
"""
function calculate_cva(
    exposure::Float64,
    rating::AMBestRating;
    term_years::Int = 1,
    lgd::Float64 = DEFAULT_INSURANCE_LGD,
    risk_free_rate::Float64 = 0.05,
    state::Union{String, Nothing} = nothing,
    coverage_type::CoverageType = ANNUITY_DEFERRED
)::CVAResult
    # Validation
    exposure > 0 || error("CRITICAL: exposure must be > 0, got $exposure")
    term_years >= 1 || error("CRITICAL: term_years must be >= 1, got $term_years")
    (0.0 < lgd <= 1.0) || error("CRITICAL: lgd must be in (0, 1], got $lgd")

    # Get hazard rate and annual PD
    annual_pd = get_annual_pd(rating)
    hazard_rate = get_hazard_rate(rating)

    # Cumulative default probability over term
    # [T1] P(default by T) = 1 - exp(-h x T)
    cum_pd = isinf(hazard_rate) ? 1.0 : 1 - exp(-hazard_rate * term_years)

    # Average discount factor (simplified: use midpoint)
    avg_discount = exp(-risk_free_rate * term_years / 2)

    # Gross CVA (before guaranty adjustment)
    # [T1] CVA = LGD x EE x PD x DF
    cva_gross = lgd * exposure * cum_pd * avg_discount

    # Apply guaranty fund adjustment if state provided
    if !isnothing(state)
        covered = calculate_covered_amount(exposure, state, coverage_type)
        coverage_ratio = get_coverage_ratio(exposure, state, coverage_type)
        uncovered = exposure - covered

        # CVA only applies to uncovered portion
        cva_net = cva_gross * (1 - coverage_ratio)
        guaranty_adjustment = cva_gross - cva_net
    else
        covered = 0.0
        uncovered = exposure
        coverage_ratio = 0.0
        cva_net = cva_gross
        guaranty_adjustment = 0.0
    end

    CVAResult(
        cva_gross = cva_gross,
        cva_net = cva_net,
        guaranty_adjustment = guaranty_adjustment,
        expected_exposure = exposure,
        covered_exposure = covered,
        uncovered_exposure = uncovered,
        coverage_ratio = coverage_ratio,
        lgd = lgd,
        rating = rating,
        annual_pd = annual_pd
    )
end

"""
    calculate_cva_term_structure(exposure_profile::Vector{Float64}, rating::AMBestRating; kwargs...) -> Float64

Calculate CVA with full exposure term structure.

[T1] CVA = LGD x SUM_t(EE(t) x [Q(t) - Q(t-1)] x DF(t))

where Q(t) is cumulative default probability.

# Arguments
- `exposure_profile`: Expected exposure at each period
- `rating`: Insurer rating

# Keyword Arguments
- `lgd::Float64=DEFAULT_INSURANCE_LGD`: Loss given default
- `risk_free_rate::Float64=0.05`: Risk-free rate
- `periods_per_year::Int=1`: Number of periods per year

# Returns
- CVA value
"""
function calculate_cva_term_structure(
    exposure_profile::Vector{Float64},
    rating::AMBestRating;
    lgd::Float64 = DEFAULT_INSURANCE_LGD,
    risk_free_rate::Float64 = 0.05,
    periods_per_year::Int = 1
)::Float64
    isempty(exposure_profile) && error("CRITICAL: exposure_profile cannot be empty")

    hazard_rate = get_hazard_rate(rating)
    n_periods = length(exposure_profile)

    cva = 0.0
    for t in 1:n_periods
        # Time in years
        time_years = t / periods_per_year
        time_prev = (t - 1) / periods_per_year

        # Incremental default probability in period
        if isinf(hazard_rate)
            q_t = 1.0
            q_prev = t == 1 ? 0.0 : 1.0
        else
            q_t = 1 - exp(-hazard_rate * time_years)
            q_prev = 1 - exp(-hazard_rate * time_prev)
        end
        incremental_pd = q_t - q_prev

        # Discount factor
        df = exp(-risk_free_rate * time_years)

        # CVA contribution from this period
        cva += lgd * exposure_profile[t] * incremental_pd * df
    end

    cva
end

#=============================================================================
# Credit-Adjusted Pricing
=============================================================================#

"""
    calculate_credit_adjusted_price(base_price::Float64, rating::AMBestRating; kwargs...) -> Float64

Calculate credit-adjusted price for annuity.

[T1] Credit-adjusted price = Base price - CVA

# Arguments
- `base_price`: Base price without credit adjustment
- `rating`: Insurer AM Best rating

# Keyword Arguments
Same as `calculate_cva`

# Returns
- Credit-adjusted price

# Example
```julia
# 100k annuity from A-rated insurer in California
adj_price = calculate_credit_adjusted_price(
    100000.0, A,
    term_years = 5,
    state = "CA"
)
```
"""
function calculate_credit_adjusted_price(
    base_price::Float64,
    rating::AMBestRating;
    term_years::Int = 1,
    lgd::Float64 = DEFAULT_INSURANCE_LGD,
    risk_free_rate::Float64 = 0.05,
    state::Union{String, Nothing} = nothing,
    coverage_type::CoverageType = ANNUITY_DEFERRED
)::Float64
    cva_result = calculate_cva(
        base_price,
        rating,
        term_years = term_years,
        lgd = lgd,
        risk_free_rate = risk_free_rate,
        state = state,
        coverage_type = coverage_type
    )

    base_price - cva_result.cva_net
end

"""
    calculate_credit_spread(rating::AMBestRating; lgd::Float64=DEFAULT_INSURANCE_LGD) -> Float64

Calculate implied credit spread for rating.

[T1] Credit spread ≈ hazard_rate x LGD

# Arguments
- `rating`: Insurer rating
- `lgd`: Loss given default

# Returns
- Implied credit spread (decimal, per year)

# Example
```julia
spread = calculate_credit_spread(A)
println("\$(round(spread * 10000, digits=1)) bps")
```
"""
function calculate_credit_spread(
    rating::AMBestRating;
    lgd::Float64 = DEFAULT_INSURANCE_LGD
)::Float64
    hazard_rate = get_hazard_rate(rating)
    isinf(hazard_rate) ? 1.0 : hazard_rate * lgd
end

#=============================================================================
# CVA Sensitivity Analysis
=============================================================================#

"""
    cva_sensitivity_to_rating(exposure::Float64, ratings::Vector{AMBestRating}; kwargs...) -> Dict{AMBestRating, CVAResult}

Calculate CVA for multiple ratings.

Useful for understanding rating migration impact.
"""
function cva_sensitivity_to_rating(
    exposure::Float64,
    ratings::Vector{AMBestRating};
    term_years::Int = 1,
    lgd::Float64 = DEFAULT_INSURANCE_LGD,
    risk_free_rate::Float64 = 0.05,
    state::Union{String, Nothing} = nothing,
    coverage_type::CoverageType = ANNUITY_DEFERRED
)::Dict{AMBestRating, CVAResult}
    Dict(
        rating => calculate_cva(
            exposure, rating,
            term_years = term_years,
            lgd = lgd,
            risk_free_rate = risk_free_rate,
            state = state,
            coverage_type = coverage_type
        )
        for rating in ratings
    )
end

"""
    cva_sensitivity_to_term(exposure::Float64, rating::AMBestRating, terms::Vector{Int}; kwargs...) -> Dict{Int, CVAResult}

Calculate CVA for multiple terms.

Useful for understanding term structure impact.
"""
function cva_sensitivity_to_term(
    exposure::Float64,
    rating::AMBestRating,
    terms::Vector{Int};
    lgd::Float64 = DEFAULT_INSURANCE_LGD,
    risk_free_rate::Float64 = 0.05,
    state::Union{String, Nothing} = nothing,
    coverage_type::CoverageType = ANNUITY_DEFERRED
)::Dict{Int, CVAResult}
    Dict(
        term => calculate_cva(
            exposure, rating,
            term_years = term,
            lgd = lgd,
            risk_free_rate = risk_free_rate,
            state = state,
            coverage_type = coverage_type
        )
        for term in terms
    )
end

#=============================================================================
# Display Functions
=============================================================================#

"""
    print_cva_result(result::CVAResult; io::IO=stdout)

Print CVA result in formatted output.
"""
function print_cva_result(result::CVAResult; io::IO = stdout)
    rating_str = rating_to_string(result.rating)

    println(io, "Credit Valuation Adjustment (CVA)")
    println(io, "-" ^ 45)
    println(io, "Rating:              $rating_str")
    println(io, "Annual PD:           $(round(result.annual_pd * 100, digits=3))%")
    println(io, "LGD:                 $(round(result.lgd * 100, digits=0))%")
    println(io, "-" ^ 45)
    println(io, "Expected Exposure:   \$$(round(Int, result.expected_exposure))")
    println(io, "Covered Exposure:    \$$(round(Int, result.covered_exposure))")
    println(io, "Uncovered Exposure:  \$$(round(Int, result.uncovered_exposure))")
    println(io, "Coverage Ratio:      $(round(result.coverage_ratio * 100, digits=1))%")
    println(io, "-" ^ 45)
    println(io, "Gross CVA:           \$$(round(result.cva_gross, digits=2))")
    println(io, "Guaranty Adjustment: \$$(round(result.guaranty_adjustment, digits=2))")
    println(io, "Net CVA:             \$$(round(result.cva_net, digits=2))")
end

"""
    print_credit_spreads(ratings::Vector{AMBestRating}; lgd::Float64=DEFAULT_INSURANCE_LGD, io::IO=stdout)

Print credit spreads for multiple ratings.
"""
function print_credit_spreads(
    ratings::Vector{AMBestRating};
    lgd::Float64 = DEFAULT_INSURANCE_LGD,
    io::IO = stdout
)
    println(io, "Credit Spreads by Rating (LGD = $(round(lgd * 100, digits=0))%)")
    println(io, "-" ^ 35)
    println(io, rpad("Rating", 10), rpad("Spread (bps)", 15), "Grade")
    println(io, "-" ^ 35)

    for rating in ratings
        spread_bps = calculate_credit_spread(rating, lgd = lgd) * 10000
        rating_str = rating_to_string(rating)
        grade = is_secure(rating) ? "Secure" : "Vulnerable"

        println(io,
            rpad(rating_str, 10),
            rpad("$(round(spread_bps, digits=1))", 15),
            grade
        )
    end
end
