"""
GLWB Core Types and Data Structures.

[T1] Guaranteed Lifetime Withdrawal Benefit (GLWB) provides income guarantees
for variable annuities. The policyholder can withdraw a fixed percentage of
the Guaranteed Withdrawal Base (GWB) annually for life.

Key concepts:
- GWB (Guaranteed Withdrawal Base): Benefit basis for withdrawals
- AV (Account Value): Actual investment value
- Rollup: GWB growth during deferral period
- Ratchet: Step-up of GWB to AV on anniversaries

References:
- Bauer, Kling & Russ (2008), "Universal Pricing of Guaranteed Minimum Benefits"
"""


"""
    RollupType

Enumeration of rollup calculation methods.

- `SIMPLE`: Linear growth: GWB × (1 + rate × years)
- `COMPOUND`: Exponential growth: GWB × (1 + rate)^years
- `NONE`: No rollup (GWB remains constant)
"""
@enum RollupType begin
    SIMPLE
    COMPOUND
    NONE
end


"""
    GWBConfig

Configuration for GLWB benefit mechanics.

# Fields
- `rollup_type::RollupType`: Method for GWB growth during deferral
- `rollup_rate::Float64`: Annual rollup rate (e.g., 0.06 for 6%)
- `rollup_cap_years::Int`: Years after which rollup stops
- `withdrawal_rate::Float64`: Annual withdrawal as % of GWB (e.g., 0.05)
- `fee_rate::Float64`: Annual fee rate (e.g., 0.01 for 1%)
- `ratchet_enabled::Bool`: Whether to step-up GWB to AV on anniversaries
- `fee_basis::Symbol`: Basis for fee calculation (:gwb or :av)

# Example
```julia
config = GWBConfig(
    rollup_type = COMPOUND,
    rollup_rate = 0.06,
    rollup_cap_years = 10,
    withdrawal_rate = 0.05,
    fee_rate = 0.01,
    ratchet_enabled = true,
    fee_basis = :gwb
)
```
"""
struct GWBConfig
    rollup_type::RollupType
    rollup_rate::Float64
    rollup_cap_years::Int
    withdrawal_rate::Float64
    fee_rate::Float64
    ratchet_enabled::Bool
    fee_basis::Symbol

    function GWBConfig(;
        rollup_type::RollupType = COMPOUND,
        rollup_rate::Float64 = 0.06,
        rollup_cap_years::Int = 10,
        withdrawal_rate::Float64 = 0.05,
        fee_rate::Float64 = 0.01,
        ratchet_enabled::Bool = true,
        fee_basis::Symbol = :gwb
    )
        rollup_rate >= 0 || throw(ArgumentError("rollup_rate must be >= 0"))
        rollup_cap_years >= 0 || throw(ArgumentError("rollup_cap_years must be >= 0"))
        0 < withdrawal_rate <= 0.20 || throw(ArgumentError("withdrawal_rate must be in (0, 0.20]"))
        fee_rate >= 0 || throw(ArgumentError("fee_rate must be >= 0"))
        fee_basis in (:gwb, :av) || throw(ArgumentError("fee_basis must be :gwb or :av"))

        new(rollup_type, rollup_rate, rollup_cap_years, withdrawal_rate, fee_rate, ratchet_enabled, fee_basis)
    end
end


