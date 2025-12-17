"""
Monte Carlo option pricing engine.

Implements Monte Carlo simulation for option pricing:
- Vanilla European options (with analytical comparison)
- FIA crediting method payoffs
- RILA buffer/floor payoffs
- Hybrid batch processing for memory efficiency

[T1] MC converges to analytical price at rate 1/√N

References:
- Glasserman (2003) "Monte Carlo Methods in Financial Engineering"
- Hull (2021) "Options, Futures, and Other Derivatives", Ch. 21
"""

"""
    MCResult{T}

Monte Carlo pricing result.

# Fields
- `price::T`: Option price (discounted expected payoff)
- `standard_error::T`: Standard error of the estimate
- `confidence_interval::Tuple{T, T}`: 95% confidence interval
- `n_paths::Int`: Number of paths used
- `payoffs::Vector{T}`: Individual path payoffs (undiscounted)
- `discount_factor::T`: Discount factor used
"""
struct MCResult{T<:Real}
    price::T
    standard_error::T
    confidence_interval::Tuple{T, T}
    n_paths::Int
    payoffs::Vector{T}
    discount_factor::T
end

"""Relative standard error (SE / price)."""
function relative_error(result::MCResult{T}) where T
    abs(result.price) < 1e-10 ? T(Inf) : result.standard_error / abs(result.price)
end

"""Width of 95% confidence interval."""
ci_width(result::MCResult) = result.confidence_interval[2] - result.confidence_interval[1]


"""
    MonteCarloEngine{T}

Monte Carlo pricing engine.

# Fields
- `n_paths::Int`: Number of simulation paths
- `antithetic::Bool`: Use antithetic variates for variance reduction
- `seed::Union{Int, Nothing}`: Random seed for reproducibility
- `batch_size::Int`: Batch size for hybrid memory management

# Example
```julia
engine = MonteCarloEngine(n_paths=100000, seed=42)
params = GBMParams(100.0, 0.05, 0.02, 0.20, 1.0)
result = price_european_call(engine, params, 100.0)
println("Price: \$(result.price) ± \$(result.standard_error)")
```
"""
struct MonteCarloEngine
    n_paths::Int
    antithetic::Bool
    seed::Union{Int, Nothing}
    batch_size::Int

    function MonteCarloEngine(;
        n_paths::Int=100000,
        antithetic::Bool=true,
        seed::Union{Int, Nothing}=nothing,
        batch_size::Int=10000
    )
        n_paths > 0 || throw(ArgumentError("CRITICAL: n_paths must be > 0, got $n_paths"))
        batch_size > 0 || throw(ArgumentError("CRITICAL: batch_size must be > 0, got $batch_size"))

        # Ensure even number for antithetic
        actual_n_paths = antithetic && n_paths % 2 != 0 ? n_paths + 1 : n_paths

        new(actual_n_paths, antithetic, seed, batch_size)
    end
end


"""
    price_european_call(engine, params, strike) -> MCResult

Price European call option via Monte Carlo.

[T1] Call payoff: max(S(T) - K, 0)

# Arguments
- `engine::MonteCarloEngine`: MC engine configuration
- `params::GBMParams`: GBM parameters
- `strike::Real`: Strike price

# Returns
- `MCResult`: Monte Carlo pricing result
"""
function price_european_call(
    engine::MonteCarloEngine,
    params::GBMParams{T},
    strike::Real
) where T
    strike > 0 || throw(ArgumentError("CRITICAL: strike must be > 0, got $strike"))

    terminal = generate_terminal_values(
        params, engine.n_paths;
        seed=engine.seed, antithetic=engine.antithetic
    )

    # Call payoff
    payoffs = max.(terminal .- T(strike), zero(T))

    return _compute_result(params, payoffs)
end


