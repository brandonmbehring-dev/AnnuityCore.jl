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

## Behavioral Fields (optional)
- `lapse_config::Union{LapseConfig, SOALapseConfig, Nothing}`: Dynamic lapse model
- `withdrawal_config::Union{WithdrawalConfig, SOAWithdrawalConfig, Nothing}`: Utilization model
- `expense_config::Union{ExpenseConfig, Nothing}`: Expense model

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

# With behavioral models:
sim_behavioral = GLWBSimulator(
    config = GWBConfig(),
    lapse_config = SOALapseConfig(),
    withdrawal_config = SOAWithdrawalConfig(),
    expense_config = ExpenseConfig()
)
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
    # Behavioral configs (optional)
    lapse_config::Union{LapseConfig, SOALapseConfig, Nothing}
    withdrawal_config::Union{WithdrawalConfig, SOAWithdrawalConfig, Nothing}
    expense_config::Union{ExpenseConfig, Nothing}

    function GLWBSimulator(;
        config::GWBConfig = GWBConfig(),
        r::Float64 = 0.04,
        sigma::Float64 = 0.20,
        n_paths::Int = 10000,
        steps_per_year::Int = 1,
        mortality::Function = default_mortality,
        seed::Union{Int, Nothing} = nothing,
        lapse_config::Union{LapseConfig, SOALapseConfig, Nothing} = nothing,
        withdrawal_config::Union{WithdrawalConfig, SOAWithdrawalConfig, Nothing} = nothing,
        expense_config::Union{ExpenseConfig, Nothing} = nothing
    )
        r >= 0 || throw(ArgumentError("r must be >= 0"))
        sigma > 0 || throw(ArgumentError("sigma must be > 0"))
        n_paths > 0 || throw(ArgumentError("n_paths must be > 0"))
        steps_per_year > 0 || throw(ArgumentError("steps_per_year must be > 0"))

        new(config, r, sigma, n_paths, steps_per_year, mortality, seed,
            lapse_config, withdrawal_config, expense_config)
    end
end

# Helper functions
has_lapse_model(sim::GLWBSimulator) = sim.lapse_config !== nothing
has_withdrawal_model(sim::GLWBSimulator) = sim.withdrawal_config !== nothing
has_expense_model(sim::GLWBSimulator) = sim.expense_config !== nothing
has_behavioral_models(sim::GLWBSimulator) = has_lapse_model(sim) || has_withdrawal_model(sim) || has_expense_model(sim)


