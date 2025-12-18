"""
Behavioral Models for Policyholder Behavior.

This submodule provides SOA-calibrated models for:
- Dynamic lapse (surrender) based on moneyness and SC position
- Withdrawal utilization based on age, duration, and ITM sensitivity
- Expense modeling with fixed and variable components

[T2] Calibrated to:
- SOA 2006 Deferred Annuity Persistency Study
- SOA 2018 VA GLB Utilization Study

# Example
```julia
using AnnuityCore

# Simple lapse model
lapse_config = LapseConfig(base_annual_lapse=0.05, moneyness_sensitivity=1.0)
result = calculate_lapse(lapse_config, 110_000.0, 100_000.0)

# SOA-calibrated lapse model
soa_lapse = SOALapseConfig(surrender_charge_length=7, use_sc_cliff_effect=true)
result = calculate_lapse(soa_lapse, 100_000.0, 100_000.0, 8, 0)  # Year 8, at cliff

# SOA withdrawal utilization
withdrawal_config = SOAWithdrawalConfig(use_itm_sensitivity=true)
result = calculate_withdrawal(withdrawal_config, 100_000.0, 80_000.0, 0.05, 5, 70)

# Integrate with GLWB simulation
sim = GLWBSimulator(
    config = GWBConfig(),
    lapse_config = SOALapseConfig(),
    withdrawal_config = SOAWithdrawalConfig(),
    expense_config = ExpenseConfig()
)
result = glwb_price(sim, 100000.0, 65)
```
"""

# Load files in dependency order
include("types.jl")
include("soa_data.jl")
include("interpolation.jl")
include("lapse.jl")
include("withdrawal.jl")
include("expenses.jl")
