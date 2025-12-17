"""
Volatility Surface Construction and Interpolation.

[T1] A volatility surface represents implied volatility as a function of
strike (K) and expiry (τ). Key concepts:

- **Moneyness**: K/F (strike/forward) or log(K/F)
- **Delta**: Option delta as strike coordinate (25Δ put, ATM, 25Δ call)
- **Smile**: Volatility curve for fixed expiry across strikes
- **Term structure**: Volatility curve for fixed strike across expiries

Interpolation methods:
- Linear in (K, τ) space
- Linear in (log-moneyness, √τ) space (better for extrapolation)
- Cubic spline for smooth smile
- SABR per-expiry fitting

References:
- Gatheral (2006), "The Volatility Surface"
- Clark (2011), "Foreign Exchange Option Pricing"
"""


"""
    VolSurfacePoint

A single point on the volatility surface.

# Fields
- `K::Float64`: Strike price
- `τ::Float64`: Time to expiry
- `σ::Float64`: Implied volatility
- `F::Float64`: Forward price (optional, for moneyness calc)
"""
struct VolSurfacePoint
    K::Float64
    τ::Float64
    σ::Float64
    F::Float64

    function VolSurfacePoint(K, τ, σ; F::Float64 = NaN)
        K > 0 || throw(ArgumentError("K must be positive"))
        τ > 0 || throw(ArgumentError("τ must be positive"))
        σ > 0 || throw(ArgumentError("σ must be positive"))
        new(K, τ, σ, F)
    end
end


"""
Moneyness of a vol surface point.
"""
function moneyness(p::VolSurfacePoint)
    isnan(p.F) && throw(ArgumentError("Forward F not set"))
    return p.K / p.F
end


"""
Log-moneyness of a vol surface point.
"""
function log_moneyness(p::VolSurfacePoint)
    return log(moneyness(p))
end


"""
    VolSmile

Volatility smile for a single expiry.

# Fields
- `τ::Float64`: Time to expiry
- `F::Float64`: Forward price
- `strikes::Vector{Float64}`: Strike prices
- `vols::Vector{Float64}`: Implied volatilities
"""
struct VolSmile
    τ::Float64
    F::Float64
    strikes::Vector{Float64}
    vols::Vector{Float64}

    function VolSmile(τ, F, strikes, vols)
        τ > 0 || throw(ArgumentError("τ must be positive"))
        F > 0 || throw(ArgumentError("F must be positive"))
        length(strikes) == length(vols) || throw(ArgumentError(
            "strikes and vols must have same length"
        ))
        all(strikes .> 0) || throw(ArgumentError("All strikes must be positive"))
        all(vols .> 0) || throw(ArgumentError("All vols must be positive"))

        # Sort by strike
        perm = sortperm(strikes)
        new(τ, F, strikes[perm], vols[perm])
    end
end


"""
    interpolate_smile(smile::VolSmile, K; method=:linear) -> Float64

Interpolate volatility at strike K.

# Arguments
- `smile::VolSmile`: Volatility smile
- `K::Float64`: Target strike
- `method::Symbol=:linear`: Interpolation method (:linear, :cubic, :flat)

# Returns
- `Float64`: Interpolated implied volatility
"""
function interpolate_smile(
    smile::VolSmile,
    K::Float64;
    method::Symbol = :linear
)
    K > 0 || throw(ArgumentError("K must be positive"))

    strikes = smile.strikes
    vols = smile.vols
    n = length(strikes)

    # Handle extrapolation
    if K <= strikes[1]
        return method == :flat ? vols[1] : _extrapolate_left(smile, K)
    elseif K >= strikes[end]
        return method == :flat ? vols[end] : _extrapolate_right(smile, K)
    end

    # Find bracketing strikes
    idx = searchsortedlast(strikes, K)
    K_lo, K_hi = strikes[idx], strikes[idx + 1]
    σ_lo, σ_hi = vols[idx], vols[idx + 1]

    if method == :linear
        # Linear interpolation in K
        t = (K - K_lo) / (K_hi - K_lo)
        return σ_lo + t * (σ_hi - σ_lo)

    elseif method == :log_linear
        # Linear in log-moneyness (better for wings)
        log_K = log(K / smile.F)
        log_K_lo = log(K_lo / smile.F)
        log_K_hi = log(K_hi / smile.F)
        t = (log_K - log_K_lo) / (log_K_hi - log_K_lo)
        return σ_lo + t * (σ_hi - σ_lo)

    elseif method == :cubic
        return _cubic_interpolate(strikes, vols, K, idx)

    else
        throw(ArgumentError("Unknown method: $method"))
    end
