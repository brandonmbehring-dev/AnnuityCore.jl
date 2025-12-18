"""
Behavioral Model Types for Policyholder Behavior Modeling.

Defines configuration and result types for:
- Dynamic lapse (surrender) modeling
- GLWB withdrawal utilization
- Expense modeling

[T2] Calibrated to SOA 2006 Deferred Annuity Persistency Study
     and SOA 2018 VA GLB Utilization Study.
"""


# =============================================================================
# Lapse Configuration Types
# =============================================================================

"""
    LapseConfig

Simple dynamic lapse configuration with user-specified parameters.

[T1] Models lapse as function of moneyness (GWB/AV ratio).
ITM guarantees (GWB > AV) reduce lapse probability.

# Fields
- `base_annual_lapse::Float64`: Base annual lapse rate (default 0.05)
- `min_lapse::Float64`: Floor on lapse rate (default 0.01)
- `max_lapse::Float64`: Cap on lapse rate (default 0.25)
- `moneyness_sensitivity::Float64`: Sensitivity to GWB/AV ratio (default 1.0)

# Example
```julia
config = LapseConfig(base_annual_lapse=0.05, moneyness_sensitivity=1.5)
```
"""
struct LapseConfig
    base_annual_lapse::Float64
    min_lapse::Float64
    max_lapse::Float64
    moneyness_sensitivity::Float64

    function LapseConfig(;
        base_annual_lapse::Float64 = 0.05,
        min_lapse::Float64 = 0.01,
        max_lapse::Float64 = 0.25,
        moneyness_sensitivity::Float64 = 1.0
    )
        base_annual_lapse >= 0 || throw(ArgumentError("base_annual_lapse must be >= 0"))
        0 <= min_lapse <= max_lapse <= 1.0 || throw(ArgumentError("Must have 0 <= min_lapse <= max_lapse <= 1"))
        moneyness_sensitivity >= 0 || throw(ArgumentError("moneyness_sensitivity must be >= 0"))
        new(base_annual_lapse, min_lapse, max_lapse, moneyness_sensitivity)
    end
end


"""
    SOALapseConfig

SOA-calibrated lapse configuration using 2006 Deferred Annuity Persistency Study.

[T2] Incorporates duration-based surrender curves, SC cliff effects, and optional
age adjustments based on empirical SOA data.

# Fields
- `surrender_charge_length::Int`: Surrender charge period in years (default 7)
- `use_duration_curve::Bool`: Use SOA 2006 duration-based curve (default true)
- `use_sc_cliff_effect::Bool`: Apply 2.48x SC cliff multiplier (default true)
- `use_age_adjustment::Bool`: Apply age-based adjustment (default false)
- `moneyness_sensitivity::Float64`: ITM sensitivity for GLWB products (default 1.0)
- `min_lapse::Float64`: Floor on lapse rate (default 0.005)
- `max_lapse::Float64`: Cap on lapse rate (default 0.30)

# Example
```julia
config = SOALapseConfig(surrender_charge_length=7, use_sc_cliff_effect=true)
```
"""
struct SOALapseConfig
    surrender_charge_length::Int
    use_duration_curve::Bool
    use_sc_cliff_effect::Bool
    use_age_adjustment::Bool
    moneyness_sensitivity::Float64
    min_lapse::Float64
    max_lapse::Float64

    function SOALapseConfig(;
        surrender_charge_length::Int = 7,
        use_duration_curve::Bool = true,
        use_sc_cliff_effect::Bool = true,
        use_age_adjustment::Bool = false,
        moneyness_sensitivity::Float64 = 1.0,
        min_lapse::Float64 = 0.005,
        max_lapse::Float64 = 0.30
    )
        surrender_charge_length >= 0 || throw(ArgumentError("surrender_charge_length must be >= 0"))
        0 <= min_lapse <= max_lapse <= 1.0 || throw(ArgumentError("Must have 0 <= min_lapse <= max_lapse <= 1"))
        moneyness_sensitivity >= 0 || throw(ArgumentError("moneyness_sensitivity must be >= 0"))
        new(surrender_charge_length, use_duration_curve, use_sc_cliff_effect,
            use_age_adjustment, moneyness_sensitivity, min_lapse, max_lapse)
    end
end


