"""
COS Method for Heston Option Pricing.

[T1] The COS method (Fang & Oosterlee, 2008) uses Fourier-cosine series
expansion for efficient option pricing. Key advantages:
- O(N) complexity vs O(N log N) for FFT methods
- Exponential convergence for smooth densities
- Excellent for European options under Heston

The method approximates:
    V(x, t) ≈ exp(-rτ) Σ Re[φ(kπ/b-a) × exp(-ikπa/(b-a))] × V_k

References:
- Fang & Oosterlee (2008), "A Novel Pricing Method for European Options
  Based on Fourier-Cosine Series Expansions"
"""


"""
    COSConfig

Configuration for COS method pricing.

# Fields
- `N::Int`: Number of Fourier terms (default 256)
- `L::Float64`: Integration range parameter (default 10.0)

Higher N gives more accuracy, larger L captures more tail probability.
"""
struct COSConfig
    N::Int
    L::Float64

    function COSConfig(; N::Int = 256, L::Float64 = 10.0)
        N > 0 || throw(ArgumentError("N must be positive"))
        L > 0 || throw(ArgumentError("L must be positive"))
        new(N, L)
    end
end


"""
    heston_cos_call(params::HestonParams, K; config=COSConfig()) -> Float64

Price a European call under Heston using the COS method.

[T1] Achieves near-machine precision with N ≈ 64-256 terms.

# Arguments
- `params::HestonParams`: Heston model parameters
- `K::Float64`: Strike price
- `config::COSConfig=COSConfig()`: COS method configuration

# Returns
- `Float64`: Call option price

# Example
```julia
params = HestonParams(S₀=100.0, r=0.05, q=0.0, V₀=0.04, κ=2.0, θ=0.04, σ_v=0.3, ρ=-0.7, τ=1.0)
price = heston_cos_call(params, 100.0)
```
"""
function heston_cos_call(
    params::HestonParams,
    K::Float64;
    config::COSConfig = COSConfig()
)
    K > 0 || throw(ArgumentError("Strike K must be positive"))

    # Log-moneyness
    x = log(params.S₀ / K)

    # Compute truncation range [a, b]
    c1, c2, c4 = _heston_cumulants(params)
    a, b = _cos_truncation_range(c1, c2, c4, config.L)

    # COS expansion
    price = _cos_call_price(params, K, x, a, b, config.N)

    return max(price, 0.0)
end


"""
    heston_cos_put(params::HestonParams, K; config=COSConfig()) -> Float64

Price a European put under Heston using the COS method.
"""
function heston_cos_put(
    params::HestonParams,
    K::Float64;
    config::COSConfig = COSConfig()
)
    K > 0 || throw(ArgumentError("Strike K must be positive"))

    x = log(params.S₀ / K)
    c1, c2, c4 = _heston_cumulants(params)
    a, b = _cos_truncation_range(c1, c2, c4, config.L)

    price = _cos_put_price(params, K, x, a, b, config.N)

    return max(price, 0.0)
end


"""
Compute cumulants of log-spot under Heston.

[T1] Used to determine optimal truncation range.
"""
function _heston_cumulants(params::HestonParams)
    r, q, τ = params.r, params.q, params.τ
    V₀, κ, θ, σ_v, ρ = params.V₀, params.κ, params.θ, params.σ_v, params.ρ

    # First cumulant (mean of log-spot)
    c1 = (r - q) * τ + (1 - exp(-κ * τ)) * (θ - V₀) / (2 * κ) - 0.5 * θ * τ

    # Second cumulant (variance)
    c2 = (1 / (8 * κ^3)) * (
        σ_v * τ * κ * exp(-κ * τ) * (V₀ - θ) * (8 * κ * ρ - 4 * σ_v) +
        κ * ρ * σ_v * (1 - exp(-κ * τ)) * (16 * θ - 8 * V₀) +
        2 * θ * κ * τ * (-4 * κ * ρ * σ_v + σ_v^2 + 4 * κ^2) +
        σ_v^2 * ((θ - 2 * V₀) * exp(-2 * κ * τ) + θ * (6 * exp(-κ * τ) - 7) + 2 * V₀) +
        8 * κ^2 * (V₀ - θ) * (1 - exp(-κ * τ))
    )

    # Fourth cumulant (approximation for tail behavior)
    c4 = 0.0  # Can be computed but c2 usually sufficient

    return c1, max(c2, 1e-10), c4
end


"""
Determine truncation range [a, b] for COS method.

[T1] Range should capture most of the probability mass.
"""
function _cos_truncation_range(c1, c2, c4, L)
    # Use cumulants to set range
    # Standard approach: [c1 - L*sqrt(c2), c1 + L*sqrt(c2)]
    std_dev = sqrt(c2)

    a = c1 - L * std_dev
    b = c1 + L * std_dev

    return a, b