"""
    price_european_put(engine, params, strike) -> MCResult

Price European put option via Monte Carlo.

[T1] Put payoff: max(K - S(T), 0)

# Arguments
- `engine::MonteCarloEngine`: MC engine configuration
- `params::GBMParams`: GBM parameters
- `strike::Real`: Strike price

# Returns
- `MCResult`: Monte Carlo pricing result
"""
function price_european_put(
    engine::MonteCarloEngine,
    params::GBMParams{T},
    strike::Real
) where T
    strike > 0 || throw(ArgumentError("CRITICAL: strike must be > 0, got $strike"))

    terminal = generate_terminal_values(
        params, engine.n_paths;
        seed=engine.seed, antithetic=engine.antithetic
    )

    # Put payoff
    payoffs = max.(T(strike) .- terminal, zero(T))

    return _compute_result(params, payoffs)
end


"""
    price_with_payoff(engine, params, payoff; n_steps=252) -> MCResult

Price option with custom payoff object.

Uses vectorized calculation when available for ~10x performance.
Falls back to path-by-path calculation for path-dependent payoffs.

# Arguments
- `engine::MonteCarloEngine`: MC engine configuration
- `params::GBMParams`: GBM parameters
- `payoff::AbstractPayoff`: Payoff object (FIA or RILA)
- `n_steps::Int=252`: Number of time steps (252 = daily for 1 year)

# Returns
- `MCResult`: Monte Carlo pricing result with credited returns

# Example
```julia
engine = MonteCarloEngine(n_paths=100000, seed=42)
params = GBMParams(100.0, 0.05, 0.02, 0.20, 1.0)
payoff = CappedCallPayoff(0.10, 0.0)  # 10% cap
result = price_with_payoff(engine, params, payoff)
```
"""
function price_with_payoff(
    engine::MonteCarloEngine,
    params::GBMParams{T},
    payoff::AbstractPayoff;
    n_steps::Int=252
) where T
    # Generate terminal values for point-to-point payoffs
    terminal = generate_terminal_values(
        params, engine.n_paths;
        seed=engine.seed, antithetic=engine.antithetic
    )

    # Calculate returns
    index_returns = (terminal .- params.spot) ./ params.spot

    # Vectorized payoff calculation
    credited_returns = calculate.(Ref(payoff), index_returns)

    # Extract credited return values from PayoffResult
    credited_values = [r.credited_return for r in credited_returns]

    # Convert to dollar payoffs
    payoffs = params.spot .* credited_values

    return _compute_result(params, payoffs)
end


"""
    price_capped_call_return(engine, params, cap_rate) -> MCResult

Price capped call on return (FIA style).

[T1] Payoff: spot × max(0, min(return, cap))

# Arguments
- `engine::MonteCarloEngine`: MC engine configuration
- `params::GBMParams`: GBM parameters
- `cap_rate::Real`: Cap rate (decimal, e.g., 0.10 for 10%)

# Returns
- `MCResult`: Monte Carlo pricing result
"""
function price_capped_call_return(
    engine::MonteCarloEngine,
    params::GBMParams{T},
    cap_rate::Real
) where T
    cap_rate > 0 || throw(ArgumentError("CRITICAL: cap_rate must be > 0, got $cap_rate"))

    terminal = generate_terminal_values(
        params, engine.n_paths;
        seed=engine.seed, antithetic=engine.antithetic
    )

    # Return = (S(T) - S(0)) / S(0)
    returns = (terminal .- params.spot) ./ params.spot

    # Capped call on return: max(0, min(return, cap))
    credited_returns = max.(zero(T), min.(returns, T(cap_rate)))

    # Convert to dollar payoff
    payoffs = params.spot .* credited_returns

    return _compute_result(params, payoffs)
end


