"""
GLWB Monte Carlo Path Simulator.

[T1] Path-dependent pricing for GLWB guarantees via Monte Carlo simulation.

The simulator:
1. Generates market paths (GBM)
2. Applies mortality decrement
3. Evolves GWB state through time
4. Tracks insurer payments post-ruin
5. Discounts and aggregates payoffs

Reference:
- Bauer, Kling & Russ (2008), "Universal Pricing of Guaranteed Minimum Benefits"
"""


"""
    GLWBSimulator

Monte Carlo simulator for GLWB pricing.

# Fields
- `config::GWBConfig`: Benefit configuration
- `r::Float64`: Risk-free rate (annual)
- `sigma::Float64`: Volatility (annual)
- `n_paths::Int`: Number of simulation paths
- `steps_per_year::Int`: Timesteps per year (1=annual, 12=monthly)
- `mortality::Function`: Mortality function qx(age) -> annual death prob
- `seed::Union{Int, Nothing}`: Random seed for reproducibility

# Example
```julia
sim = GLWBSimulator(
    config = GWBConfig(),
    r = 0.04,
    sigma = 0.20,
    n_paths = 10000,
    steps_per_year = 12
)
result = glwb_price(sim, 100000.0, 65)
```
"""
struct GLWBSimulator
    config::GWBConfig
    r::Float64
    sigma::Float64
    n_paths::Int
    steps_per_year::Int
    mortality::Function
    seed::Union{Int, Nothing}

    function GLWBSimulator(;
        config::GWBConfig = GWBConfig(),
        r::Float64 = 0.04,
        sigma::Float64 = 0.20,
        n_paths::Int = 10000,
        steps_per_year::Int = 1,
        mortality::Function = default_mortality,
        seed::Union{Int, Nothing} = nothing
    )
        r >= 0 || throw(ArgumentError("r must be >= 0"))
        sigma > 0 || throw(ArgumentError("sigma must be > 0"))
        n_paths > 0 || throw(ArgumentError("n_paths must be > 0"))
        steps_per_year > 0 || throw(ArgumentError("steps_per_year must be > 0"))

        new(config, r, sigma, n_paths, steps_per_year, mortality, seed)
    end
end


"""
    glwb_price(sim, premium, age; max_age=100, deferral_years=0) -> GLWBPricingResult

Price GLWB guarantee via Monte Carlo simulation.

[T1] Computes expected present value of insurer payments when account is depleted.

# Arguments
- `sim::GLWBSimulator`: Simulator configuration
- `premium::Float64`: Initial premium (sets initial GWB and AV)
- `age::Int`: Policyholder age at issue
- `max_age::Int=100`: Maximum simulation age
- `deferral_years::Int=0`: Years before withdrawals begin

# Returns
- `GLWBPricingResult`: Pricing result with price, risk metrics, and diagnostics

# Example
```julia
sim = GLWBSimulator(n_paths=10000, sigma=0.20)
result = glwb_price(sim, 100000.0, 65)
println("Price: \$(result.price)")
println("Prob ruin: \$(result.prob_ruin)")
```
"""
function glwb_price(
    sim::GLWBSimulator,
    premium::Float64,
    age::Int;
    max_age::Int = 100,
    deferral_years::Int = 0
)
    rng = sim.seed === nothing ? StableRNG(42) : StableRNG(sim.seed)

    dt = 1.0 / sim.steps_per_year
    n_steps = (max_age - age) * sim.steps_per_year

    # Pre-allocate result arrays
    payoffs = zeros(sim.n_paths)
    ruin_years = fill(-1.0, sim.n_paths)
    lapse_years = fill(-1.0, sim.n_paths)
    death_years = fill(-1.0, sim.n_paths)

    # GBM parameters
    drift = (sim.r - 0.5 * sim.sigma^2) * dt
    diffusion = sim.sigma * sqrt(dt)

    for path in 1:sim.n_paths
        # Initialize fresh state for each path
        state = GWBState(premium)
        pv_insurer = 0.0
        ruined = false

        for step in 1:n_steps
            t_years = step * dt
            current_age = age + floor(Int, t_years)

            # Skip if age exceeds table
            if current_age > max_age
                break
            end

            # Mortality check (at start of period)
            qx = sim.mortality(current_age)
            qx_step = 1.0 - (1.0 - qx)^dt
            if rand(rng) < qx_step
                death_years[path] = t_years
                break
            end

            # Market return (GBM)
            z = randn(rng)
            market_return = drift + diffusion * z

            # Withdrawal (after deferral period)
            withdrawal = 0.0
            if t_years >= deferral_years
                withdrawal = state.gwb * sim.config.withdrawal_rate * dt
            end

            # Step state forward
            step!(state, sim.config, market_return, withdrawal, dt)

            # Ruin detection (first occurrence)
            if state.av <= 0 && !ruined
                ruin_years[path] = t_years
                ruined = true
            end

            # Insurer payment (if ruined, insurer pays guaranteed amount)
            if ruined && t_years >= deferral_years
                df = exp(-sim.r * t_years)
                guaranteed_payment = state.gwb * sim.config.withdrawal_rate * dt
                pv_insurer += guaranteed_payment * df
            end
        end

        payoffs[path] = pv_insurer
    end

    # Aggregate results
    mean_payoff = mean(payoffs)
    std_payoff = std(payoffs)

    # Ruin statistics
    ruin_mask = ruin_years .> 0
    prob_ruin = sum(ruin_mask) / sim.n_paths
    mean_ruin_year = prob_ruin > 0 ? mean(ruin_years[ruin_mask]) : 0.0

    # Lapse statistics (not implemented - placeholder)
    lapse_mask = lapse_years .> 0
    prob_lapse = sum(lapse_mask) / sim.n_paths
    mean_lapse_year = prob_lapse > 0 ? mean(lapse_years[lapse_mask]) : 0.0

    return GLWBPricingResult(
        mean_payoff,
        mean_payoff / premium,
        mean_payoff,
        std_payoff,
        std_payoff / sqrt(sim.n_paths),
        prob_ruin,
        mean_ruin_year,
        prob_lapse,
        mean_lapse_year,
        sim.n_paths
    )
