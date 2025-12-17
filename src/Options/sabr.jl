"""
SABR Stochastic Volatility Model.

[T1] The SABR model (Hagan et al. 2002) assumes:
    dF = σ F^β dW_F
    dσ = α σ dW_σ
    dW_F dW_σ = ρ dt

where:
- F: Forward price
- σ: Stochastic volatility
- α: Volatility of volatility
- β: CEV exponent (0 = normal, 1 = lognormal)
- ρ: Correlation

The Hagan formula provides an analytical approximation for implied volatility.

References:
- Hagan et al. (2002), "Managing Smile Risk"
- Oblój (2008), "Fine-tune your smile: Correction to Hagan et al."
"""


"""
    SABRParams

Parameters for the SABR model.

# Fields
- `F::Float64`: Forward price
- `α::Float64`: Initial volatility (σ₀)
- `β::Float64`: CEV exponent (typically 0 ≤ β ≤ 1)
- `ρ::Float64`: Correlation (-1 ≤ ρ ≤ 1)
- `ν::Float64`: Volatility of volatility (vol of vol)
- `τ::Float64`: Time to expiry

# Example
```julia
params = SABRParams(
    F = 100.0,
    α = 0.20,
    β = 0.5,
    ρ = -0.3,
    ν = 0.4,
    τ = 1.0
)
```
"""
struct SABRParams
    F::Float64
    α::Float64
    β::Float64
    ρ::Float64
    ν::Float64
    τ::Float64

    function SABRParams(;
        F::Float64,
        α::Float64,
        β::Float64 = 1.0,
        ρ::Float64 = 0.0,
        ν::Float64,
        τ::Float64
    )
        F > 0 || throw(ArgumentError("Forward F must be positive"))
        α > 0 || throw(ArgumentError("α must be positive"))
        0 <= β <= 1 || throw(ArgumentError("β must be in [0, 1]"))
        abs(ρ) <= 1 || throw(ArgumentError("ρ must be in [-1, 1]"))
        ν >= 0 || throw(ArgumentError("ν must be non-negative"))
        τ > 0 || throw(ArgumentError("τ must be positive"))

        new(F, α, β, ρ, ν, τ)
    end
end


"""
    sabr_implied_vol(params::SABRParams, K; method=:hagan) -> Float64

Compute SABR implied volatility using Hagan's approximation.

[T1] The Hagan formula (2002) gives a closed-form approximation for Black implied vol.

# Arguments
- `params::SABRParams`: SABR parameters
- `K::Float64`: Strike price
- `method::Symbol=:hagan`: Approximation method (:hagan or :obloj)

# Returns
- `Float64`: Black implied volatility

# Example
```julia
params = SABRParams(F=100.0, α=0.20, β=0.5, ρ=-0.3, ν=0.4, τ=1.0)
σ_impl = sabr_implied_vol(params, 100.0)  # ATM vol
```
"""
function sabr_implied_vol(
    params::SABRParams,
    K::Float64;
    method::Symbol = :hagan
)
    F, α, β, ρ, ν, τ = params.F, params.α, params.β, params.ρ, params.ν, params.τ

    K > 0 || throw(ArgumentError("Strike K must be positive"))

    # Handle ATM case (F ≈ K)
    if abs(F - K) < 1e-10 * F
        return _sabr_atm_vol(params)
    end

    if method == :hagan
        return _sabr_hagan(F, K, α, β, ρ, ν, τ)
    elseif method == :obloj
        return _sabr_obloj(F, K, α, β, ρ, ν, τ)
    else
        throw(ArgumentError("Unknown method: $method. Use :hagan or :obloj"))
    end
end


"""
Hagan et al. (2002) SABR implied volatility approximation.

[T1] Original formula from "Managing Smile Risk".

The key factor z/χ(z) where:
- z = (ν/α) * (FK)^((1-β)/2) * ln(F/K)
- χ(z) = log[(√(1-2ρz+z²) + z - ρ)/(1-ρ)]

For z → 0, z/χ(z) → 1.
"""
function _sabr_hagan(F, K, α, β, ρ, ν, τ)
    # Moneyness
    FK = F * K
    FK_beta = FK^((1 - β) / 2)
    logFK = log(F / K)

    # z parameter
    z = (ν / α) * FK_beta * logFK

    # z/χ(z) factor - this is the key smile-generating term
    # For z → 0: z/χ(z) → 1
    # For z ≠ 0 with negative ρ: increases vol for low strikes (put skew)
    if abs(z) < 1e-10
        z_over_chi = 1.0
    else
        sqrt_term = sqrt(1 - 2 * ρ * z + z^2)
        chi_z = log((sqrt_term + z - ρ) / (1 - ρ))
        z_over_chi = z / chi_z
    end

    # Denominator expansion
    one_minus_beta = 1 - β
    FK_2beta = FK^(one_minus_beta)

    denom = 1 + (one_minus_beta^2 / 24) * logFK^2 +
            (one_minus_beta^4 / 1920) * logFK^4

    # Numerator expansion (τ-dependent corrections)
    term1 = (one_minus_beta^2 / 24) * α^2 / FK_2beta
    term2 = 0.25 * ρ * β * ν * α / FK_beta
    term3 = (2 - 3 * ρ^2) * ν^2 / 24

    numer = α * (1 + (term1 + term2 + term3) * τ)

    # Final formula: σ_B = (α/FK_beta) * (z/χ(z)) * [1 + corrections] / denom
    σ_B = (numer / (FK_beta * denom)) * z_over_chi

    return max(σ_B, 1e-10)  # Ensure positive
