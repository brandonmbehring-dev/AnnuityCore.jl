#=============================================================================
# Regulatory Types - Phase 9
#
# [PROTOTYPE] EDUCATIONAL USE ONLY - NOT FOR PRODUCTION REGULATORY FILING
# =========================================================================
# This module provides simplified NAIC VM-21/VM-22 calculations for
# educational purposes. NOT suitable for regulatory filings.
#
# For production regulatory work, you need:
# 1. Qualified actuarial certification (FSA/MAAA)
# 2. NAIC-prescribed scenario generators (GOES/AAA ESG)
# 3. Full policy administration system integration
#
# See: docs/regulatory/AG43_COMPLIANCE_GAP.md
# =========================================================================
=============================================================================#

using Random

#=============================================================================
# Scenario Types
=============================================================================#

"""
    EconomicScenario

Single economic scenario for VM-21/VM-22 calculations.

# Fields
- `rates::Vector{Float64}`: Interest rate path (annual)
- `equity_returns::Vector{Float64}`: Equity return path (annual)
- `scenario_id::Int`: Scenario identifier

# Example
```julia
scenario = EconomicScenario(
    rates = fill(0.04, 30),
    equity_returns = fill(0.07, 30),
    scenario_id = 1
)
```
"""
struct EconomicScenario
    rates::Vector{Float64}
    equity_returns::Vector{Float64}
    scenario_id::Int

    function EconomicScenario(rates::Vector{Float64}, equity_returns::Vector{Float64}, scenario_id::Int)
        length(rates) == length(equity_returns) || error(
            "CRITICAL: Rate path length ($(length(rates))) must match equity path length ($(length(equity_returns)))"
        )
        new(rates, equity_returns, scenario_id)
    end
end

# Keyword constructor
function EconomicScenario(; rates::Vector{Float64}, equity_returns::Vector{Float64}, scenario_id::Int)
    EconomicScenario(rates, equity_returns, scenario_id)
end


"""
    AG43Scenarios

Collection of AG43/VM-21 prescribed scenarios.

[T1] AG43 requires stochastic scenarios for CTE calculation.

# Fields
- `scenarios::Vector{EconomicScenario}`: List of economic scenarios
- `n_scenarios::Int`: Number of scenarios
- `projection_years::Int`: Years in each scenario
"""
struct AG43Scenarios
    scenarios::Vector{EconomicScenario}
    n_scenarios::Int
    projection_years::Int
end

