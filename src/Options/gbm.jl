"""
Geometric Brownian Motion (GBM) path generation.

Implements efficient path simulation for Monte Carlo pricing:
- Standard GBM with exact log-normal simulation
- Antithetic variates for variance reduction
- Vectorized operations for performance

[T1] GBM SDE: dS = (r - q)S dt + σS dW

References:
- Glasserman (2003) "Monte Carlo Methods in Financial Engineering", Ch. 3
- Hull (2021) "Options, Futures, and Other Derivatives", Ch. 21
"""

"""
    GBMParams{T}

Parameters for GBM simulation.

# Fields
- `spot::T`: Initial spot price
- `rate::T`: Risk-free rate (annualized, decimal)
- `dividend::T`: Dividend yield (annualized, decimal)
- `volatility::T`: Volatility (annualized, decimal)
- `time_to_expiry::T`: Time to expiry in years
"""
struct GBMParams{T<:Real}
    spot::T
    rate::T
    dividend::T
    volatility::T
    time_to_expiry::T

    function GBMParams(spot::T, rate::T, dividend::T, volatility::T, time_to_expiry::T) where T<:Real
        spot > 0 || throw(ArgumentError("CRITICAL: spot must be > 0, got $spot"))
        volatility >= 0 || throw(ArgumentError("CRITICAL: volatility must be >= 0, got $volatility"))
        time_to_expiry > 0 || throw(ArgumentError("CRITICAL: time_to_expiry must be > 0, got $time_to_expiry"))
        new{T}(spot, rate, dividend, volatility, time_to_expiry)
    end
end

# Convenience constructor for mixed types
function GBMParams(spot, rate, dividend, volatility, time_to_expiry)
    T = promote_type(typeof(spot), typeof(rate), typeof(dividend), typeof(volatility), typeof(time_to_expiry))
    GBMParams(T(spot), T(rate), T(dividend), T(volatility), T(time_to_expiry))
end

"""
    drift(params::GBMParams) -> T

Risk-neutral drift: r - q - σ²/2
"""
function drift(params::GBMParams{T}) where T
    return params.rate - params.dividend - params.volatility^2 / 2
end

"""
    forward(params::GBMParams) -> T

Forward price: S × exp((r-q)×T)
"""
function forward(params::GBMParams{T}) where T
    return params.spot * exp((params.rate - params.dividend) * params.time_to_expiry)
end


"""
    PathResult{T}

Result of GBM path generation.

# Fields
- `paths::Matrix{T}`: Simulated paths, shape (n_paths, n_steps + 1)
- `times::Vector{T}`: Time points, shape (n_steps + 1,)
- `params::GBMParams{T}`: Parameters used for simulation
- `seed::Union{Int, Nothing}`: Random seed used
- `antithetic::Bool`: Whether antithetic variates were used
"""
struct PathResult{T<:Real}
    paths::Matrix{T}
    times::Vector{T}
    params::GBMParams{T}
    seed::Union{Int, Nothing}
    antithetic::Bool
end

"""Number of paths in result."""
n_paths(result::PathResult) = size(result.paths, 1)

"""Number of time steps in result."""
n_steps(result::PathResult) = size(result.paths, 2) - 1

"""Terminal values of all paths."""
terminal_values(result::PathResult) = result.paths[:, end]

"""Total returns for all paths: (S(T) - S(0)) / S(0)."""
function total_returns(result::PathResult{T}) where T
    return (result.paths[:, end] .- result.paths[:, 1]) ./ result.paths[:, 1]
end