"""
    LapseResult

Result of lapse calculation with diagnostic fields.

# Fields
- `lapse_rate::Float64`: Final calculated annual lapse rate
- `moneyness::Float64`: GWB/AV ratio used in calculation
- `base_rate::Float64`: Base rate before adjustments
- `adjustment_factor::Float64`: Combined adjustment multiplier
"""
struct LapseResult
    lapse_rate::Float64
    moneyness::Float64
    base_rate::Float64
    adjustment_factor::Float64
end


# =============================================================================
# Withdrawal Configuration Types
# =============================================================================

"""
    WithdrawalConfig

Simple withdrawal utilization configuration with user-specified parameters.

[T1] Models withdrawal utilization as function of age and duration.

# Fields
- `base_utilization::Float64`: Base utilization rate (default 0.50)
- `age_sensitivity::Float64`: Increase per year over 65 (default 0.01)
- `min_utilization::Float64`: Floor on utilization (default 0.10)
- `max_utilization::Float64`: Cap on utilization (default 1.00)

# Example
```julia
config = WithdrawalConfig(base_utilization=0.50, age_sensitivity=0.02)
```
"""
struct WithdrawalConfig
    base_utilization::Float64
    age_sensitivity::Float64
    min_utilization::Float64
    max_utilization::Float64

    function WithdrawalConfig(;
        base_utilization::Float64 = 0.50,
        age_sensitivity::Float64 = 0.01,
        min_utilization::Float64 = 0.10,
        max_utilization::Float64 = 1.00
    )
        0 <= base_utilization <= 1 || throw(ArgumentError("base_utilization must be in [0, 1]"))
        age_sensitivity >= 0 || throw(ArgumentError("age_sensitivity must be >= 0"))
        0 <= min_utilization <= max_utilization <= 1 || throw(ArgumentError("Must have 0 <= min <= max <= 1"))
        new(base_utilization, age_sensitivity, min_utilization, max_utilization)
    end
end


"""
    SOAWithdrawalConfig

SOA-calibrated withdrawal configuration using 2018 VA GLB Utilization Study.

[T2] Incorporates duration-based ramp-up, age-based curves, and ITM sensitivity
factors from empirical SOA data.

# Fields
- `use_duration_curve::Bool`: Use SOA 2018 duration curve (default true)
- `use_age_curve::Bool`: Use SOA 2018 age curve (default true)
- `use_itm_sensitivity::Bool`: Apply ITM sensitivity factors (default true)
- `use_continuous_itm::Bool`: Smooth interpolation for ITM (default true)
- `combination_method::Symbol`: How to combine factors - :multiplicative or :additive (default :multiplicative)
- `min_utilization::Float64`: Floor on utilization (default 0.05)
- `max_utilization::Float64`: Cap on utilization (default 1.00)

# Example
```julia
config = SOAWithdrawalConfig(use_itm_sensitivity=true, combination_method=:multiplicative)
```
"""
struct SOAWithdrawalConfig
    use_duration_curve::Bool
    use_age_curve::Bool
    use_itm_sensitivity::Bool
    use_continuous_itm::Bool
    combination_method::Symbol
    min_utilization::Float64
    max_utilization::Float64

    function SOAWithdrawalConfig(;
        use_duration_curve::Bool = true,
        use_age_curve::Bool = true,
        use_itm_sensitivity::Bool = true,
        use_continuous_itm::Bool = true,
        combination_method::Symbol = :multiplicative,
        min_utilization::Float64 = 0.05,
        max_utilization::Float64 = 1.00
    )
        combination_method in (:multiplicative, :additive) || throw(ArgumentError("combination_method must be :multiplicative or :additive"))
        0 <= min_utilization <= max_utilization <= 1 || throw(ArgumentError("Must have 0 <= min <= max <= 1"))
        new(use_duration_curve, use_age_curve, use_itm_sensitivity,
            use_continuous_itm, combination_method, min_utilization, max_utilization)
    end
end


"""
    WithdrawalResult

Result of withdrawal calculation with diagnostic fields.

# Fields
- `withdrawal_amount::Float64`: Calculated withdrawal amount
- `utilization_rate::Float64`: Utilization rate applied (0-1)
- `max_allowed::Float64`: Maximum allowed withdrawal
- `duration_factor::Float64`: Duration contribution to utilization
- `age_factor::Float64`: Age contribution to utilization
- `itm_factor::Float64`: ITM sensitivity factor applied
"""
struct WithdrawalResult
    withdrawal_amount::Float64
    utilization_rate::Float64
    max_allowed::Float64
    duration_factor::Float64
    age_factor::Float64
    itm_factor::Float64