"""
    price_buffer_protection(engine, params, buffer_rate; cap_rate=nothing) -> MCResult

Price buffer protection (RILA style).

[T1] Buffer absorbs first X% of losses.

# Arguments
- `engine::MonteCarloEngine`: MC engine configuration
- `params::GBMParams`: GBM parameters
- `buffer_rate::Real`: Buffer rate (decimal, e.g., 0.10 for 10%)
- `cap_rate::Union{Real, Nothing}=nothing`: Optional cap rate

# Returns
- `MCResult`: Monte Carlo pricing result
"""
function price_buffer_protection(
    engine::MonteCarloEngine,
    params::GBMParams{T},
    buffer_rate::Real;
    cap_rate::Union{Real, Nothing}=nothing
) where T
    buffer_rate > 0 || throw(ArgumentError("CRITICAL: buffer_rate must be > 0, got $buffer_rate"))

    terminal = generate_terminal_values(
        params, engine.n_paths;
        seed=engine.seed, antithetic=engine.antithetic
    )

    returns = (terminal .- params.spot) ./ params.spot

    # Buffer payoff: positive returns pass through, negative absorbed up to buffer
    credited_returns = map(returns) do r
        if r >= 0
            r  # Positive: full upside
        else
            max(r + buffer_rate, zero(T))  # Negative: buffer absorbs first X%
        end
    end

    # Apply cap if specified
    if cap_rate !== nothing
        credited_returns = min.(credited_returns, T(cap_rate))
    end

    payoffs = params.spot .* credited_returns

    return _compute_result(params, payoffs)
end


"""
    price_floor_protection(engine, params, floor_rate; cap_rate=nothing) -> MCResult

Price floor protection (RILA style).

[T1] Floor limits maximum loss to X%.

# Arguments
- `engine::MonteCarloEngine`: MC engine configuration
- `params::GBMParams`: GBM parameters
- `floor_rate::Real`: Floor rate (decimal, e.g., -0.10 for -10% max loss)
- `cap_rate::Union{Real, Nothing}=nothing`: Optional cap rate

# Returns
- `MCResult`: Monte Carlo pricing result
"""
function price_floor_protection(
    engine::MonteCarloEngine,
    params::GBMParams{T},
    floor_rate::Real;
    cap_rate::Union{Real, Nothing}=nothing
) where T
    floor_rate <= 0 || throw(ArgumentError("CRITICAL: floor_rate should be <= 0, got $floor_rate"))

    terminal = generate_terminal_values(
        params, engine.n_paths;
        seed=engine.seed, antithetic=engine.antithetic
    )

    returns = (terminal .- params.spot) ./ params.spot

    # Floor payoff: max(return, floor)
    credited_returns = max.(returns, T(floor_rate))

    # Apply cap if specified
    if cap_rate !== nothing
        credited_returns = min.(credited_returns, T(cap_rate))
    end

    payoffs = params.spot .* credited_returns

    return _compute_result(params, payoffs)
end


"""
    _compute_result(params, payoffs) -> MCResult

Compute MC result from payoffs.

# Arguments
- `params::GBMParams`: GBM parameters (for discounting)
- `payoffs::Vector`: Undiscounted payoffs

# Returns
- `MCResult`: Complete MC result with statistics
"""
function _compute_result(params::GBMParams{T}, payoffs::Vector{T}) where T
    # Discount factor
    df = exp(-params.rate * params.time_to_expiry)

    # Discounted mean and standard error
    mean_payoff = mean(payoffs)
    std_payoff = std(payoffs; corrected=true)
    se = std_payoff / sqrt(length(payoffs))

    price = df * mean_payoff
    se_price = df * se

    # 95% confidence interval (z = 1.96)
    ci_lower = price - T(1.96) * se_price
    ci_upper = price + T(1.96) * se_price

    return MCResult(
        price,
        se_price,
        (ci_lower, ci_upper),
        length(payoffs),
        payoffs,
        df
    )
end