"""
    generate_gbm_paths(params, n_paths, n_steps; seed=nothing, antithetic=false, rng=nothing) -> PathResult

Generate GBM paths using exact log-normal simulation.

[T1] Uses exact formula:
    S(t+dt) = S(t) × exp((r - q - σ²/2)dt + σ√dt × Z)

# Arguments
- `params::GBMParams`: GBM parameters (spot, rate, dividend, volatility, time)
- `n_paths::Int`: Number of paths to simulate
- `n_steps::Int`: Number of time steps per path
- `seed::Union{Int, Nothing}=nothing`: Random seed for reproducibility
- `antithetic::Bool=false`: Use antithetic variates for variance reduction
- `rng::Union{AbstractRNG, Nothing}=nothing`: Optional RNG (overrides seed if provided)

# Returns
- `PathResult`: Simulated paths and metadata

# Notes
Antithetic variates: For each standard normal Z, also use -Z.
This reduces variance without additional random numbers.
When antithetic=true, n_paths must be even.

# Example
```julia
params = GBMParams(100.0, 0.05, 0.02, 0.20, 1.0)
result = generate_gbm_paths(params, 10000, 252; seed=42)
mean(terminal_values(result))  # Should be close to forward price
```
"""
function generate_gbm_paths(
    params::GBMParams{T},
    n_paths::Int,
    n_steps::Int;
    seed::Union{Int, Nothing}=nothing,
    antithetic::Bool=false,
    rng::Union{AbstractRNG, Nothing}=nothing
) where T
    n_paths > 0 || throw(ArgumentError("CRITICAL: n_paths must be > 0, got $n_paths"))
    n_steps > 0 || throw(ArgumentError("CRITICAL: n_steps must be > 0, got $n_steps"))
    if antithetic
        n_paths % 2 == 0 || throw(ArgumentError("CRITICAL: n_paths must be even for antithetic, got $n_paths"))
    end

    # Initialize RNG
    if rng === nothing
        rng = seed === nothing ? StableRNG(42) : StableRNG(seed)
    end

    # Time discretization
    dt = params.time_to_expiry / n_steps
    sqrt_dt = sqrt(dt)
    times = collect(range(zero(T), params.time_to_expiry; length=n_steps + 1))

    # Drift and diffusion per step
    drift_per_step = drift(params) * dt
    vol_per_step = params.volatility * sqrt_dt

    if antithetic
        # Generate half the paths, use antithetic for other half
        half_paths = n_paths ÷ 2
        z = randn(rng, T, half_paths, n_steps)

        # Compute log-returns for original and antithetic
        log_returns = drift_per_step .+ vol_per_step .* z
        log_returns_anti = drift_per_step .- vol_per_step .* z  # -Z

        # Combine
        all_log_returns = vcat(log_returns, log_returns_anti)
    else
        # Generate all random numbers
        z = randn(rng, T, n_paths, n_steps)
        all_log_returns = drift_per_step .+ vol_per_step .* z
    end

    # Cumulative sum of log-returns
    cum_log_returns = cumsum(all_log_returns; dims=2)

    # Build paths: S(t) = S(0) × exp(cumulative log-returns)
    paths = Matrix{T}(undef, n_paths, n_steps + 1)
    paths[:, 1] .= params.spot
    paths[:, 2:end] .= params.spot .* exp.(cum_log_returns)

    return PathResult(paths, times, params, seed, antithetic)
end


"""
    generate_terminal_values(params, n_paths; seed=nothing, antithetic=false, rng=nothing) -> Vector

Generate only terminal values (faster for European options).

[T1] Direct simulation: S(T) = S(0) × exp((r - q - σ²/2)T + σ√T × Z)

# Arguments
- `params::GBMParams`: GBM parameters
- `n_paths::Int`: Number of paths
- `seed::Union{Int, Nothing}=nothing`: Random seed
- `antithetic::Bool=false`: Use antithetic variates
- `rng::Union{AbstractRNG, Nothing}=nothing`: Optional RNG

# Returns
- `Vector{T}`: Terminal values, length n_paths

# Notes
This is more efficient than `generate_gbm_paths` when only the terminal
value is needed (e.g., European option pricing).
"""
function generate_terminal_values(
    params::GBMParams{T},
    n_paths::Int;
    seed::Union{Int, Nothing}=nothing,
    antithetic::Bool=false,
    rng::Union{AbstractRNG, Nothing}=nothing
) where T
    n_paths > 0 || throw(ArgumentError("CRITICAL: n_paths must be > 0, got $n_paths"))
    if antithetic
        n_paths % 2 == 0 || throw(ArgumentError("CRITICAL: n_paths must be even for antithetic, got $n_paths"))
    end

    # Initialize RNG
    if rng === nothing
        rng = seed === nothing ? StableRNG(42) : StableRNG(seed)
    end

    τ = params.time_to_expiry
    sqrt_τ = sqrt(τ)
    total_drift = drift(params) * τ
    total_vol = params.volatility * sqrt_τ

    if antithetic
        half_paths = n_paths ÷ 2
        z = randn(rng, T, half_paths)
        z_all = vcat(z, -z)
    else
        z_all = randn(rng, T, n_paths)
    end

    log_returns = total_drift .+ total_vol .* z_all
    terminal_values = params.spot .* exp.(log_returns)

    return terminal_values