"""
    glwb_price(sim, premium, age; max_age=100, deferral_years=0) -> GLWBPricingResult

Price GLWB guarantee via Monte Carlo simulation.

[T1] Computes expected present value of insurer payments when account is depleted.

[T2] When behavioral models are enabled (via sim.lapse_config, sim.withdrawal_config,
sim.expense_config), the simulation incorporates:
- Dynamic lapse based on moneyness (SOA 2006 calibration)
- Withdrawal utilization based on age/duration/ITM (SOA 2018 calibration)
- Expense tracking for PV calculation

# Arguments
- `sim::GLWBSimulator`: Simulator configuration
- `premium::Float64`: Initial premium (sets initial GWB and AV)
- `age::Int`: Policyholder age at issue
- `max_age::Int=100`: Maximum simulation age
- `deferral_years::Int=0`: Years before withdrawals begin

# Returns
- `GLWBPricingResult`: Pricing result with price, risk metrics, and diagnostics.
  When behavioral models are enabled, includes avg_utilization, total_expenses_pv,
  and lapse_year_histogram.

# Example
```julia
sim = GLWBSimulator(n_paths=10000, sigma=0.20)
result = glwb_price(sim, 100000.0, 65)
println("Price: \$(result.price)")
println("Prob ruin: \$(result.prob_ruin)")

# With behavioral models:
sim_beh = GLWBSimulator(
    lapse_config = SOALapseConfig(),
    withdrawal_config = SOAWithdrawalConfig()
)
result = glwb_price(sim_beh, 100000.0, 65)
println("Avg utilization: \$(result.avg_utilization)")
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
    n_years = max_age - age

    # Pre-allocate result arrays
    payoffs = zeros(sim.n_paths)
    ruin_years = fill(-1.0, sim.n_paths)
    lapse_years = fill(-1.0, sim.n_paths)
    death_years = fill(-1.0, sim.n_paths)

    # Behavioral tracking arrays
    path_utilizations = Float64[]  # Track utilization rates
    path_expenses = zeros(sim.n_paths)  # PV of expenses per path
    lapse_year_counts = zeros(Int, n_years + 1)  # Histogram of lapse years

    # GBM parameters
    drift = (sim.r - 0.5 * sim.sigma^2) * dt
    diffusion = sim.sigma * sqrt(dt)

    # Determine surrender charge period end (for lapse model)
    sc_length = if has_lapse_model(sim) && sim.lapse_config isa SOALapseConfig
        sim.lapse_config.surrender_charge_length
    else
        7  # Default assumption
    end

    for path in 1:sim.n_paths
        # Initialize fresh state for each path
        state = GWBState(premium)
        pv_insurer = 0.0
        pv_expenses = 0.0
        ruined = false
        lapsed = false

        for step in 1:n_steps
            t_years = step * dt
            current_age = age + floor(Int, t_years)
            duration = floor(Int, t_years) + 1  # Contract year (1-indexed)

            # Skip if age exceeds table or already terminated
            if current_age > max_age || lapsed
                break
            end

            # Mortality check (at start of period)
            qx = sim.mortality(current_age)
            qx_step = 1.0 - (1.0 - qx)^dt
            if rand(rng) < qx_step
                death_years[path] = t_years
                break
            end

            # Lapse check (after mortality, before state evolution)
            if has_lapse_model(sim) && !ruined
                lapse_rate = _calculate_lapse_rate(
                    sim.lapse_config, state.gwb, state.av,
                    duration, sc_length, current_age
                )
                lapse_prob_step = 1.0 - (1.0 - lapse_rate)^dt
                if rand(rng) < lapse_prob_step
                    lapse_years[path] = t_years
                    lapsed = true
                    # Record in histogram
                    year_idx = min(duration, n_years + 1)
                    lapse_year_counts[year_idx] += 1
                    break
                end
            end

            # Market return (GBM)
            z = randn(rng)
            market_return = drift + diffusion * z

            # Withdrawal calculation (after deferral period)
            withdrawal = 0.0
            if t_years >= deferral_years && !ruined
                if has_withdrawal_model(sim)
                    # Use behavioral withdrawal model
                    moneyness = state.av > 0 ? (state.gwb / state.av) : 1.0
                    util_rate = _calculate_utilization_rate(
                        sim.withdrawal_config, state.gwb, state.av,
                        duration, current_age, moneyness
                    )
                    max_withdrawal = state.gwb * sim.config.withdrawal_rate * dt
                    withdrawal = util_rate * max_withdrawal
                    push!(path_utilizations, util_rate)
                else
                    # Fixed withdrawal rate (original behavior)
                    withdrawal = state.gwb * sim.config.withdrawal_rate * dt
                end
            end

            # Expense calculation
            if has_expense_model(sim)
                year_idx = duration - 1  # 0-indexed for expense calc
                expense_result = calculate_expense(sim.expense_config, state.av, year_idx)
                expense_step = expense_result.total_expense * dt  # Prorate for timestep
                df = exp(-sim.r * t_years)
                pv_expenses += expense_step * df
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
        path_expenses[path] = pv_expenses
    end

    # Aggregate results
    mean_payoff = mean(payoffs)
    std_payoff = std(payoffs)

    # Ruin statistics
    ruin_mask = ruin_years .> 0
    prob_ruin = sum(ruin_mask) / sim.n_paths
    mean_ruin_year = prob_ruin > 0 ? mean(ruin_years[ruin_mask]) : 0.0

    # Lapse statistics
    lapse_mask = lapse_years .> 0
    prob_lapse = sum(lapse_mask) / sim.n_paths
    mean_lapse_year = prob_lapse > 0 ? mean(lapse_years[lapse_mask]) : 0.0

    # Behavioral metrics
    avg_utilization = if !isempty(path_utilizations)
        mean(path_utilizations)
    else
        nothing
    end

    total_expenses_pv = if has_expense_model(sim)
        mean(path_expenses)
    else
        nothing
    end

    lapse_histogram = if has_lapse_model(sim)
        lapse_year_counts
    else
        nothing
    end

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
        sim.n_paths,
        avg_utilization,
        total_expenses_pv,
        lapse_histogram
    )
end


# =============================================================================
# Behavioral Model Helpers (internal)
# =============================================================================

"""
    _calculate_lapse_rate(config, gwb, av, duration, sc_length, age) -> Float64