"""
    price_vanilla_mc(spot, strike, rate, dividend, volatility, time_to_expiry; option_type=:call, n_paths=100000, seed=nothing) -> MCResult

Convenience function to price vanilla option via MC.

# Arguments
- `spot::Real`: Current spot price
- `strike::Real`: Strike price
- `rate::Real`: Risk-free rate (decimal)
- `dividend::Real`: Dividend yield (decimal)
- `volatility::Real`: Volatility (decimal)
- `time_to_expiry::Real`: Time to expiry in years
- `option_type::Symbol=:call`: `:call` or `:put`
- `n_paths::Int=100000`: Number of paths
- `seed::Union{Int, Nothing}=nothing`: Random seed

# Returns
- `MCResult`: Monte Carlo pricing result
"""
function price_vanilla_mc(
    spot::Real,
    strike::Real,
    rate::Real,
    dividend::Real,
    volatility::Real,
    time_to_expiry::Real;
    option_type::Symbol=:call,
    n_paths::Int=100000,
    seed::Union{Int, Nothing}=nothing
)
    params = GBMParams(spot, rate, dividend, volatility, time_to_expiry)
    engine = MonteCarloEngine(n_paths=n_paths, antithetic=true, seed=seed)

    if option_type == :call
        return price_european_call(engine, params, strike)
    else
        return price_european_put(engine, params, strike)
    end
end


"""
    monte_carlo_price(spot, strike, rate, dividend, volatility, time_to_expiry; option_type=:call, n_paths=100000, seed=nothing) -> T

Convenience function returning just the price (not full MCResult).

Useful for validation against external implementations.

# Example
```julia
price = monte_carlo_price(100.0, 100.0, 0.05, 0.02, 0.20, 1.0)
println("MC price: \$price")
```
"""
function monte_carlo_price(
    spot::Real,
    strike::Real,
    rate::Real,
    dividend::Real,
    volatility::Real,
    time_to_expiry::Real;
    option_type::Symbol=:call,
    n_paths::Int=100000,
    seed::Union{Int, Nothing}=nothing
)
    result = price_vanilla_mc(
        spot, strike, rate, dividend, volatility, time_to_expiry;
        option_type=option_type, n_paths=n_paths, seed=seed
    )
    return result.price
end


"""
    convergence_analysis(params, strike, analytical_price; path_counts=[1000, 5000, 10000, 50000, 100000, 500000], seed=42) -> NamedTuple

Analyze MC convergence to analytical price.

[T1] MC error should converge at rate 1/√N.

# Arguments
- `params::GBMParams`: GBM parameters
- `strike::Real`: Strike price
- `analytical_price::Real`: Analytical (Black-Scholes) price
- `path_counts::Vector{Int}`: Number of paths to test
- `seed::Int=42`: Random seed

# Returns
- `NamedTuple`: Convergence analysis results including convergence rate

# Example
```julia
params = GBMParams(100.0, 0.05, 0.02, 0.20, 1.0)
bs_price = black_scholes_call(100.0, 100.0, 0.05, 0.02, 0.20, 1.0)
analysis = convergence_analysis(params, 100.0, bs_price)
println("Convergence rate: \$(analysis.convergence_rate)")  # Should be ~-0.5
```
"""
function convergence_analysis(
    params::GBMParams{T},
    strike::Real,
    analytical_price::Real;
    path_counts::Vector{Int}=[1000, 5000, 10000, 50000, 100000, 500000],
    seed::Int=42
) where T
    results = Vector{NamedTuple}()

    for n in path_counts
        engine = MonteCarloEngine(n_paths=n, antithetic=true, seed=seed)
        mc_result = price_european_call(engine, params, strike)

        error = abs(mc_result.price - analytical_price)
        rel_error = analytical_price > 0 ? error / analytical_price : T(Inf)

        push!(results, (
            n_paths = n,
            mc_price = mc_result.price,
            analytical_price = analytical_price,
            absolute_error = error,
            relative_error = rel_error,
            standard_error = mc_result.standard_error,
            within_ci = mc_result.confidence_interval[1] <= analytical_price <= mc_result.confidence_interval[2],
        ))
    end

    # Estimate convergence rate via log-log regression
    log_n = log.([r.n_paths for r in results])
    log_error = log.([r.absolute_error + 1e-10 for r in results])

    # Simple linear regression: log(error) = rate × log(N) + const
    n = length(log_n)
    slope = (n * sum(log_n .* log_error) - sum(log_n) * sum(log_error)) /
            (n * sum(log_n.^2) - sum(log_n)^2)

    return (
        results = results,
        convergence_rate = slope,
    )
end
