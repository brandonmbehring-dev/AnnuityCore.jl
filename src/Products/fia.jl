"""
FIA (Fixed Indexed Annuity) Pricer.

Prices FIA products with embedded index-linked options:
- Cap: Point-to-point with maximum return cap
- Participation: Partial participation in index returns
- Spread: Index return minus spread/margin
- Trigger: Performance triggered bonus

[T1] FIA products have 0% floor (principal protection).
[T1] FIA = Bond + Call Option portfolio
"""

using Distributions: Normal, cdf
using StableRNGs
using Statistics: mean


"""
    price_fia(product, market, premium; kwargs...) -> FIAPricingResult

Price FIA product with embedded index-linked option.

[T1] FIA valuation components:
- Capped call = ATM call - OTM call at cap
- Participation = par_rate × ATM call
- Spread = OTM call at spread strike
- Trigger = Digital option × trigger rate

# Arguments
- `product::FIAProduct`: FIA product specification
- `market::MarketParams`: Market parameters (spot, rate, div, vol)
- `premium::Real=100.0`: Premium amount for scaling
- `option_budget_pct::Real=0.03`: Option budget as % of premium (e.g., 0.03 = 3%)
- `n_paths::Int=10000`: Number of Monte Carlo paths
- `seed::Union{Int, Nothing}=nothing`: Random seed for reproducibility

# Returns
- `FIAPricingResult`: Present value, option metrics, fair terms

# Example
```julia
market = MarketParams(100.0, 0.05, 0.02, 0.20)
product = FIAProduct(cap_rate=0.10, term_years=1)
result = price_fia(product, market)
```
"""
function price_fia(
    product::FIAProduct{T},
    market::MarketParams{T},
    premium::Real = T(100);
    option_budget_pct::Real = T(0.03),
    n_paths::Int = 10000,
    seed::Union{Int, Nothing} = nothing
) where T<:Real
    term = T(product.term_years)
    premium_t = T(premium)
    budget_pct = T(option_budget_pct)

    # Calculate option budget (time-value adjusted annuity factor)
    r = market.risk_free_rate
    if r > 1e-8
        annuity_factor = (1 - (1 + r)^(-term)) / r
    else
        annuity_factor = term
    end
    option_budget = premium_t * budget_pct * annuity_factor

    # Price embedded option based on crediting method
    embedded_option_value = _price_fia_option(product, market, term, premium_t)

    # Calculate expected credit via Monte Carlo
    expected_credit = _calculate_fia_expected_credit(product, market, term, n_paths, seed)

    # Solve for fair terms given option budget
    fair_cap = _solve_fair_cap(market, term, option_budget, premium_t)
    fair_participation = _solve_fair_participation(market, term, option_budget, premium_t)

    # Risk-neutral PV: e^(-rT) × Premium × (1 + E[credit])
    discount_factor = exp(-r * term)
    present_value = discount_factor * premium_t * (1 + expected_credit)

    details = Dict{Symbol, Any}(
        :term_years => term,
        :premium => premium_t,
        :discount_factor => discount_factor,
        :option_budget_pct => budget_pct,
        :annuity_factor => annuity_factor,
    )

    FIAPricingResult(
        present_value,
        embedded_option_value,
        option_budget,
        fair_cap,
        fair_participation,
        expected_credit,
        details
    )
end


"""
    _price_fia_option(product, market, term, premium) -> Float64

Price the embedded option based on crediting method.
"""
function _price_fia_option(
    product::FIAProduct{T},
    market::MarketParams{T},
    term::T,
    premium::T
) where T<:Real
    S = market.spot
    r = market.risk_free_rate
    q = market.dividend_yield
    σ = market.volatility

    # ATM call value
    atm_call = black_scholes_call(S, S, r, q, σ, term)

    if product.cap_rate !== nothing
        # Capped call = ATM call - OTM call at cap
        cap = product.cap_rate
        if cap > 0
            cap_strike = S * (1 + cap)
            otm_call = black_scholes_call(S, cap_strike, r, q, σ, term)
            capped_call_value = atm_call - otm_call
        else
            capped_call_value = zero(T)
        end
        return (capped_call_value / S) * premium

    elseif product.participation_rate !== nothing
        # Participation = par_rate × ATM call
        par_rate = product.participation_rate
        return par_rate * (atm_call / S) * premium

    elseif product.spread_rate !== nothing
        # Spread: OTM call with effective strike
        spread = product.spread_rate
        effective_strike = S * (1 + spread)
        spread_call = black_scholes_call(S, effective_strike, r, q, σ, term)
        return (spread_call / S) * premium

    elseif product.trigger_rate !== nothing
        # Trigger: Digital option approximation
        # PV = e^(-rT) × N(d2) × trigger_rate × premium
        trigger_rate = product.trigger_rate
        d1, d2 = _calculate_d1_d2(S, S, r, q, σ, term)
        prob_itm = _cdf_normal(d2)
        df = exp(-r * term)
        return df * trigger_rate * premium * prob_itm
    else
        return zero(T)
    end
