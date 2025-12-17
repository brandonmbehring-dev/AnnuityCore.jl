"""
Black-Scholes option pricing with Greeks.

Implements the Black-Scholes-Merton formula for European options.
Parametric types enable automatic differentiation support.

References:
- [T1] Black, F. & Scholes, M. (1973). "The Pricing of Options and Corporate Liabilities"
- [T1] Hull, J.C. (2021). "Options, Futures, and Other Derivatives", Ch. 15
"""

"""
    BSGreeks{T}

Container for Black-Scholes Greeks.

# Fields
- `delta::T`: ∂V/∂S (sensitivity to spot price)
- `gamma::T`: ∂²V/∂S² (convexity in spot)
- `vega::T`: ∂V/∂σ (sensitivity to volatility, in % terms)
- `theta::T`: ∂V/∂t (time decay, per year)
- `rho::T`: ∂V/∂r (sensitivity to interest rate, in % terms)
"""
struct BSGreeks{T<:Real}
    delta::T
    gamma::T
    vega::T
    theta::T
    rho::T
end

const N = Normal()

"""
    black_scholes_call(S, K, r, q, σ, τ) -> price

Price a European call option using Black-Scholes-Merton formula.

[T1] From Hull (2021), Eq. 15.20:
    C = S·e^(-qτ)·N(d₁) - K·e^(-rτ)·N(d₂)

where:
    d₁ = [ln(S/K) + (r - q + σ²/2)τ] / (σ√τ)
    d₂ = d₁ - σ√τ

# Arguments
- `S::Real`: Spot price
- `K::Real`: Strike price
- `r::Real`: Risk-free rate (continuous, decimal)
- `q::Real`: Dividend yield (continuous, decimal)
- `σ::Real`: Volatility (decimal, e.g., 0.20 for 20%)
- `τ::Real`: Time to expiry (years)

# Returns
- `Float64`: Call option price

# Example
```julia
# Hull Example 15.6: S=42, K=40, r=0.10, q=0, σ=0.20, T=0.5
julia> black_scholes_call(42.0, 40.0, 0.10, 0.0, 0.20, 0.5)
4.759422... # Expected: 4.7594
```
"""
function black_scholes_call(S::T, K::T, r::T, q::T, σ::T, τ::T) where T<:Real
    # Handle edge case: expired option
    if τ <= 0
        return max(S - K, zero(T))
    end

    # Handle edge case: zero volatility
    if σ <= 0
        df = exp(-r * τ)
        fwd = S * exp((r - q) * τ)
        return df * max(fwd - K, zero(T))
    end

    sqrt_τ = sqrt(τ)
    d1 = (log(S / K) + (r - q + σ^2 / 2) * τ) / (σ * sqrt_τ)
    d2 = d1 - σ * sqrt_τ

    return S * exp(-q * τ) * cdf(N, d1) - K * exp(-r * τ) * cdf(N, d2)
end

# Convenience method for mixed numeric types
function black_scholes_call(S, K, r, q, σ, τ)
    T = promote_type(typeof(S), typeof(K), typeof(r), typeof(q), typeof(σ), typeof(τ))
    black_scholes_call(T(S), T(K), T(r), T(q), T(σ), T(τ))
end


"""
    black_scholes_put(S, K, r, q, σ, τ) -> price

Price a European put option using Black-Scholes-Merton formula.

[T1] From Hull (2021), Eq. 15.21:
    P = K·e^(-rτ)·N(-d₂) - S·e^(-qτ)·N(-d₁)

# Arguments
Same as `black_scholes_call`

# Returns
- `Float64`: Put option price

# Example
```julia
# Hull Example 15.6: S=42, K=40, r=0.10, q=0, σ=0.20, T=0.5
julia> black_scholes_put(42.0, 40.0, 0.10, 0.0, 0.20, 0.5)
0.808600... # Expected: 0.8086
```
"""
function black_scholes_put(S::T, K::T, r::T, q::T, σ::T, τ::T) where T<:Real
    # Handle edge case: expired option
    if τ <= 0
        return max(K - S, zero(T))
    end

    # Handle edge case: zero volatility
    if σ <= 0
        df = exp(-r * τ)
        fwd = S * exp((r - q) * τ)
        return df * max(K - fwd, zero(T))
    end

    sqrt_τ = sqrt(τ)
    d1 = (log(S / K) + (r - q + σ^2 / 2) * τ) / (σ * sqrt_τ)
    d2 = d1 - σ * sqrt_τ

    return K * exp(-r * τ) * cdf(N, -d2) - S * exp(-q * τ) * cdf(N, -d1)