end


"""
    generate_paths_with_monthly_observations(params, n_paths; n_months=12, seed=nothing, antithetic=false) -> PathResult

Generate paths with monthly observation dates.

Useful for monthly averaging crediting methods (FIA).

# Arguments
- `params::GBMParams`: GBM parameters
- `n_paths::Int`: Number of paths
- `n_months::Int=12`: Number of monthly observations
- `seed::Union{Int, Nothing}=nothing`: Random seed
- `antithetic::Bool=false`: Use antithetic variates

# Returns
- `PathResult`: Paths with monthly observation points
"""
function generate_paths_with_monthly_observations(
    params::GBMParams{T},
    n_paths::Int;
    n_months::Int=12,
    seed::Union{Int, Nothing}=nothing,
    antithetic::Bool=false
) where T
    # Calculate steps needed for monthly observations
    # Assuming ~21 trading days per month
    steps_per_month = 21
    n_steps = n_months * steps_per_month

    result = generate_gbm_paths(params, n_paths, n_steps; seed=seed, antithetic=antithetic)

    # Extract monthly observations (every 21 steps)
    monthly_indices = 1:steps_per_month:(n_steps + 1)
    monthly_paths = result.paths[:, monthly_indices]
    monthly_times = result.times[monthly_indices]

    return PathResult(monthly_paths, monthly_times, params, seed, antithetic)
end


"""
    validate_gbm_simulation(params; n_paths=100000, seed=42) -> NamedTuple

Validate GBM simulation against theoretical moments.

[T1] Under risk-neutral measure:
- E[S(T)] = S(0) × exp((r-q)×T) (forward price)
- Var[log(S(T)/S(0))] = σ²T

# Arguments
- `params::GBMParams`: GBM parameters
- `n_paths::Int=100000`: Number of paths for validation
- `seed::Int=42`: Random seed

# Returns
- `NamedTuple`: Validation results with theoretical vs simulated values
"""
function validate_gbm_simulation(
    params::GBMParams{T};
    n_paths::Int=100000,
    seed::Int=42
) where T
    terminal = generate_terminal_values(params, n_paths; seed=seed, antithetic=true)

    # Theoretical values
    expected_mean = forward(params)
    expected_log_var = params.volatility^2 * params.time_to_expiry

    # Simulated values
    simulated_mean = mean(terminal)
    log_returns = log.(terminal ./ params.spot)
    simulated_log_var = var(log_returns)

    # Standard error (for confidence intervals)
    se_mean = std(terminal) / sqrt(n_paths)

    return (
        n_paths = n_paths,
        theoretical_mean = expected_mean,
        simulated_mean = simulated_mean,
        mean_error = abs(simulated_mean - expected_mean),
        mean_error_pct = abs(simulated_mean - expected_mean) / expected_mean * 100,
        mean_se = se_mean,
        mean_z_score = (simulated_mean - expected_mean) / se_mean,
        theoretical_log_variance = expected_log_var,
        simulated_log_variance = simulated_log_var,
        variance_error_pct = abs(simulated_log_var - expected_log_var) / expected_log_var * 100,
        validation_passed = abs(simulated_mean - expected_mean) / expected_mean < 0.01,
    )
end