end


"""
Extrapolate volatility for strikes below the minimum observed.
"""
function _extrapolate_left(smile::VolSmile, K)
    # Flat extrapolation is safest for puts (avoid negative vols)
    return smile.vols[1]
end


"""
Extrapolate volatility for strikes above the maximum observed.
"""
function _extrapolate_right(smile::VolSmile, K)
    # Flat extrapolation is safest for calls
    return smile.vols[end]
end


"""
Cubic spline interpolation at a point.
"""
function _cubic_interpolate(x, y, x_target, idx)
    n = length(x)

    # Use 4 points for cubic (2 on each side if available)
    i0 = max(1, idx - 1)
    i3 = min(n, idx + 2)
    i1 = max(i0 + 1, idx)
    i2 = min(i1 + 1, i3)

    # Lagrange cubic interpolation
    x0, x1, x2, x3 = x[i0], x[i1], x[i2], x[min(i3, n)]
    y0, y1, y2, y3 = y[i0], y[i1], y[i2], y[min(i3, n)]

    # Handle case where we don't have 4 distinct points
    if i3 - i0 < 3
        # Fall back to linear
        t = (x_target - x[idx]) / (x[idx + 1] - x[idx])
        return y[idx] + t * (y[idx + 1] - y[idx])
    end

    # Lagrange basis polynomials
    L0 = ((x_target - x1) * (x_target - x2) * (x_target - x3)) /
         ((x0 - x1) * (x0 - x2) * (x0 - x3))
    L1 = ((x_target - x0) * (x_target - x2) * (x_target - x3)) /
         ((x1 - x0) * (x1 - x2) * (x1 - x3))
    L2 = ((x_target - x0) * (x_target - x1) * (x_target - x3)) /
         ((x2 - x0) * (x2 - x1) * (x2 - x3))
    L3 = ((x_target - x0) * (x_target - x1) * (x_target - x2)) /
         ((x3 - x0) * (x3 - x1) * (x3 - x2))

    return y0 * L0 + y1 * L1 + y2 * L2 + y3 * L3
end


"""
    VolSurface

Full volatility surface across strikes and expiries.

# Fields
- `smiles::Vector{VolSmile}`: Smiles for each expiry
- `expiries::Vector{Float64}`: Sorted expiry times
"""
struct VolSurface
    smiles::Vector{VolSmile}
    expiries::Vector{Float64}

    function VolSurface(smiles::Vector{VolSmile})
        length(smiles) > 0 || throw(ArgumentError("Need at least one smile"))

        # Sort by expiry
        expiries = [s.τ for s in smiles]
        perm = sortperm(expiries)
        new(smiles[perm], expiries[perm])
    end
end