"""Get all rate paths as matrix [n_scenarios × projection_years]."""
function get_rate_matrix(ag43::AG43Scenarios)::Matrix{Float64}
    reduce(vcat, [s.rates' for s in ag43.scenarios])
end

"""Get all equity return paths as matrix [n_scenarios × projection_years]."""
function get_equity_matrix(ag43::AG43Scenarios)::Matrix{Float64}
    reduce(vcat, [s.equity_returns' for s in ag43.scenarios])
end


"""
    VasicekParams

Vasicek interest rate model parameters.

[T1] dr = κ(θ - r)dt + σ dW

# Fields
- `kappa::Float64`: Mean reversion speed (default 0.20)
- `theta::Float64`: Long-run mean rate (default 0.04 = 4%)
- `sigma::Float64`: Rate volatility (default 0.01 = 1%)
"""
struct VasicekParams
    kappa::Float64  # Mean reversion speed
    theta::Float64  # Long-run mean rate
    sigma::Float64  # Rate volatility
end

# Default constructor using keyword syntax
VasicekParams(; kappa::Real = 0.20, theta::Real = 0.04, sigma::Real = 0.01) =
    VasicekParams(Float64(kappa), Float64(theta), Float64(sigma))


"""
    EquityParams

Equity model parameters (GBM) - real-world measure.

[T1] dS/S = μdt + σ dW

# Fields
- `mu::Float64`: Drift (expected return) - real-world measure (default 0.07 = 7%)
- `sigma::Float64`: Volatility (default 0.18 = 18%)

Note: For risk-neutral pricing, use `RiskNeutralEquityParams` instead.
"""
struct EquityParams
    mu::Float64     # Expected return (real-world)
    sigma::Float64  # Volatility
end

# Default constructor using keyword syntax
EquityParams(; mu::Real = 0.07, sigma::Real = 0.18) =
    EquityParams(Float64(mu), Float64(sigma))


"""
    RiskNeutralEquityParams

Risk-neutral equity model parameters.

[T1] Under risk-neutral measure: drift = r - q (forward rate minus dividend yield)

# Fields
- `risk_free_rate::Float64`: Risk-free rate (from yield curve)
- `dividend_yield::Float64`: Continuous dividend yield (default 0.02 = 2%)
- `sigma::Float64`: Volatility (default 0.18 = 18%)

# Example
```julia
params = RiskNeutralEquityParams(risk_free_rate=0.04, dividend_yield=0.02)
risk_neutral_drift(params)  # Returns 0.02 (4% - 2%)
```
"""
struct RiskNeutralEquityParams
    risk_free_rate::Float64
    dividend_yield::Float64
    sigma::Float64
end

# Default constructor with only risk_free_rate required
function RiskNeutralEquityParams(;
    risk_free_rate::Float64,
    dividend_yield::Float64 = 0.02,
    sigma::Float64 = 0.18
)
    RiskNeutralEquityParams(risk_free_rate, dividend_yield, sigma)
end

"""Risk-neutral drift = r - q."""
risk_neutral_drift(p::RiskNeutralEquityParams) = p.risk_free_rate - p.dividend_yield

"""Convert to EquityParams for compatibility."""
function to_equity_params(p::RiskNeutralEquityParams)::EquityParams
    EquityParams(risk_neutral_drift(p), p.sigma)
end


#=============================================================================
# VM-21 Types
=============================================================================#

"""
    PolicyData

Policy data for VM-21 calculation (variable annuity with GLWB).

# Fields
- `av::Float64`: Current account value
- `gwb::Float64`: Guaranteed withdrawal base
- `age::Int`: Policyholder age
- `csv::Float64`: Cash surrender value (default 0.0)
- `withdrawal_rate::Float64`: Annual withdrawal rate (default 0.05 = 5%)
- `fee_rate::Float64`: Annual fee rate (default 0.01 = 1%)
"""
struct PolicyData
    av::Float64
    gwb::Float64
    age::Int
    csv::Float64
    withdrawal_rate::Float64
    fee_rate::Float64

    function PolicyData(av, gwb, age, csv, withdrawal_rate, fee_rate)
        av >= 0 || error("CRITICAL: Account value cannot be negative, got $av")
        gwb >= 0 || error("CRITICAL: GWB cannot be negative, got $gwb")
        age >= 0 || error("CRITICAL: Age cannot be negative, got $age")
        new(Float64(av), Float64(gwb), age, Float64(csv), Float64(withdrawal_rate), Float64(fee_rate))
    end
end

# Keyword constructor with defaults
function PolicyData(;
    av::Real,
    gwb::Real,
    age::Int,
    csv::Real = 0.0,
    withdrawal_rate::Real = 0.05,
    fee_rate::Real = 0.01
)
    PolicyData(Float64(av), Float64(gwb), age, Float64(csv), Float64(withdrawal_rate), Float64(fee_rate))
end


"""
    VM21Result

VM-21 calculation result.

# Fields
- `cte70::Float64`: Conditional Tail Expectation at 70%
- `ssa::Float64`: Standard Scenario Amount
- `csv_floor::Float64`: Cash Surrender Value floor
- `reserve::Float64`: Required reserve = max(CTE70, SSA, CSV)
- `scenario_count::Int`: Number of scenarios used
- `mean_pv::Float64`: Mean present value across scenarios
- `std_pv::Float64`: Standard deviation of present values
- `worst_pv::Float64`: Worst scenario present value
"""
struct VM21Result
    cte70::Float64
    ssa::Float64
    csv_floor::Float64
    reserve::Float64
    scenario_count::Int
    mean_pv::Float64
    std_pv::Float64
    worst_pv::Float64
end

# Keyword constructor
function VM21Result(;
    cte70::Float64,
    ssa::Float64,
    csv_floor::Float64,
    reserve::Float64,
    scenario_count::Int,
    mean_pv::Float64 = 0.0,
    std_pv::Float64 = 0.0,
    worst_pv::Float64 = 0.0
)
    VM21Result(cte70, ssa, csv_floor, reserve, scenario_count, mean_pv, std_pv, worst_pv)
end


#=============================================================================
# VM-22 Types
=============================================================================#

"""
    ReserveType

Type of reserve calculation used in VM-22.
"""
@enum ReserveType begin
    DETERMINISTIC
    STOCHASTIC
end


"""
    FixedAnnuityPolicy

Fixed annuity policy data for VM-22 calculation.

# Fields
- `premium::Float64`: Initial premium
- `guaranteed_rate::Float64`: Guaranteed crediting rate (e.g., 0.04 for 4%)
- `term_years::Int`: Term of guarantee
- `current_year::Int`: Current policy year (0 = issue)
- `surrender_charge_pct::Float64`: Current surrender charge percentage
- `account_value::Union{Float64, Nothing}`: Current account value (if different from premium)
"""
struct FixedAnnuityPolicy
    premium::Float64
    guaranteed_rate::Float64
    term_years::Int
    current_year::Int
    surrender_charge_pct::Float64
    account_value::Union{Float64, Nothing}

    function FixedAnnuityPolicy(premium, guaranteed_rate, term_years, current_year,
                                 surrender_charge_pct, account_value)
        premium > 0 || error("CRITICAL: Premium must be positive, got $premium")
        guaranteed_rate >= 0 || error("CRITICAL: Guaranteed rate cannot be negative, got $guaranteed_rate")
        term_years > 0 || error("CRITICAL: Term years must be positive, got $term_years")
        new(Float64(premium), Float64(guaranteed_rate), term_years, current_year,
            Float64(surrender_charge_pct), account_value)
    end
end

# Keyword constructor with defaults
function FixedAnnuityPolicy(;
    premium::Real,
    guaranteed_rate::Real,
    term_years::Int,
    current_year::Int = 0,
    surrender_charge_pct::Real = 0.07,
    account_value::Union{Real, Nothing} = nothing
)
    av = account_value === nothing ? nothing : Float64(account_value)
    FixedAnnuityPolicy(Float64(premium), Float64(guaranteed_rate), term_years,
                       current_year, Float64(surrender_charge_pct), av)
end

"""Get account value (defaults to premium if not specified)."""
function get_av(policy::FixedAnnuityPolicy)::Float64
    policy.account_value !== nothing ? policy.account_value : policy.premium
end


"""
    StochasticExclusionResult

Result of Stochastic Exclusion Test (SET).

# Fields
- `passed::Bool`: Whether product passes exclusion (can use DR)
- `ratio::Float64`: SET ratio (liability / asset value)
- `threshold::Float64`: Threshold for passing
"""
struct StochasticExclusionResult
    passed::Bool
    ratio::Float64
    threshold::Float64
end


"""
    VM22Result

VM-22 calculation result.

# Fields
- `reserve::Float64`: Required reserve
- `net_premium_reserve::Float64`: NPR component
- `deterministic_reserve::Float64`: DR component
- `stochastic_reserve::Union{Float64, Nothing}`: SR component (if applicable)
- `reserve_type::ReserveType`: Which reserve calculation was binding
- `set_passed::Bool`: Whether Stochastic Exclusion Test passed
- `sst_passed::Bool`: Whether Single Scenario Test passed
"""
struct VM22Result
    reserve::Float64
    net_premium_reserve::Float64
    deterministic_reserve::Float64
    stochastic_reserve::Union{Float64, Nothing}
    reserve_type::ReserveType
    set_passed::Bool
    sst_passed::Bool
end

# Keyword constructor with defaults
function VM22Result(;
    reserve::Float64,
    net_premium_reserve::Float64,
    deterministic_reserve::Float64,
    stochastic_reserve::Union{Float64, Nothing} = nothing,
    reserve_type::ReserveType = DETERMINISTIC,
    set_passed::Bool = true,
    sst_passed::Bool = true
)
    VM22Result(reserve, net_premium_reserve, deterministic_reserve,
               stochastic_reserve, reserve_type, set_passed, sst_passed)
end