end


# =============================================================================
# Expense Configuration Types
# =============================================================================

"""
    ExpenseConfig

Configuration for expense modeling.

[T1] Models both fixed per-policy expenses and variable AV-based expenses
with optional inflation adjustment.

# Fields
- `per_policy_annual::Float64`: Fixed annual per-policy expense (default 100.0)
- `pct_of_av_annual::Float64`: Annual percentage of AV for M&E (default 0.015)
- `acquisition_pct::Float64`: One-time acquisition cost as % of premium (default 0.03)
- `inflation_rate::Float64`: Annual inflation rate for fixed expenses (default 0.025)

# Example
```julia
config = ExpenseConfig(per_policy_annual=100.0, pct_of_av_annual=0.015)
```
"""
struct ExpenseConfig
    per_policy_annual::Float64
    pct_of_av_annual::Float64
    acquisition_pct::Float64
    inflation_rate::Float64

    function ExpenseConfig(;
        per_policy_annual::Float64 = 100.0,
        pct_of_av_annual::Float64 = 0.015,
        acquisition_pct::Float64 = 0.03,
        inflation_rate::Float64 = 0.025
    )
        per_policy_annual >= 0 || throw(ArgumentError("per_policy_annual must be >= 0"))
        pct_of_av_annual >= 0 || throw(ArgumentError("pct_of_av_annual must be >= 0"))
        acquisition_pct >= 0 || throw(ArgumentError("acquisition_pct must be >= 0"))
        inflation_rate >= -0.10 || throw(ArgumentError("inflation_rate must be >= -10%"))
        new(per_policy_annual, pct_of_av_annual, acquisition_pct, inflation_rate)
    end
end


"""
    ExpenseResult

Result of expense calculation for a period.

# Fields
- `total_expense::Float64`: Total expense for the period
- `per_policy_component::Float64`: Fixed portion (inflation-adjusted)
- `av_component::Float64`: Percentage of AV portion
"""
struct ExpenseResult
    total_expense::Float64
    per_policy_component::Float64
    av_component::Float64
end


# =============================================================================
# Behavioral Config Wrapper (for GLWBSimulator integration)
# =============================================================================

"""
    BehavioralConfig

Combined behavioral configuration for GLWB simulation.

Wraps lapse, withdrawal, and expense configs into a single object
for easy integration with GLWBSimulator.

# Fields
- `lapse::Union{LapseConfig, SOALapseConfig, Nothing}`: Lapse configuration
- `withdrawal::Union{WithdrawalConfig, SOAWithdrawalConfig, Nothing}`: Withdrawal configuration
- `expenses::Union{ExpenseConfig, Nothing}`: Expense configuration

# Example
```julia
behavioral = BehavioralConfig(
    lapse = SOALapseConfig(),
    withdrawal = SOAWithdrawalConfig(),
    expenses = ExpenseConfig()
)
```
"""
struct BehavioralConfig
    lapse::Union{LapseConfig, SOALapseConfig, Nothing}
    withdrawal::Union{WithdrawalConfig, SOAWithdrawalConfig, Nothing}
    expenses::Union{ExpenseConfig, Nothing}

    function BehavioralConfig(;
        lapse::Union{LapseConfig, SOALapseConfig, Nothing} = nothing,
        withdrawal::Union{WithdrawalConfig, SOAWithdrawalConfig, Nothing} = nothing,
        expenses::Union{ExpenseConfig, Nothing} = nothing
    )
        new(lapse, withdrawal, expenses)
    end
end

# Convenience: check if any behavioral modeling is enabled
has_lapse(bc::BehavioralConfig) = bc.lapse !== nothing
has_withdrawal(bc::BehavioralConfig) = bc.withdrawal !== nothing
has_expenses(bc::BehavioralConfig) = bc.expenses !== nothing
has_any_behavior(bc::BehavioralConfig) = has_lapse(bc) || has_withdrawal(bc) || has_expenses(bc)