Calculate lapse rate using the configured lapse model.
"""
function _calculate_lapse_rate(
    config::LapseConfig,
    gwb::Real,
    av::Real,
    duration::Int,
    sc_length::Int,
    age::Int
)
    # Simple model: just needs surrender period status
    surrender_complete = duration > sc_length
    result = calculate_lapse(config, gwb, av; surrender_period_complete=surrender_complete)
    return result.lapse_rate
end

function _calculate_lapse_rate(
    config::SOALapseConfig,
    gwb::Real,
    av::Real,
    duration::Int,
    sc_length::Int,
    age::Int
)
    # SOA model: needs duration and years to SC end
    years_to_sc_end = config.surrender_charge_length - duration + 1
    result = calculate_lapse(config, gwb, av, duration, years_to_sc_end; age=age)
    return result.lapse_rate
end


"""
    _calculate_utilization_rate(config, gwb, av, duration, age, moneyness) -> Float64

Calculate withdrawal utilization rate using the configured model.
"""
function _calculate_utilization_rate(
    config::WithdrawalConfig,
    gwb::Real,
    av::Real,
    duration::Int,
    age::Int,
    moneyness::Real
)
    # Simple model uses age-based adjustment
    result = calculate_withdrawal(config, gwb, av, 1.0, age)  # Use rate=1.0 to get pure utilization
    return result.utilization_rate
end

function _calculate_utilization_rate(
    config::SOAWithdrawalConfig,
    gwb::Real,
    av::Real,
    duration::Int,
    age::Int,
    moneyness::Real
)
    # SOA model uses duration, age, and ITM
    result = calculate_withdrawal(config, gwb, av, 1.0, duration, age; moneyness=moneyness)
    return result.utilization_rate
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
            seed = sim.seed,
            lapse_config = sim.lapse_config,
            withdrawal_config = sim.withdrawal_config,
            expense_config = sim.expense_config
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
        mortality = sim.mortality, seed = sim.seed,
        lapse_config = sim.lapse_config, withdrawal_config = sim.withdrawal_config,
        expense_config = sim.expense_config
    )
    vega = glwb_price(sim_vol_up, premium, age; kwargs...).price - base_price

    # Rho (rate bump of 1%)
    sim_rate_up = GLWBSimulator(
        config = sim.config, r = sim.r + 0.01, sigma = sim.sigma,
        n_paths = sim.n_paths, steps_per_year = sim.steps_per_year,
        mortality = sim.mortality, seed = sim.seed,
        lapse_config = sim.lapse_config, withdrawal_config = sim.withdrawal_config,
        expense_config = sim.expense_config
    )
    rho = glwb_price(sim_rate_up, premium, age; kwargs...).price - base_price

    # Age sensitivity (1 year older)
    age_sens = glwb_price(sim, premium, age + 1; kwargs...).price - base_price

    return (vega = vega, rho = rho, age_sensitivity = age_sens)
end