end


"""
COS method call price computation.

[T1] Fang & Oosterlee (2008) COS method for European call.

For call: v(x) = (exp(x) - 1)^+ where x = log(S/K)
"""
function _cos_call_price(params::HestonParams, K, x, a, b, N)
    S₀, r, q, τ = params.S₀, params.r, params.q, params.τ

    # Discount factor
    df = exp(-r * τ)
    bma = b - a

    # Sum over k
    sum_val = 0.0

    for k in 0:N-1
        # Payoff coefficients U_k for call
        # U_k = (2/(b-a)) * (χ_k(0,b) - ψ_k(0,b))
        χ_k = _chi_call(k, a, b)
        ψ_k = _psi_call(k, a, b)
        U_k = (2 / bma) * (χ_k - ψ_k)

        # Characteristic function F_k
        # F_k = Re[φ(kπ/(b-a)) × exp(ikπ(x-a)/(b-a))]
        ω = k * π / bma
        cf = heston_characteristic_function(ω, params)

        # Phase factor
        phase = exp(im * ω * (x - a))
        F_k = real(cf * phase)

        if k == 0
            sum_val += 0.5 * U_k * F_k
        else
            sum_val += U_k * F_k
        end
    end

    return K * df * sum_val
end


"""
COS method put price computation.
"""
function _cos_put_price(params::HestonParams, K, x, a, b, N)
    S₀, r, q, τ = params.S₀, params.r, params.q, params.τ

    df = exp(-r * τ)
    bma = b - a

    sum_val = 0.0

    for k in 0:N-1
        # Payoff coefficients for put
        # U_k = (2/(b-a)) * (ψ_k(a,0) - χ_k(a,0))
        χ_k = _chi_put(k, a, b)
        ψ_k = _psi_put(k, a, b)
        U_k = (2 / bma) * (ψ_k - χ_k)

        ω = k * π / bma
        cf = heston_characteristic_function(ω, params)
        phase = exp(im * ω * (x - a))
        F_k = real(cf * phase)

        if k == 0
            sum_val += 0.5 * U_k * F_k
        else
            sum_val += U_k * F_k
        end
    end

    return K * df * sum_val
end


"""
χ coefficient for call payoff (integration from 0 to b).
"""
function _chi_call(k, a, b)
    bma = b - a
    if k == 0
        return exp(b) - 1.0
    end
    ω = k * π / bma
    # ∫_0^b exp(y) cos(kπ(y-a)/(b-a)) dy
    num = exp(b) * (cos(ω * (b - a)) + ω * sin(ω * (b - a))) -
          exp(0.0) * (cos(ω * (0 - a)) + ω * sin(ω * (0 - a)))
    return num / (1 + ω^2)
end


"""
ψ coefficient for call payoff (integration from 0 to b).
"""
function _psi_call(k, a, b)
    bma = b - a
    if k == 0
        return b - 0.0
    end
    ω = k * π / bma
    # ∫_0^b cos(kπ(y-a)/(b-a)) dy
    return (sin(ω * (b - a)) - sin(ω * (0 - a))) / ω
end


"""
χ coefficient for put payoff (integration from a to 0).
"""
function _chi_put(k, a, b)
    bma = b - a
    if k == 0
        return 1.0 - exp(a)
    end
    ω = k * π / bma
    num = exp(0.0) * (cos(ω * (0 - a)) + ω * sin(ω * (0 - a))) -
          exp(a) * (cos(ω * (a - a)) + ω * sin(ω * (a - a)))
    return num / (1 + ω^2)
end


"""
ψ coefficient for put payoff (integration from a to 0).
"""
function _psi_put(k, a, b)
    bma = b - a
    if k == 0
        return 0.0 - a
    end
    ω = k * π / bma
    return (sin(ω * (0 - a)) - sin(ω * (a - a))) / ω
end