"""
    interpolate_surface(surface::VolSurface, K, τ; method=:linear) -> Float64

Interpolate volatility at (K, τ).

# Arguments
- `surface::VolSurface`: Volatility surface
- `K::Float64`: Strike price
- `τ::Float64`: Time to expiry
- `method::Symbol=:linear`: Interpolation method

# Returns
- `Float64`: Interpolated implied volatility
"""
function interpolate_surface(
    surface::VolSurface,
    K::Float64,
    τ::Float64;
    method::Symbol = :linear
)
    K > 0 || throw(ArgumentError("K must be positive"))
    τ > 0 || throw(ArgumentError("τ must be positive"))

    expiries = surface.expiries

    # Handle extrapolation in time
    if τ <= expiries[1]
        return interpolate_smile(surface.smiles[1], K; method=method)
    elseif τ >= expiries[end]
        return interpolate_smile(surface.smiles[end], K; method=method)
    end

    # Find bracketing expiries
    idx = searchsortedlast(expiries, τ)
    τ_lo, τ_hi = expiries[idx], expiries[idx + 1]
    smile_lo, smile_hi = surface.smiles[idx], surface.smiles[idx + 1]

    # Interpolate each smile at K
    σ_lo = interpolate_smile(smile_lo, K; method=method)
    σ_hi = interpolate_smile(smile_hi, K; method=method)

    # Interpolate in time (linear in variance is common)
    if method == :linear_variance
        # Linear in total variance: σ²τ
        var_lo = σ_lo^2 * τ_lo
        var_hi = σ_hi^2 * τ_hi
        t = (τ - τ_lo) / (τ_hi - τ_lo)
        var_interp = var_lo + t * (var_hi - var_lo)
        return sqrt(var_interp / τ)
    else
        # Linear in vol
        t = (τ - τ_lo) / (τ_hi - τ_lo)
        return σ_lo + t * (σ_hi - σ_lo)
    end
end


"""
    build_surface_from_quotes(quotes::Vector{NamedTuple}) -> VolSurface

Build a volatility surface from market quotes.

# Arguments
- `quotes`: Vector of (K, τ, σ, F) named tuples

# Returns
- `VolSurface`: Constructed surface
"""
function build_surface_from_quotes(
    quotes::Vector{<:NamedTuple}
)
    # Group by expiry
    expiry_groups = Dict{Float64, Vector{NamedTuple}}()

    for q in quotes
        τ = q.τ
        if !haskey(expiry_groups, τ)
            expiry_groups[τ] = NamedTuple[]
        end
        push!(expiry_groups[τ], q)
    end

    # Build smiles
    smiles = VolSmile[]
    for (τ, group) in expiry_groups
        strikes = [q.K for q in group]
        vols = [q.σ for q in group]
        F = group[1].F  # Assume same forward for all quotes at this expiry

        push!(smiles, VolSmile(τ, F, strikes, vols))
    end

    return VolSurface(smiles)
end


"""
    fit_sabr_surface(surface::VolSurface; β=0.5) -> Vector{SABRParams}

Fit SABR parameters to each expiry slice of the surface.

# Arguments
- `surface::VolSurface`: Market volatility surface
- `β::Float64=0.5`: Fixed SABR β parameter

# Returns
- `Vector{SABRParams}`: SABR parameters for each expiry
"""
function fit_sabr_surface(
    surface::VolSurface;
    β::Float64 = 0.5
)
    sabr_params = SABRParams[]

    for smile in surface.smiles
        params = calibrate_sabr(
            smile.F, smile.τ, smile.strikes, smile.vols; β=β
        )
        push!(sabr_params, params)
    end

    return sabr_params
end


"""
    atm_vol(smile::VolSmile) -> Float64

Get ATM implied volatility (interpolated at F).
"""
function atm_vol(smile::VolSmile)
    return interpolate_smile(smile, smile.F)
end