end


"""
    _calculate_fia_expected_credit(product, market, term, n_paths, seed) -> Float64

Calculate expected credit via Monte Carlo simulation.
"""
function _calculate_fia_expected_credit(
    product::FIAProduct{T},
    market::MarketParams{T},
    term::T,
    n_paths::Int,
    seed::Union{Int, Nothing}
) where T<:Real
    rng = seed === nothing ? StableRNG(42) : StableRNG(seed)

    S = market.spot
    r = market.risk_free_rate
    q = market.dividend_yield
    σ = market.volatility

    # Generate terminal values (GBM)
    drift = (r - q - 0.5 * σ^2) * term
    diffusion = σ * sqrt(term)

    credits = zeros(T, n_paths)

    # Create appropriate payoff
    payoff = _create_fia_payoff(product)

    for i in 1:n_paths
        z = randn(rng)
        S_T = S * exp(drift + diffusion * z)
        index_return = (S_T - S) / S

        # Apply payoff
        result = calculate(payoff, index_return)
        credits[i] = result.credited_return
    end

    mean(credits)
end


"""
    _create_fia_payoff(product) -> AbstractPayoff

Create the appropriate FIA payoff object.
"""
function _create_fia_payoff(product::FIAProduct{T}) where T<:Real
    if product.cap_rate !== nothing
        CappedCallPayoff(product.cap_rate)
    elseif product.participation_rate !== nothing
        cap = product.cap_rate === nothing ? nothing : product.cap_rate
        ParticipationPayoff(product.participation_rate; cap_rate=cap)
    elseif product.spread_rate !== nothing
        cap = product.cap_rate === nothing ? nothing : product.cap_rate
        SpreadPayoff(product.spread_rate; cap_rate=cap)
    elseif product.trigger_rate !== nothing
        TriggerPayoff(product.trigger_rate)
    else
        CappedCallPayoff(T(1.0))  # Default: uncapped (100% cap)
    end
end


"""
    _solve_fair_cap(market, term, option_budget, premium) -> Float64

Solve for fair cap rate given option budget via binary search.

[T1] Find cap such that capped_call_value = option_budget
"""
function _solve_fair_cap(
    market::MarketParams{T},
    term::T,
    option_budget::T,
    premium::T;
    tol::Real = 1e-6,
    max_iter::Int = 50
) where T<:Real
    S = market.spot
    r = market.risk_free_rate
    q = market.dividend_yield
    σ = market.volatility

    # ATM call value
    atm_call = black_scholes_call(S, S, r, q, σ, term)
    atm_call_pct = atm_call / S

    # Budget as percentage of premium
    budget_pct = option_budget / premium

    # If budget >= ATM call, can offer unlimited cap
    if budget_pct >= atm_call_pct
        return T(1.0)  # 100% cap = effectively unlimited
    end

    # Binary search for cap rate
    low = T(0.01)
    high = T(1.0)
    target = budget_pct

    for _ in 1:max_iter
        mid = (low + high) / 2
        cap_strike = S * (1 + mid)
        otm_call = black_scholes_call(S, cap_strike, r, q, σ, term)
        capped_value = (atm_call - otm_call) / S

        if abs(capped_value - target) < tol
            return mid
        elseif capped_value > target
            high = mid  # Cap too high, reduce it
        else
            low = mid   # Cap too low, increase it
        end
    end

    return (low + high) / 2
end


"""
    _solve_fair_participation(market, term, option_budget, premium) -> Float64

Solve for fair participation rate given option budget.

[T1] Participation = option_budget / ATM_call_value
"""
function _solve_fair_participation(
    market::MarketParams{T},
    term::T,
    option_budget::T,
    premium::T
) where T<:Real
    S = market.spot
    r = market.risk_free_rate
    q = market.dividend_yield
    σ = market.volatility

    # ATM call value
    atm_call = black_scholes_call(S, S, r, q, σ, term)
    atm_call_pct = atm_call / S

    if atm_call_pct < 1e-10
        return zero(T)
    end

    # Budget as percentage
    budget_pct = option_budget / premium

    # Participation = budget / ATM call
    participation = budget_pct / atm_call_pct

    return participation
end


"""
    _calculate_d1_d2(S, K, r, q, σ, T) -> Tuple{Float64, Float64}

Calculate d1 and d2 for Black-Scholes formula.
"""
function _calculate_d1_d2(S::T, K::T, r::T, q::T, σ::T, τ::T) where T<:Real
    if τ <= 0 || σ <= 0
        return (zero(T), zero(T))
    end

    d1 = (log(S / K) + (r - q + 0.5 * σ^2) * τ) / (σ * sqrt(τ))
    d2 = d1 - σ * sqrt(τ)

    return (d1, d2)
end


"""
    _cdf_normal(x) -> Float64

Standard normal cumulative distribution function.
"""
function _cdf_normal(x::Real)
    cdf(Normal(), x)
end