"""
    heston_cos_greeks(params::HestonParams, K; config=COSConfig()) -> NamedTuple

Compute Greeks under Heston using COS method with finite differences.

# Returns
NamedTuple with: delta, gamma, vega, theta, rho
"""
function heston_cos_greeks(
    params::HestonParams,
    K::Float64;
    config::COSConfig = COSConfig()
)
    # Base price
    price = heston_cos_call(params, K; config=config)

    # Delta and Gamma (spot sensitivity)
    ε_S = params.S₀ * 0.01
    params_up = HestonParams(
        S₀ = params.S₀ + ε_S, r = params.r, q = params.q,
        V₀ = params.V₀, κ = params.κ, θ = params.θ,
        σ_v = params.σ_v, ρ = params.ρ, τ = params.τ
    )
    params_dn = HestonParams(
        S₀ = params.S₀ - ε_S, r = params.r, q = params.q,
        V₀ = params.V₀, κ = params.κ, θ = params.θ,
        σ_v = params.σ_v, ρ = params.ρ, τ = params.τ
    )

    price_up = heston_cos_call(params_up, K; config=config)
    price_dn = heston_cos_call(params_dn, K; config=config)

    delta = (price_up - price_dn) / (2 * ε_S)
    gamma = (price_up - 2 * price + price_dn) / (ε_S^2)

    # Vega (V₀ sensitivity, scaled to 1% vol change)
    ε_V = 0.0001  # Small variance bump
    params_v_up = HestonParams(
        S₀ = params.S₀, r = params.r, q = params.q,
        V₀ = params.V₀ + ε_V, κ = params.κ, θ = params.θ,
        σ_v = params.σ_v, ρ = params.ρ, τ = params.τ
    )
    price_v_up = heston_cos_call(params_v_up, K; config=config)
    vega = (price_v_up - price) / ε_V * 0.01  # Per 1% vol

    # Theta (time decay)
    ε_τ = 1 / 365  # One day
    if params.τ > ε_τ
        params_tau = HestonParams(
            S₀ = params.S₀, r = params.r, q = params.q,
            V₀ = params.V₀, κ = params.κ, θ = params.θ,
            σ_v = params.σ_v, ρ = params.ρ, τ = params.τ - ε_τ
        )
        price_tau = heston_cos_call(params_tau, K; config=config)
        theta = -(price_tau - price) / ε_τ * (1 / 365)  # Daily theta
    else
        theta = 0.0
    end

    # Rho (rate sensitivity)
    ε_r = 0.0001
    params_r_up = HestonParams(
        S₀ = params.S₀, r = params.r + ε_r, q = params.q,
        V₀ = params.V₀, κ = params.κ, θ = params.θ,
        σ_v = params.σ_v, ρ = params.ρ, τ = params.τ
    )
    price_r_up = heston_cos_call(params_r_up, K; config=config)
    rho = (price_r_up - price) / ε_r * 0.01  # Per 1% rate

    return (
        delta = delta,
        gamma = gamma,
        vega = vega,
        theta = theta,
        rho = rho,
        price = price
    )
end


"""
    heston_smile_cos(params::HestonParams, strikes; config=COSConfig()) -> Vector{Float64}

Compute implied volatility smile from Heston COS prices.

# Arguments
- `params::HestonParams`: Heston parameters
- `strikes::Vector{Float64}`: Strike prices
- `config::COSConfig=COSConfig()`: COS configuration

# Returns
- `Vector{Float64}`: Implied volatilities for each strike
"""
function heston_smile_cos(
    params::HestonParams,
    strikes::Vector{Float64};
    config::COSConfig = COSConfig()
)
    impl_vols = Float64[]

    for K in strikes
        price = heston_cos_call(params, K; config=config)

        # Invert Black-Scholes to get implied vol
        σ = _invert_bs_for_iv(
            price, params.S₀, K, params.r, params.q, params.τ
        )
        push!(impl_vols, σ)
    end

    return impl_vols
end


"""
Invert Black-Scholes formula to get implied volatility.
"""
function _invert_bs_for_iv(price, S, K, r, q, τ; max_iter=50, tol=1e-8)
    # Initial guess from Brenner-Subrahmanyam approximation
    σ = sqrt(2 * abs(log(S / K) + (r - q) * τ) / τ)
    σ = clamp(σ, 0.01, 2.0)

    for _ in 1:max_iter
        bs_price = black_scholes_call(S, K, r, q, σ, τ)
        vega = black_scholes_greeks(S, K, r, q, σ, τ).vega * 100

        diff = bs_price - price
        if abs(diff) < tol
            break
        end

        # Newton step
        σ = σ - diff / (vega + 1e-10)
        σ = clamp(σ, 0.001, 3.0)
    end

    return σ
end


"""
    benchmark_cos_vs_mc(params::HestonParams, K; n_mc_paths=100000) -> NamedTuple

Compare COS method vs Monte Carlo for validation.

# Returns
NamedTuple with: cos_price, mc_price, mc_std_error, abs_diff, rel_diff
"""
function benchmark_cos_vs_mc(
    params::HestonParams,
    K::Float64;
    n_mc_paths::Int = 100000,
    config::COSConfig = COSConfig()
)
    cos_price = heston_cos_call(params, K; config=config)
    mc_result = heston_call_mc(params, K; n_paths=n_mc_paths)

    abs_diff = abs(cos_price - mc_result.price)
    rel_diff = abs_diff / (mc_result.price + 1e-10)

    return (
        cos_price = cos_price,
        mc_price = mc_result.price,
        mc_std_error = mc_result.std_error,
        abs_diff = abs_diff,
        rel_diff = rel_diff
    )
end