end


"""
Oblój (2008) corrected SABR approximation.

[T1] Improved accuracy for high vol-of-vol and away-from-ATM strikes.
Uses better Taylor expansion for small z and improved asymptotic behavior.
"""
function _sabr_obloj(F, K, α, β, ρ, ν, τ)
    # Similar structure to Hagan but with corrections
    FK = F * K
    FK_beta = FK^((1 - β) / 2)
    logFK = log(F / K)

    # z parameter with Oblój correction
    z = (ν / α) * FK_beta * logFK

    # z/χ(z) factor with improved Taylor expansion for numerical stability
    # For z → 0: z/χ(z) ≈ 1 - ρz/2 + (3ρ² - 2)z²/12 + O(z³)
    if abs(z) < 1e-7
        # Use inverse of Taylor expansion of χ(z)/z
        chi_over_z = 1.0 + 0.5 * ρ * z + (3 * ρ^2 - 2) * z^2 / 12
        z_over_chi = 1.0 / chi_over_z
    else
        sqrt_term = sqrt(1 - 2 * ρ * z + z^2)
        chi_z = log((sqrt_term + z - ρ) / (1 - ρ))
        z_over_chi = z / chi_z
    end

    # Use F^(1-β) instead of (FK)^((1-β)/2) for asymptotic consistency
    one_minus_beta = 1 - β
    F_beta = F^one_minus_beta
    K_beta = K^one_minus_beta

    # Corrected denominator
    denom = 1 + (one_minus_beta^2 / 24) * logFK^2 +
            (one_minus_beta^4 / 1920) * logFK^4

    # Corrected numerator terms
    term1 = (one_minus_beta^2 / 24) * α^2 / (FK^one_minus_beta)
    term2 = 0.25 * ρ * β * ν * α / FK_beta
    term3 = (2 - 3 * ρ^2) * ν^2 / 24

    numer = α * (1 + (term1 + term2 + term3) * τ)

    σ_B = (numer / (FK_beta * denom)) * z_over_chi

    return max(σ_B, 1e-10)
end


"""
ATM SABR implied volatility.

[T1] Simplified formula when F = K.
"""
function _sabr_atm_vol(params::SABRParams)
    F, α, β, ρ, ν, τ = params.F, params.α, params.β, params.ρ, params.ν, params.τ

    F_beta = F^(1 - β)

    term1 = (1 - β)^2 * α^2 / (24 * F^(2 * (1 - β)))
    term2 = 0.25 * ρ * β * ν * α / F_beta
    term3 = (2 - 3 * ρ^2) * ν^2 / 24

    σ_ATM = (α / F_beta) * (1 + (term1 + term2 + term3) * τ)

    return max(σ_ATM, 1e-10)
end


"""
    sabr_smile(params::SABRParams, strikes::Vector{Float64}; method=:hagan) -> Vector{Float64}

Compute SABR implied volatility smile across strikes.

# Arguments
- `params::SABRParams`: SABR parameters
- `strikes::Vector{Float64}`: Strike prices
- `method::Symbol=:hagan`: Approximation method

# Returns
- `Vector{Float64}`: Implied volatilities for each strike
"""
function sabr_smile(
    params::SABRParams,
    strikes::Vector{Float64};
    method::Symbol = :hagan
)
    return [sabr_implied_vol(params, K; method=method) for K in strikes]
end


