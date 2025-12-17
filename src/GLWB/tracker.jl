"""
GLWB State Machine Tracker.

[T1] The GWBTracker implements the state evolution for GLWB benefits.
Each timestep processes:
1. Market return on account value
2. Fee deduction
3. Rollup application (if in deferral phase)
4. Ratchet step-up (on anniversaries)
5. Withdrawal processing

The tracker maintains both the guarantee (GWB) and actual value (AV)
through the contract lifetime.
"""


"""
    step!(state, config, market_return, withdrawal, dt) -> StepResult

Evolve GWB state forward by one timestep.

[T1] Core state transition function implementing GLWB mechanics.

# Arguments
- `state::GWBState`: Current state (modified in place)
- `config::GWBConfig`: Benefit configuration
- `market_return::Float64`: Market return this period (e.g., 0.01 for 1%)
- `withdrawal::Float64`: Withdrawal amount requested
- `dt::Float64`: Timestep size in years

# Returns
- `StepResult`: Details of the step (fees, rollup, ratchet, withdrawal)

# State Evolution Order
1. Apply market return to AV
2. Charge fee (based on GWB or AV per config)
3. Apply rollup (if not in withdrawal phase)
4. Apply ratchet (on anniversary dates)
5. Process withdrawal (may reduce GWB if excess)
6. Update time counter

# Example
```julia
state = GWBState(100000.0)
config = GWBConfig()
result = step!(state, config, 0.05, 0.0, 1/12)  # Monthly step, 5% return
```
"""
function step!(
    state::GWBState,
    config::GWBConfig,
    market_return::Float64,
    withdrawal::Float64,
    dt::Float64
)
    # 1. Apply market return to AV
    state.av *= (1.0 + market_return)

    # 2. Charge fee (basis: gwb or av)
    fee_base = config.fee_basis == :gwb ? state.gwb : state.av
    fee = config.fee_rate * fee_base * dt
    state.av = max(state.av - fee, 0.0)

    # 3. Apply rollup (if not in withdrawal phase)
    rollup_amount = 0.0
    if !state.withdrawal_phase_started && config.rollup_type != NONE
        old_gwb = state.gwb
        state.gwb = calculate_rollup(state, config)
        rollup_amount = state.gwb - old_gwb
    end

    # 4. Apply ratchet (on anniversary)
    ratchet_applied = false
    if config.ratchet_enabled && is_anniversary(state.years_since_issue, dt)
        if state.av > state.gwb
            state.gwb = state.av
            state.high_water_mark = state.av
            ratchet_applied = true
        end
    end

    # 5. Process withdrawal
    if withdrawal > 0
        state.withdrawal_phase_started = true
    end

    # Calculate max withdrawal for this period
    max_withdrawal = state.gwb * config.withdrawal_rate * dt
    actual_withdrawal = min(withdrawal, state.av)

    # Excess withdrawal reduces GWB proportionally
    if actual_withdrawal > max_withdrawal && state.gwb > 0
        excess = actual_withdrawal - max_withdrawal
        gwb_reduction = excess / state.gwb
        state.gwb *= (1.0 - gwb_reduction)
    end

    state.av = max(state.av - actual_withdrawal, 0.0)
    state.total_withdrawals += actual_withdrawal

    # 6. Update time
    state.years_since_issue += dt

    return StepResult(fee, rollup_amount, ratchet_applied, actual_withdrawal, max_withdrawal)
end


"""
    max_withdrawal(state, config, dt) -> Float64

Calculate maximum withdrawal allowed for a given period.

# Arguments
- `state::GWBState`: Current state
- `config::GWBConfig`: Benefit configuration
- `dt::Float64`: Timestep size in years

# Returns
- `Float64`: Maximum withdrawal amount
"""
function max_withdrawal(state::GWBState, config::GWBConfig, dt::Float64)
    return state.gwb * config.withdrawal_rate * dt
end


"""
    simulate_path!(state, config, returns, withdrawals, dt) -> Vector{StepResult}

Simulate an entire path of state evolution.

# Arguments
- `state::GWBState`: Initial state (modified in place)
- `config::GWBConfig`: Benefit configuration
- `returns::Vector{Float64}`: Market returns per period
- `withdrawals::Vector{Float64}`: Withdrawal amounts per period
- `dt::Float64`: Timestep size in years

# Returns
- `Vector{StepResult}`: Results for each step
"""
function simulate_path!(
    state::GWBState,
    config::GWBConfig,
    returns::Vector{Float64},
    withdrawals::Vector{Float64},
    dt::Float64
)
    n_steps = length(returns)
    length(withdrawals) == n_steps || throw(ArgumentError("returns and withdrawals must have same length"))

    results = Vector{StepResult}(undef, n_steps)

    for i in 1:n_steps
        results[i] = step!(state, config, returns[i], withdrawals[i], dt)
    end

    return results
end


"""
    is_ruined(state) -> Bool

Check if account value is depleted (ruin state).

[T1] Ruin occurs when AV <= 0. After ruin, the insurer makes
guaranteed payments equal to max withdrawal for life.
"""
function is_ruined(state::GWBState)
    return state.av <= 0
end


"""
    benefit_moneyness(state) -> Float64

Calculate benefit moneyness: (GWB - AV) / GWB.

[T1] Moneyness > 0 indicates the guarantee is "in the money"
(GWB exceeds AV, making guarantee valuable).

Used for dynamic lapse modeling - higher moneyness = lower lapse probability.
"""
function benefit_moneyness(state::GWBState)
    if state.gwb <= 0
        return 0.0
    end
    return (state.gwb - state.av) / state.gwb
end


"""
    gwb_to_av_ratio(state) -> Float64

Calculate GWB to AV ratio.

Ratio > 1 means guarantee exceeds account value.
"""
function gwb_to_av_ratio(state::GWBState)
    if state.av <= 0
        return state.gwb > 0 ? Inf : 1.0
    end
    return state.gwb / state.av
end