end


"""
    calculate_fair_fee(sim, premium, age; kwargs...) -> Float64

Find the fee rate that makes guarantee cost approximately zero.

[T1] Uses bisection search to find break-even fee.

# Arguments
- `sim::GLWBSimulator`: Base simulator (fee will be varied)
- `premium::Float64`: Initial premium
- `age::Int`: Policyholder age
- `target_cost::Float64=0.0`: Target guarantee cost (default: 0 for fair value)
- `tol::Float64=0.0001`: Convergence tolerance
- `max_iter::Int=50`: Maximum iterations

# Returns
- `Float64`: Fair fee rate (annual)
"""
function calculate_fair_fee(
    sim::GLWBSimulator,
    premium::Float64,
    age::Int;
    target_cost::Float64 = 0.0,
    tol::Float64 = 0.0001,
    max_iter::Int = 50,
    kwargs...
)
    fee_low = 0.001   # 0.1%
    fee_high = 0.03   # 3.0%

    for _ in 1:max_iter
        fee_mid = (fee_low + fee_high) / 2

        # Create simulator with trial fee
        config_trial = GWBConfig(
            rollup_type = sim.config.rollup_type,
            rollup_rate = sim.config.rollup_rate,
            rollup_cap_years = sim.config.rollup_cap_years,
            withdrawal_rate = sim.config.withdrawal_rate,
            fee_rate = fee_mid,
            ratchet_enabled = sim.config.ratchet_enabled,
            fee_basis = sim.config.fee_basis
        )
        sim_trial = GLWBSimulator(
            config = config_trial,
            r = sim.r,
            sigma = sim.sigma,
            n_paths = sim.n_paths,
            steps_per_year = sim.steps_per_year,
            mortality = sim.mortality,
            seed = sim.seed
        )

        result = glwb_price(sim_trial, premium, age; kwargs...)
        cost = result.guarantee_cost

        if abs(cost - target_cost) < tol
            return fee_mid
        elseif cost > target_cost
            fee_low = fee_mid  # Need higher fee to reduce cost
        else
            fee_high = fee_mid  # Need lower fee to increase cost
        end
    end

    return (fee_low + fee_high) / 2  # Return best estimate
end


"""
    sensitivity_analysis(sim, premium, age; kwargs...) -> NamedTuple

Compute Greeks-like sensitivities for GLWB.

# Returns
NamedTuple with:
- `vega::Float64`: Price sensitivity to volatility (per 1%)
- `rho::Float64`: Price sensitivity to interest rate (per 1%)
- `age_sens::Float64`: Price sensitivity to age (per year)
"""
function sensitivity_analysis(
    sim::GLWBSimulator,
    premium::Float64,
    age::Int;
    kwargs...
)
    # Base price
    base_result = glwb_price(sim, premium, age; kwargs...)
    base_price = base_result.price

    # Vega (volatility bump of 1%)
    sim_vol_up = GLWBSimulator(
        config = sim.config, r = sim.r, sigma = sim.sigma + 0.01,
        n_paths = sim.n_paths, steps_per_year = sim.steps_per_year,
        mortality = sim.mortality, seed = sim.seed
    )
    vega = glwb_price(sim_vol_up, premium, age; kwargs...).price - base_price

    # Rho (rate bump of 1%)
    sim_rate_up = GLWBSimulator(
        config = sim.config, r = sim.r + 0.01, sigma = sim.sigma,
        n_paths = sim.n_paths, steps_per_year = sim.steps_per_year,
        mortality = sim.mortality, seed = sim.seed
    )
    rho = glwb_price(sim_rate_up, premium, age; kwargs...).price - base_price

    # Age sensitivity (1 year older)
    age_sens = glwb_price(sim, premium, age + 1; kwargs...).price - base_price

    return (vega = vega, rho = rho, age_sensitivity = age_sens)
end