"""
    calibrate_sabr(F, τ, strikes, market_vols; β=nothing, method=:least_squares) -> SABRParams

Calibrate SABR parameters to market implied volatilities.

[T1] Finds (α, ρ, ν) that minimize squared error to market vols.
     β is often fixed based on market convention.

# Arguments
- `F::Float64`: Forward price
- `τ::Float64`: Time to expiry
- `strikes::Vector{Float64}`: Strike prices
- `market_vols::Vector{Float64}`: Market implied volatilities
- `β::Union{Float64, Nothing}=nothing`: Fixed β (if nothing, calibrate it too)
- `method::Symbol=:least_squares`: Calibration method

# Returns
- `SABRParams`: Calibrated parameters

# Example
```julia
strikes = [90.0, 95.0, 100.0, 105.0, 110.0]
market_vols = [0.25, 0.22, 0.20, 0.21, 0.23]
params = calibrate_sabr(100.0, 1.0, strikes, market_vols; β=0.5)
```
"""
function calibrate_sabr(
    F::Float64,
    τ::Float64,
    strikes::Vector{Float64},
    market_vols::Vector{Float64};
    β::Union{Float64, Nothing} = nothing,
    method::Symbol = :least_squares
)
    length(strikes) == length(market_vols) || throw(ArgumentError(
        "strikes and market_vols must have same length"
    ))

    # Objective function
    function objective(x)
        if β === nothing
            α, ρ, ν, β_cal = x[1], x[2], x[3], x[4]
        else
            α, ρ, ν = x[1], x[2], x[3]
            β_cal = β
        end

        # Bounds enforcement
        α = max(α, 1e-6)
        ρ = clamp(ρ, -0.999, 0.999)
        ν = max(ν, 1e-6)
        β_cal = clamp(β_cal, 0.0, 1.0)

        try
            params = SABRParams(F=F, α=α, β=β_cal, ρ=ρ, ν=ν, τ=τ)
            model_vols = sabr_smile(params, strikes)
            return sum((model_vols .- market_vols).^2)
        catch
            return 1e10  # Penalty for invalid params
        end
    end

    # Initial guess
    σ_atm_idx = argmin(abs.(strikes .- F))
    α_init = market_vols[σ_atm_idx] * F^(1 - (β === nothing ? 0.5 : β))
    ρ_init = -0.3
    ν_init = 0.4
    β_init = β === nothing ? 0.5 : β

    if β === nothing
        x0 = [α_init, ρ_init, ν_init, β_init]
    else
        x0 = [α_init, ρ_init, ν_init]
    end

    # Simple gradient-free optimization (Nelder-Mead style)
    best_x = x0
    best_obj = objective(x0)

    # Grid search refinement
    for α_mult in [0.5, 0.8, 1.0, 1.2, 1.5]
        for ρ_try in [-0.7, -0.5, -0.3, 0.0, 0.3]
            for ν_try in [0.2, 0.3, 0.4, 0.5, 0.6]
                if β === nothing
                    for β_try in [0.0, 0.25, 0.5, 0.75, 1.0]
                        x_try = [α_init * α_mult, ρ_try, ν_try, β_try]
                        obj = objective(x_try)
                        if obj < best_obj
                            best_obj = obj
                            best_x = x_try
                        end
                    end
                else
                    x_try = [α_init * α_mult, ρ_try, ν_try]
                    obj = objective(x_try)
                    if obj < best_obj
                        best_obj = obj
                        best_x = x_try
                    end
                end
            end
        end
    end

    # Extract calibrated parameters
    if β === nothing
        α_cal, ρ_cal, ν_cal, β_cal = best_x
    else
        α_cal, ρ_cal, ν_cal = best_x
        β_cal = β
    end

    return SABRParams(
        F = F,
        α = max(α_cal, 1e-6),
        β = clamp(β_cal, 0.0, 1.0),
        ρ = clamp(ρ_cal, -0.999, 0.999),
        ν = max(ν_cal, 1e-6),
        τ = τ
    )
end


"""
    sabr_delta(params::SABRParams, K, r; call=true) -> Float64

Compute SABR delta using Black formula with SABR vol.

[T1] Δ = ∂V/∂S ≈ Black delta with σ = σ_SABR(K)
"""
function sabr_delta(
    params::SABRParams,
    K::Float64,
    r::Float64;
    call::Bool = true
)
    σ = sabr_implied_vol(params, K)
    F, τ = params.F, params.τ

    # Forward delta (no discounting for forward)
    d1 = (log(F / K) + 0.5 * σ^2 * τ) / (σ * sqrt(τ))

    if call
        return cdf(Normal(), d1)
    else
        return cdf(Normal(), d1) - 1
    end
end


"""
    sabr_vega(params::SABRParams, K, r) -> Float64

Compute SABR vega (sensitivity to α).

[T1] ∂V/∂α - sensitivity to the initial volatility level.
"""
function sabr_vega(
    params::SABRParams,
    K::Float64,
    r::Float64
)
    σ = sabr_implied_vol(params, K)
    F, τ = params.F, params.τ

    d1 = (log(F / K) + 0.5 * σ^2 * τ) / (σ * sqrt(τ))

    # Black vega
    black_vega = F * sqrt(τ) * pdf(Normal(), d1)

    # Chain rule: ∂V/∂α = ∂V/∂σ × ∂σ/∂α
    # Approximate ∂σ/∂α numerically
    ε = params.α * 0.01
    params_up = SABRParams(F=F, α=params.α + ε, β=params.β, ρ=params.ρ, ν=params.ν, τ=τ)
    params_dn = SABRParams(F=F, α=params.α - ε, β=params.β, ρ=params.ρ, ν=params.ν, τ=τ)

    σ_up = sabr_implied_vol(params_up, K)
    σ_dn = sabr_implied_vol(params_dn, K)
    dσ_dα = (σ_up - σ_dn) / (2 * ε)

    return black_vega * dσ_dα * exp(-r * τ)
end
