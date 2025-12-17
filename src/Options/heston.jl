"""
Heston Stochastic Volatility Model.

[T1] The Heston (1993) model assumes variance follows a CIR process:
    dS = (r - q) S dt + √V S dW_S
    dV = κ(θ - V) dt + σ_v √V dW_V
    dW_S dW_V = ρ dt

where:
- κ: Mean reversion speed
- θ: Long-term variance
- σ_v: Volatility of volatility
- ρ: Correlation between spot and variance
- V₀: Initial variance

Feller condition: 2κθ > σ_v² ensures variance stays positive.

References:
- Heston (1993), "A Closed-Form Solution for Options with Stochastic Volatility"
- Gatheral (2006), "The Volatility Surface", Chapter 2
"""


"""
    HestonParams

Parameters for the Heston stochastic volatility model.

# Fields
- `S₀::Float64`: Initial spot price
- `r::Float64`: Risk-free rate
- `q::Float64`: Dividend yield
- `V₀::Float64`: Initial variance (σ₀²)
- `κ::Float64`: Mean reversion speed
- `θ::Float64`: Long-term variance
- `σ_v::Float64`: Volatility of volatility
- `ρ::Float64`: Correlation between spot and variance
- `τ::Float64`: Time to maturity

# Example
```julia
params = HestonParams(
    S₀ = 100.0,
    r = 0.05,
    q = 0.02,
    V₀ = 0.04,    # 20% initial vol
    κ = 2.0,
    θ = 0.04,     # 20% long-term vol
    σ_v = 0.3,
    ρ = -0.7,
    τ = 1.0
)
```
"""
struct HestonParams
    S₀::Float64
    r::Float64
    q::Float64
    V₀::Float64
    κ::Float64
    θ::Float64
    σ_v::Float64
    ρ::Float64
    τ::Float64

    function HestonParams(;
        S₀::Float64,
        r::Float64,
        q::Float64 = 0.0,
        V₀::Float64,
        κ::Float64,
        θ::Float64,
        σ_v::Float64,
        ρ::Float64,
        τ::Float64
    )
        S₀ > 0 || throw(ArgumentError("S₀ must be positive"))
        V₀ >= 0 || throw(ArgumentError("V₀ must be non-negative"))
        κ > 0 || throw(ArgumentError("κ must be positive"))
        θ > 0 || throw(ArgumentError("θ must be positive"))
        σ_v > 0 || throw(ArgumentError("σ_v must be positive"))
        abs(ρ) <= 1 || throw(ArgumentError("ρ must be in [-1, 1]"))
        τ > 0 || throw(ArgumentError("τ must be positive"))

        new(S₀, r, q, V₀, κ, θ, σ_v, ρ, τ)
    end
end


"""
    feller_condition(params::HestonParams) -> Bool

Check if the Feller condition is satisfied: 2κθ > σ_v².

[T1] When satisfied, variance process stays strictly positive.
"""
function feller_condition(params::HestonParams)
    return 2 * params.κ * params.θ > params.σ_v^2
end


"""
    HestonPathResult

Result of Heston path simulation.

# Fields
- `spot_paths::Matrix{Float64}`: Spot price paths (n_paths × n_steps+1)
- `variance_paths::Matrix{Float64}`: Variance paths (n_paths × n_steps+1)
- `params::HestonParams`: Parameters used
"""
struct HestonPathResult
    spot_paths::Matrix{Float64}
    variance_paths::Matrix{Float64}
    params::HestonParams
end


"""
    generate_heston_paths(params, n_paths, n_steps; seed=nothing, scheme=:euler) -> HestonPathResult

Generate paths under the Heston model.

[T1] Uses Euler-Maruyama or QE (Quadratic Exponential) discretization.

# Arguments
- `params::HestonParams`: Model parameters
- `n_paths::Int`: Number of simulation paths
- `n_steps::Int`: Number of time steps
- `seed::Union{Int, Nothing}=nothing`: Random seed
- `scheme::Symbol=:euler`: Discretization scheme (:euler or :qe)

# Returns
- `HestonPathResult`: Paths for spot and variance

# Notes
- Euler scheme may produce negative variances (truncated to 0)
- QE scheme (Andersen 2008) is more accurate but complex
"""
function generate_heston_paths(
    params::HestonParams,
    n_paths::Int,
    n_steps::Int;
    seed::Union{Int, Nothing} = nothing,
    scheme::Symbol = :euler
)
    rng = seed === nothing ? StableRNG(42) : StableRNG(seed)

    dt = params.τ / n_steps

    # Initialize paths
    S = zeros(n_paths, n_steps + 1)
    V = zeros(n_paths, n_steps + 1)

    S[:, 1] .= params.S₀
    V[:, 1] .= params.V₀

    if scheme == :euler
        _simulate_euler!(S, V, params, n_paths, n_steps, dt, rng)
    elseif scheme == :qe
        _simulate_qe!(S, V, params, n_paths, n_steps, dt, rng)
    else
        throw(ArgumentError("Unknown scheme: $scheme. Use :euler or :qe"))
    end

    return HestonPathResult(S, V, params)
