"""
RILA (Registered Index-Linked Annuity) Pricer.

Prices RILA products with partial downside protection:
- Buffer: Insurer absorbs FIRST X% of losses
- Floor: Insurer covers losses BEYOND X%

[T1] RILA can have negative returns (unlike FIA with 0% floor).
[T1] Buffer = Long ATM put - Short OTM put (put spread)
[T1] Floor = Long OTM put
"""

using StableRNGs
using Statistics: mean


"""
    price_rila(product, market, premium; kwargs...) -> RILAPricingResult

Price RILA product with buffer or floor protection.

[T1] Protection replication:
- Buffer (10%): Long ATM put, Short put at K=S×0.90
- Floor (-10%): Long put at K=S×0.90

# Arguments
- `product::RILAProduct`: RILA product specification
- `market::MarketParams`: Market parameters (spot, rate, div, vol)
- `premium::Real=100.0`: Premium amount for scaling
- `n_paths::Int=10000`: Number of Monte Carlo paths
- `seed::Union{Int, Nothing}=nothing`: Random seed for reproducibility

# Returns
- `RILAPricingResult`: Present value, protection metrics, expected return

# Example
```julia
market = MarketParams(100.0, 0.05, 0.02, 0.20)
product = RILAProduct(buffer_rate=0.10, cap_rate=0.20, is_buffer=true, term_years=1)
result = price_rila(product, market)
```
"""
function price_rila(
    product::RILAProduct{T},
    market::MarketParams{T},
    premium::Real = T(100);
    n_paths::Int = 10000,
    seed::Union{Int, Nothing} = nothing
) where T<:Real
    term = T(product.term_years)
    premium_t = T(premium)

    # Price protection component
    protection_value = _price_protection(product, market, term, premium_t)

    # Price upside (capped call)
    upside_value = _price_upside(product.cap_rate, market, term, premium_t)

    # Calculate expected return via MC
    expected_return = _calculate_rila_expected_return(product, market, term, n_paths, seed)

    # Max loss calculation
    if product.is_buffer
        buffer = product.buffer_rate
        max_loss = T(1.0) - buffer  # Dollar-for-dollar after buffer
    else
        max_loss = abs(product.floor_rate)  # Floor is max loss
    end

    # Breakeven calculation
    # Buffer: breakeven at -buffer_rate (buffer fully absorbs)
    # Floor: breakeven at 0 (any negative = loss)
    breakeven = product.is_buffer ? -product.buffer_rate : zero(T)

    # Risk-neutral PV
    r = market.risk_free_rate
    discount_factor = exp(-r * term)
    present_value = discount_factor * premium_t * (1 + expected_return)

    # Ensure non-negative PV (edge case with extreme parameters)
    present_value = max(present_value, zero(T))

    protection_type = product.is_buffer ? :buffer : :floor

    details = Dict{Symbol, Any}(
        :term_years => term,
        :premium => premium_t,
        :discount_factor => discount_factor,
        :is_buffer => product.is_buffer,
    )

    RILAPricingResult(
        present_value,
        protection_value,
        protection_type,
        upside_value,
        expected_return,
        max_loss,
        breakeven,
        details
    )
end


"""
    _price_protection(product, market, term, premium) -> Float64

Price the downside protection component.

[T1] Buffer = Long ATM put - Short OTM put (put spread)
[T1] Floor = Long OTM put
"""
function _price_protection(
    product::RILAProduct{T},
    market::MarketParams{T},
    term::T,
    premium::T
) where T<:Real
    S = market.spot
    r = market.risk_free_rate
    q = market.dividend_yield
    σ = market.volatility

    if product.is_buffer
        buffer_rate = product.buffer_rate

        # Handle 100% buffer edge case
        if buffer_rate >= 1.0 - 1e-10
            # 100% buffer = full ATM put protection
            atm_put = black_scholes_put(S, S, r, q, σ, term)
            protection = atm_put
        else
            # Buffer = Long ATM put - Short OTM put
            atm_put = black_scholes_put(S, S, r, q, σ, term)
            otm_strike = S * (1 - buffer_rate)
            otm_put = black_scholes_put(S, otm_strike, r, q, σ, term)
            protection = atm_put - otm_put
        end
    else
        # Floor = Long OTM put at floor strike
        floor_rate = product.floor_rate
        floor_strike = S * (1 + floor_rate)  # floor_rate is negative
        protection = black_scholes_put(S, floor_strike, r, q, σ, term)
    end

    return (protection / S) * premium
end


"""
    _price_upside(cap_rate, market, term, premium) -> Float64

Price the capped upside component.
"""
function _price_upside(
    cap_rate::Union{T, Nothing},
    market::MarketParams{T},
    term::T,
    premium::T
) where T<:Real
    S = market.spot
    r = market.risk_free_rate
    q = market.dividend_yield
    σ = market.volatility

    # ATM call for full upside
    atm_call = black_scholes_call(S, S, r, q, σ, term)

    if cap_rate !== nothing && cap_rate > 0
        # Capped call = ATM call - OTM call at cap
        cap_strike = S * (1 + cap_rate)
        otm_call = black_scholes_call(S, cap_strike, r, q, σ, term)
        upside = atm_call - otm_call
    else
        # Uncapped
        upside = atm_call
    end

    return (upside / S) * premium
end