"""
    GWBState

Mutable state for GWB benefit tracking through time.

[T1] Tracks both the actual account value and the guaranteed benefit base.
The GWB grows via rollup/ratchet while AV follows market performance.

# Fields
- `gwb::Float64`: Guaranteed Withdrawal Base
- `av::Float64`: Account Value (market value)
- `rollup_base::Float64`: Initial GWB for rollup calculation
- `high_water_mark::Float64`: Highest AV for ratchet
- `years_since_issue::Float64`: Time elapsed since contract issue
- `withdrawal_phase_started::Bool`: Whether withdrawals have begun
- `total_withdrawals::Float64`: Cumulative withdrawals taken
"""
mutable struct GWBState
    gwb::Float64
    av::Float64
    rollup_base::Float64
    high_water_mark::Float64
    years_since_issue::Float64
    withdrawal_phase_started::Bool
    total_withdrawals::Float64

    function GWBState(
        gwb::Float64,
        av::Float64,
        rollup_base::Float64,
        high_water_mark::Float64,
        years_since_issue::Float64,
        withdrawal_phase_started::Bool,
        total_withdrawals::Float64
    )
        gwb >= 0 || throw(ArgumentError("gwb must be >= 0"))
        av >= 0 || throw(ArgumentError("av must be >= 0"))
        years_since_issue >= 0 || throw(ArgumentError("years_since_issue must be >= 0"))

        new(gwb, av, rollup_base, high_water_mark, years_since_issue, withdrawal_phase_started, total_withdrawals)
    end
end

# Convenience constructor from initial premium
function GWBState(premium::Float64)
    GWBState(premium, premium, premium, premium, 0.0, false, 0.0)
end


"""
    StepResult

Result of a single timestep evolution of GWB state.

# Fields
- `fee_charged::Float64`: Fee deducted this period
- `rollup_amount::Float64`: GWB increase from rollup
- `ratchet_applied::Bool`: Whether ratchet stepped up GWB
- `withdrawal_taken::Float64`: Actual withdrawal amount
- `max_withdrawal::Float64`: Maximum allowed withdrawal this period
"""
struct StepResult
    fee_charged::Float64
    rollup_amount::Float64
    ratchet_applied::Bool
    withdrawal_taken::Float64
    max_withdrawal::Float64
end


"""
    GLWBPricingResult

Result of GLWB Monte Carlo pricing.

# Fields
- `price::Float64`: Expected PV of insurer payments
- `guarantee_cost::Float64`: Price as % of premium
- `mean_payoff::Float64`: Mean payoff across paths
- `std_payoff::Float64`: Standard deviation of payoffs
- `standard_error::Float64`: Monte Carlo standard error
- `prob_ruin::Float64`: Probability of account depletion
- `mean_ruin_year::Float64`: Mean year of ruin (if occurs)
- `prob_lapse::Float64`: Probability of lapse
- `mean_lapse_year::Float64`: Mean year of lapse (if occurs)
- `n_paths::Int`: Number of simulation paths

## Behavioral Fields (optional, populated when behavioral models enabled)
- `avg_utilization::Union{Float64, Nothing}`: Average withdrawal utilization rate
- `total_expenses_pv::Union{Float64, Nothing}`: Present value of total expenses
- `lapse_year_histogram::Union{Vector{Int}, Nothing}`: Count of lapses by year
"""
struct GLWBPricingResult
    price::Float64
    guarantee_cost::Float64
    mean_payoff::Float64
    std_payoff::Float64
    standard_error::Float64
    prob_ruin::Float64
    mean_ruin_year::Float64
    prob_lapse::Float64
    mean_lapse_year::Float64
    n_paths::Int
    # Behavioral fields (optional)
    avg_utilization::Union{Float64, Nothing}
    total_expenses_pv::Union{Float64, Nothing}
    lapse_year_histogram::Union{Vector{Int}, Nothing}
end

# Convenience constructor for backward compatibility (no behavioral fields)
function GLWBPricingResult(
    price::Float64,
    guarantee_cost::Float64,
    mean_payoff::Float64,
    std_payoff::Float64,
    standard_error::Float64,
    prob_ruin::Float64,
    mean_ruin_year::Float64,
    prob_lapse::Float64,
    mean_lapse_year::Float64,
    n_paths::Int
)
    GLWBPricingResult(
        price, guarantee_cost, mean_payoff, std_payoff, standard_error,
        prob_ruin, mean_ruin_year, prob_lapse, mean_lapse_year, n_paths,
        nothing, nothing, nothing  # No behavioral data
    )
end