end


"""
Euler-Maruyama discretization for Heston model.

[T1] Simple but may produce negative variances.
"""
function _simulate_euler!(S, V, params, n_paths, n_steps, dt, rng)
    sqrt_dt = sqrt(dt)
    κ, θ, σ_v, ρ = params.κ, params.θ, params.σ_v, params.ρ
    r, q = params.r, params.q

    # Correlation structure
    sqrt_1_minus_rho2 = sqrt(1 - ρ^2)

    for t in 1:n_steps
        # Generate correlated Brownian increments
        Z1 = randn(rng, n_paths)
        Z2 = randn(rng, n_paths)
        dW_S = Z1 * sqrt_dt
        dW_V = (ρ * Z1 + sqrt_1_minus_rho2 * Z2) * sqrt_dt

        for i in 1:n_paths
            V_curr = max(V[i, t], 0.0)  # Truncate negative variance
            sqrt_V = sqrt(V_curr)

            # Spot dynamics
            S[i, t + 1] = S[i, t] * exp(
                (r - q - 0.5 * V_curr) * dt + sqrt_V * dW_S[i]
            )

            # Variance dynamics (CIR process)
            V[i, t + 1] = V_curr + κ * (θ - V_curr) * dt + σ_v * sqrt_V * dW_V[i]
        end
    end
end


"""
Quadratic Exponential (QE) scheme for Heston variance.

[T1] Andersen (2008) - more accurate than Euler, handles low variance well.

NOTE: This implementation does not include spot-variance correlation ρ.
For correlation effects, use scheme=:euler which correctly handles ρ.
The QE scheme here provides better variance dynamics but treats spot
as conditionally independent given the variance path.
"""
function _simulate_qe!(S, V, params, n_paths, n_steps, dt, rng)
    κ, θ, σ_v, ρ = params.κ, params.θ, params.σ_v, params.ρ
    r, q = params.r, params.q

    # QE parameters
    ψ_c = 1.5  # Critical value for scheme switching

    # Precompute constants
    exp_kappa_dt = exp(-κ * dt)
    c1 = σ_v^2 * exp_kappa_dt * (1 - exp_kappa_dt) / κ
    c2 = θ * σ_v^2 * (1 - exp_kappa_dt)^2 / (2 * κ)

    sqrt_dt = sqrt(dt)

    for t in 1:n_steps
        Z_S = randn(rng, n_paths)  # Independent normal for spot
        U_V = rand(rng, n_paths)

        for i in 1:n_paths
            V_curr = max(V[i, t], 0.0)

            # QE: compute m and s² for next variance
            m = θ + (V_curr - θ) * exp_kappa_dt
            s2 = c1 * V_curr + c2
            ψ = s2 / (m^2 + 1e-10)  # Avoid division by zero

            # Sample next variance
            if ψ <= ψ_c
                # Quadratic scheme
                b2 = 2 / ψ - 1 + sqrt(2 / ψ) * sqrt(2 / ψ - 1)
                b = sqrt(b2)
                a = m / (1 + b2)
                Z_V = quantile(Normal(), U_V[i])
                V[i, t + 1] = a * (b + Z_V)^2
            else
                # Exponential scheme
                p = (ψ - 1) / (ψ + 1)
                β = (1 - p) / (m + 1e-10)
                if U_V[i] <= p
                    V[i, t + 1] = 0.0
                else
                    V[i, t + 1] = log((1 - p) / (1 - U_V[i])) / β
                end
            end

            # Integrated variance approximation (trapezoidal)
            V_next = max(V[i, t + 1], 0.0)
            V_avg = 0.5 * (V_curr + V_next)

            # Spot dynamics (conditionally independent given variance)
            sqrt_V_avg = sqrt(V_avg)
            dW_S = Z_S[i] * sqrt_dt

            S[i, t + 1] = S[i, t] * exp(
                (r - q - 0.5 * V_avg) * dt + sqrt_V_avg * dW_S
            )
        end
    end
end