"""
    _calculate_rila_expected_return(product, market, term, n_paths, seed) -> Float64

Calculate expected return via Monte Carlo simulation.
"""
function _calculate_rila_expected_return(
    product::RILAProduct{T},
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

    returns = zeros(T, n_paths)

    # Create appropriate payoff
    payoff = _create_rila_payoff(product)

    for i in 1:n_paths
        z = randn(rng)
        S_T = S * exp(drift + diffusion * z)
        index_return = (S_T - S) / S

        # Apply payoff
        result = calculate(payoff, index_return)
        returns[i] = result.credited_return
    end

    mean(returns)
end


"""
    _create_rila_payoff(product) -> AbstractPayoff

Create the appropriate RILA payoff object.
"""
function _create_rila_payoff(product::RILAProduct{T}) where T<:Real
    if product.is_buffer
        BufferPayoff(product.buffer_rate, product.cap_rate)
    else
        FloorPayoff(product.floor_rate, product.cap_rate)
    end
end


"""
    rila_greeks(product, market; term_years) -> NamedTuple

Calculate hedge Greeks for RILA protection.

[T1] Buffer = Long ATM put - Short OTM put (put spread)
[T1] Floor = Long OTM put

Returns the combined position Greeks.

# Arguments
- `product::RILAProduct`: RILA product
- `market::MarketParams`: Market parameters
- `term_years::Real=nothing`: Override term (uses product.term_years if nothing)

# Returns
- `NamedTuple`: (delta, gamma, vega, theta, rho, protection_type)
"""
function rila_greeks(
    product::RILAProduct{T},
    market::MarketParams{T};
    term_years::Union{Real, Nothing} = nothing
) where T<:Real
    term = term_years === nothing ? T(product.term_years) : T(term_years)

    S = market.spot
    r = market.risk_free_rate
    q = market.dividend_yield
    σ = market.volatility

    if product.is_buffer
        buffer_rate = product.buffer_rate

        if buffer_rate >= 1.0 - 1e-10
            # 100% buffer = ATM put only
            atm_greeks = black_scholes_greeks(S, S, r, q, σ, term)

            return (
                delta = -atm_greeks.delta,  # Put delta is negative
                gamma = atm_greeks.gamma,
                vega = atm_greeks.vega,
                theta = -atm_greeks.theta,  # Time decay sign adjustment
                rho = -atm_greeks.rho,
                protection_type = :buffer
            )
        else
            # Buffer = Long ATM put - Short OTM put
            atm_greeks = black_scholes_greeks(S, S, r, q, σ, term)
            otm_strike = S * (1 - buffer_rate)
            otm_greeks = black_scholes_greeks(S, otm_strike, r, q, σ, term)

            # Net Greeks: Long ATM - Short OTM
            # Note: black_scholes_greeks returns call Greeks by default
            # For puts: delta_put = delta_call - 1 (approximately)
            d1_atm, _ = _calculate_d1_d2(S, S, r, q, σ, term)
            d1_otm, _ = _calculate_d1_d2(S, otm_strike, r, q, σ, term)

            # Put deltas
            put_delta_atm = _cdf_normal(d1_atm) - 1
            put_delta_otm = _cdf_normal(d1_otm) - 1

            return (
                delta = put_delta_atm - put_delta_otm,
                gamma = atm_greeks.gamma - otm_greeks.gamma,
                vega = atm_greeks.vega - otm_greeks.vega,
                theta = atm_greeks.theta - otm_greeks.theta,
                rho = atm_greeks.rho - otm_greeks.rho,
                protection_type = :buffer
            )
        end
    else
        # Floor = Long OTM put
        floor_rate = product.floor_rate
        floor_strike = S * (1 + floor_rate)  # floor_rate is negative

        otm_greeks = black_scholes_greeks(S, floor_strike, r, q, σ, term)

        d1_otm, _ = _calculate_d1_d2(S, floor_strike, r, q, σ, term)
        put_delta_otm = _cdf_normal(d1_otm) - 1

        return (
            delta = put_delta_otm,
            gamma = otm_greeks.gamma,
            vega = otm_greeks.vega,
            theta = otm_greeks.theta,
            rho = otm_greeks.rho,
            protection_type = :floor
        )
    end
end


"""
    compare_buffer_vs_floor(market, buffer_rate, floor_rate, cap_rate, term_years; kwargs...) -> NamedTuple

Compare buffer vs floor protection for same protection level.

# Arguments
- `market::MarketParams`: Market parameters
- `buffer_rate::Real`: Buffer protection level (e.g., 0.10 for 10%)
- `floor_rate::Real`: Floor protection level (e.g., -0.10 for -10% floor)
- `cap_rate::Real`: Cap rate for both
- `term_years::Int`: Investment term

# Returns
- `NamedTuple`: Comparison metrics for buffer and floor
"""
function compare_buffer_vs_floor(
    market::MarketParams{T},
    buffer_rate::Real,
    floor_rate::Real,
    cap_rate::Real,
    term_years::Int;
    n_paths::Int = 10000,
    seed::Union{Int, Nothing} = nothing
) where T<:Real
    buffer_product = RILAProduct{T}(
        T(buffer_rate), nothing, T(cap_rate), true, term_years, "", "Buffer"
    )

    floor_product = RILAProduct{T}(
        nothing, T(floor_rate), T(cap_rate), false, term_years, "", "Floor"
    )

    buffer_result = price_rila(buffer_product, market; n_paths=n_paths, seed=seed)
    floor_result = price_rila(floor_product, market; n_paths=n_paths, seed=seed)

    (
        buffer = (
            protection_value = buffer_result.protection_value,
            upside_value = buffer_result.upside_value,
            expected_return = buffer_result.expected_return,
            max_loss = buffer_result.max_loss,
            present_value = buffer_result.present_value,
        ),
        floor = (
            protection_value = floor_result.protection_value,
            upside_value = floor_result.upside_value,
            expected_return = floor_result.expected_return,
            max_loss = floor_result.max_loss,
            present_value = floor_result.present_value,
        )
    )
end