"""
    atm_vol(surface::VolSurface, τ) -> Float64

Get ATM implied volatility at expiry τ.
"""
function atm_vol(surface::VolSurface, τ::Float64)
    # Find the smile for this expiry
    idx = searchsortedlast(surface.expiries, τ)
    if idx == 0
        smile = surface.smiles[1]
    elseif idx >= length(surface.expiries)
        smile = surface.smiles[end]
    else
        # Interpolate ATM vol between expiries
        smile_lo = surface.smiles[idx]
        smile_hi = surface.smiles[idx + 1]
        τ_lo, τ_hi = surface.expiries[idx], surface.expiries[idx + 1]

        σ_lo = atm_vol(smile_lo)
        σ_hi = atm_vol(smile_hi)

        t = (τ - τ_lo) / (τ_hi - τ_lo)
        return σ_lo + t * (σ_hi - σ_lo)
    end

    return atm_vol(smile)
end


"""
    skew(smile::VolSmile; delta=0.25) -> Float64

Compute volatility skew: σ(25Δ put) - σ(25Δ call).

[T1] Positive skew = downside protection is more expensive.
"""
function skew(smile::VolSmile; delta::Float64 = 0.25)
    # Approximate 25Δ strikes using ATM vol and time
    σ_atm = atm_vol(smile)
    F, τ = smile.F, smile.τ

    # 25Δ put strike (simplified approximation)
    K_put = F * exp(-0.674 * σ_atm * sqrt(τ))  # 25Δ put

    # 25Δ call strike
    K_call = F * exp(0.674 * σ_atm * sqrt(τ))  # 25Δ call

    σ_put = interpolate_smile(smile, K_put)
    σ_call = interpolate_smile(smile, K_call)

    return σ_put - σ_call
end


"""
    butterfly(smile::VolSmile; delta=0.25) -> Float64

Compute butterfly spread: 0.5*(σ_put + σ_call) - σ_ATM.

[T1] Measures convexity/curvature of the smile.
"""
function butterfly(smile::VolSmile; delta::Float64 = 0.25)
    σ_atm = atm_vol(smile)
    F, τ = smile.F, smile.τ

    K_put = F * exp(-0.674 * σ_atm * sqrt(τ))
    K_call = F * exp(0.674 * σ_atm * sqrt(τ))

    σ_put = interpolate_smile(smile, K_put)
    σ_call = interpolate_smile(smile, K_call)

    return 0.5 * (σ_put + σ_call) - σ_atm
end


"""
    term_structure(surface::VolSurface) -> Vector{Tuple{Float64, Float64}}

Extract ATM term structure: [(τ₁, σ₁), (τ₂, σ₂), ...].
"""
function term_structure(surface::VolSurface)
    return [(s.τ, atm_vol(s)) for s in surface.smiles]
end


"""
    validate_no_calendar_arbitrage(surface::VolSurface) -> Bool

Check that total variance is increasing in time (no calendar arbitrage).

[T1] Calendar arbitrage occurs if σ²(τ₁) > σ²(τ₂) for τ₁ < τ₂.
"""
function validate_no_calendar_arbitrage(surface::VolSurface)
    ts = term_structure(surface)

    for i in 1:(length(ts) - 1)
        τ₁, σ₁ = ts[i]
        τ₂, σ₂ = ts[i + 1]

        var₁ = σ₁^2 * τ₁
        var₂ = σ₂^2 * τ₂

        if var₂ < var₁ - 1e-10  # Small tolerance
            return false
        end
    end

    return true
end


"""
    smile_from_heston(params::HestonParams, strikes; config=COSConfig()) -> VolSmile

Generate a volatility smile from Heston parameters using COS pricing.
"""
function smile_from_heston(
    params::HestonParams,
    strikes::Vector{Float64};
    config::COSConfig = COSConfig()
)
    impl_vols = heston_smile_cos(params, strikes; config=config)
    return VolSmile(params.τ, params.S₀, strikes, impl_vols)
end


"""
    smile_from_sabr(params::SABRParams, strikes) -> VolSmile

Generate a volatility smile from SABR parameters.
"""
function smile_from_sabr(
    params::SABRParams,
    strikes::Vector{Float64}
)
    impl_vols = sabr_smile(params, strikes)
    return VolSmile(params.τ, params.F, strikes, impl_vols)
end