"""
    heston_characteristic_function(u, params::HestonParams; type::Int=1) -> Complex

Compute the Heston characteristic function.

[T1] φ(u) = E[exp(iu log(S_T))]

Used for Fourier-based pricing methods (COS, Carr-Madan).

# Arguments
- `u`: Fourier variable (can be complex)
- `params::HestonParams`: Model parameters
- `type::Int=1`: Formulation type (1 or 2, affects branch cuts)

# Returns
- `Complex{Float64}`: Characteristic function value
"""
function heston_characteristic_function(
    u::Union{Real, Complex},
    params::HestonParams;
    type::Int = 1
)
    S₀, r, q, V₀ = params.S₀, params.r, params.q, params.V₀
    κ, θ, σ_v, ρ, τ = params.κ, params.θ, params.σ_v, params.ρ, params.τ

    # Handle u = 0 case (CF should be 1)
    if abs(u) < 1e-12
        return complex(1.0, 0.0)
    end

    # Convert to complex
    u = complex(u)

    # Adjusted parameters
    a = κ * θ
    b = type == 1 ? κ - ρ * σ_v : κ

    # Characteristic exponents
    iu = im * u
    d = sqrt((ρ * σ_v * iu - b)^2 + σ_v^2 * (iu + u^2))

    # Ensure d has positive real part for numerical stability
    if real(d) < 0
        d = -d
    end

    if type == 1
        g = (b - ρ * σ_v * iu + d) / (b - ρ * σ_v * iu - d)
    else
        g = (b - ρ * σ_v * iu - d) / (b - ρ * σ_v * iu + d)
    end

    exp_d_tau = exp(d * τ)

    # C and D functions
    if type == 1
        C = (r - q) * iu * τ + (a / σ_v^2) * (
            (b - ρ * σ_v * iu + d) * τ - 2 * log((1 - g * exp_d_tau) / (1 - g))
        )
        D = ((b - ρ * σ_v * iu + d) / σ_v^2) * ((1 - exp_d_tau) / (1 - g * exp_d_tau))
    else
        C = (r - q) * iu * τ + (a / σ_v^2) * (
            (b - ρ * σ_v * iu - d) * τ - 2 * log((1 - g * exp_d_tau) / (1 - g))
        )
        D = ((b - ρ * σ_v * iu - d) / σ_v^2) * ((1 - exp_d_tau) / (1 - g * exp_d_tau))
    end

    return exp(C + D * V₀ + iu * log(S₀))
end


"""
    heston_call_mc(params::HestonParams, K; n_paths=100000, n_steps=252, seed=42, scheme=:qe)

Price a European call under Heston using Monte Carlo.

# Arguments
- `params::HestonParams`: Model parameters
- `K::Float64`: Strike price
- `n_paths::Int=100000`: Number of paths
- `n_steps::Int=252`: Steps per path
- `seed::Int=42`: Random seed
- `scheme::Symbol=:qe`: Discretization scheme

# Returns
- `NamedTuple`: (price, std_error, paths_result)
"""
function heston_call_mc(
    params::HestonParams,
    K::Float64;
    n_paths::Int = 100000,
    n_steps::Int = 252,
    seed::Int = 42,
    scheme::Symbol = :qe
)
    result = generate_heston_paths(params, n_paths, n_steps; seed=seed, scheme=scheme)

    # Terminal spot prices
    S_T = result.spot_paths[:, end]

    # Discounted payoffs
    payoffs = max.(S_T .- K, 0.0) * exp(-params.r * params.τ)

    price = mean(payoffs)
    std_error = std(payoffs) / sqrt(n_paths)

    return (price = price, std_error = std_error, paths_result = result)
end


"""
    heston_put_mc(params::HestonParams, K; kwargs...)

Price a European put under Heston using Monte Carlo.
"""
function heston_put_mc(
    params::HestonParams,
    K::Float64;
    n_paths::Int = 100000,
    n_steps::Int = 252,
    seed::Int = 42,
    scheme::Symbol = :qe
)
    result = generate_heston_paths(params, n_paths, n_steps; seed=seed, scheme=scheme)

    S_T = result.spot_paths[:, end]
    payoffs = max.(K .- S_T, 0.0) * exp(-params.r * params.τ)

    price = mean(payoffs)
    std_error = std(payoffs) / sqrt(n_paths)

    return (price = price, std_error = std_error, paths_result = result)
end


"""
    heston_implied_vol(params::HestonParams, K; method=:newton)

Compute Black-Scholes implied volatility from Heston price.

[T1] Inverts BS formula to find σ such that BS(σ) = Heston price.
"""
function heston_implied_vol(
    params::HestonParams,
    K::Float64;
    method::Symbol = :newton,
    n_paths::Int = 100000
)
    # Get Heston price
    heston_result = heston_call_mc(params, K; n_paths=n_paths)
    target_price = heston_result.price

    # Newton-Raphson to find implied vol
    σ = sqrt(params.V₀)  # Initial guess
    S, r, q, τ = params.S₀, params.r, params.q, params.τ

    for _ in 1:50
        bs_price = black_scholes_call(S, K, r, q, σ, τ)
        vega = black_scholes_greeks(S, K, r, q, σ, τ).vega * 100  # vega is per 1% change

        diff = bs_price - target_price
        if abs(diff) < 1e-8
            break
        end

        σ = σ - diff / (vega + 1e-10)
        σ = clamp(σ, 0.01, 2.0)
    end

    return σ
end