end

# Convenience method for mixed numeric types
function black_scholes_put(S, K, r, q, σ, τ)
    T = promote_type(typeof(S), typeof(K), typeof(r), typeof(q), typeof(σ), typeof(τ))
    black_scholes_put(T(S), T(K), T(r), T(q), T(σ), T(τ))
end


"""
    black_scholes_greeks(S, K, r, q, σ, τ; is_call=true) -> BSGreeks

Calculate all Black-Scholes Greeks for a European option.

[T1] From Hull (2021), Chapter 19:
- Delta (call) = e^(-qτ)·N(d₁)
- Delta (put) = e^(-qτ)·[N(d₁) - 1]
- Gamma = e^(-qτ)·n(d₁) / (S·σ·√τ)
- Vega = S·e^(-qτ)·n(d₁)·√τ / 100
- Theta (call) = -(S·σ·e^(-qτ)·n(d₁))/(2√τ) - r·K·e^(-rτ)·N(d₂) + q·S·e^(-qτ)·N(d₁)
- Theta (put) = -(S·σ·e^(-qτ)·n(d₁))/(2√τ) + r·K·e^(-rτ)·N(-d₂) - q·S·e^(-qτ)·N(-d₁)
- Rho (call) = K·τ·e^(-rτ)·N(d₂) / 100
- Rho (put) = -K·τ·e^(-rτ)·N(-d₂) / 100

# Arguments
- `S, K, r, q, σ, τ`: Same as `black_scholes_call`
- `is_call::Bool=true`: True for call Greeks, false for put Greeks

# Returns
- `BSGreeks`: Named tuple with (delta, gamma, vega, theta, rho)

# Notes
- Vega is per 1% move in volatility (multiply by 0.01 for 1pp move)
- Rho is per 1% move in rate (multiply by 0.01 for 1pp move)
- Theta is annualized (divide by 365 for daily decay)
"""
function black_scholes_greeks(S::T, K::T, r::T, q::T, σ::T, τ::T; is_call::Bool=true) where T<:Real
    if τ <= 0 || σ <= 0
        # At expiry or zero vol, return limiting Greeks
        intrinsic = is_call ? max(S - K, zero(T)) : max(K - S, zero(T))
        in_the_money = intrinsic > 0

        delta = is_call ? (in_the_money ? one(T) : zero(T)) : (in_the_money ? -one(T) : zero(T))
        return BSGreeks(delta, zero(T), zero(T), zero(T), zero(T))
    end

    sqrt_τ = sqrt(τ)
    d1 = (log(S / K) + (r - q + σ^2 / 2) * τ) / (σ * sqrt_τ)
    d2 = d1 - σ * sqrt_τ

    # PDF of standard normal at d1
    n_d1 = pdf(N, d1)

    # Discount factors
    exp_qt = exp(-q * τ)
    exp_rt = exp(-r * τ)

    # Gamma and Vega are same for calls and puts
    gamma = exp_qt * n_d1 / (S * σ * sqrt_τ)
    vega = S * exp_qt * n_d1 * sqrt_τ / 100  # Per 1% vol move

    if is_call
        Nd1 = cdf(N, d1)
        Nd2 = cdf(N, d2)

        delta = exp_qt * Nd1
        theta = -(S * σ * exp_qt * n_d1) / (2 * sqrt_τ) -
                r * K * exp_rt * Nd2 +
                q * S * exp_qt * Nd1
        rho = K * τ * exp_rt * Nd2 / 100  # Per 1% rate move
    else
        Nmd1 = cdf(N, -d1)
        Nmd2 = cdf(N, -d2)

        delta = exp_qt * (cdf(N, d1) - 1)
        theta = -(S * σ * exp_qt * n_d1) / (2 * sqrt_τ) +
                r * K * exp_rt * Nmd2 -
                q * S * exp_qt * Nmd1
        rho = -K * τ * exp_rt * Nmd2 / 100  # Per 1% rate move
    end

    return BSGreeks(delta, gamma, vega, theta, rho)
end

# Convenience method for mixed numeric types
function black_scholes_greeks(S, K, r, q, σ, τ; is_call::Bool=true)
    T = promote_type(typeof(S), typeof(K), typeof(r), typeof(q), typeof(σ), typeof(τ))
    black_scholes_greeks(T(S), T(K), T(r), T(q), T(σ), T(τ); is_call=is_call)
end
