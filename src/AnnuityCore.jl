"""
    AnnuityCore

Core pricing engine for annuity products: Black-Scholes, Greeks, payoffs, and Monte Carlo.

This package provides:
- Black-Scholes option pricing with full Greeks
- Heston stochastic volatility model (MC + COS method)
- SABR model with Hagan approximation
- Volatility surface construction and interpolation
- FIA payoff calculations (cap, participation, spread, trigger)
- RILA payoff calculations (buffer, floor, step-rate)
- Monte Carlo simulation engine with GBM/Heston paths

# Example
```julia
using AnnuityCore

# Price a European call option (Black-Scholes)
price = black_scholes_call(100.0, 100.0, 0.05, 0.02, 0.20, 1.0)

# Price via Monte Carlo
mc_price = monte_carlo_price(100.0, 100.0, 0.05, 0.02, 0.20, 1.0)

# Heston stochastic volatility
params = HestonParams(S₀=100.0, r=0.05, V₀=0.04, κ=2.0, θ=0.04, σ_v=0.3, ρ=-0.7, τ=1.0)
heston_price = heston_cos_call(params, 100.0)  # Fast COS method

# SABR implied volatility
sabr = SABRParams(F=100.0, α=0.20, β=0.5, ρ=-0.3, ν=0.4, τ=1.0)
σ_impl = sabr_implied_vol(sabr, 100.0)

# Calculate payoff with buffer protection
payoff = BufferPayoff(0.10, 0.20)
result = calculate(payoff, -0.05)  # Returns 0.0 (buffer absorbs loss)
```
"""
module AnnuityCore

using Distributions
using Random: AbstractRNG
using StableRNGs
using Statistics: mean, std, var
using Zygote

# Options pricing (Black-Scholes first, MC after payoffs)
include("Options/black_scholes.jl")
include("Options/gbm.jl")
include("Options/ad_greeks.jl")

# Stochastic volatility models
include("Options/heston.jl")
include("Options/sabr.jl")
include("Options/heston_cos.jl")
include("Options/vol_surface.jl")

# Payoff types (needed by monte_carlo.jl)
include("Payoffs/base.jl")
include("Payoffs/fia.jl")
include("Payoffs/rila.jl")

# Monte Carlo engine (depends on payoffs)
include("Options/monte_carlo.jl")

# Validation gates
include("Validation/gates.jl")

# Behavioral Models (must be before GLWB since path_sim.jl uses behavioral types)
include("Behavioral/Behavioral.jl")

# GLWB (Guaranteed Lifetime Withdrawal Benefit)
include("GLWB/types.jl")
include("GLWB/rollup.jl")
include("GLWB/tracker.jl")
include("GLWB/mortality.jl")
include("GLWB/path_sim.jl")

# Product Pricers (MYGA, FIA, RILA)
include("Products/types.jl")
include("Products/myga.jl")
include("Products/fia.jl")
include("Products/rila.jl")

# Stress Testing
include("StressTesting/StressTesting.jl")

# Public API - Black-Scholes
export black_scholes_call, black_scholes_put
export black_scholes_greeks, BSGreeks

# Public API - AD Greeks
export ADGreeks
export ad_greeks_call, ad_greeks_put
export portfolio_greeks, ad_greeks_payoff
export validate_ad_vs_analytical

# Public API - GBM Path Generation
export GBMParams, PathResult
export generate_gbm_paths, generate_terminal_values
export generate_paths_with_monthly_observations
export validate_gbm_simulation
export drift, forward, n_paths, n_steps, terminal_values, total_returns

# Public API - Monte Carlo Engine
export MonteCarloEngine, MCResult
export price_european_call, price_european_put
export price_with_payoff
export price_capped_call_return, price_buffer_protection, price_floor_protection
export price_vanilla_mc, monte_carlo_price
export convergence_analysis
export relative_error, ci_width

# Public API - Payoffs
export AbstractPayoff, FIAPayoff, RILAPayoff
export PayoffResult

# FIA payoffs
export CappedCallPayoff, ParticipationPayoff, SpreadPayoff, TriggerPayoff

# RILA payoffs
export BufferPayoff, FloorPayoff, BufferWithFloorPayoff, StepRateBufferPayoff

# Calculation
export calculate

# Validation
export ValidationResult, HALT, PASS, WARN
export validate_no_arbitrage, validate_put_call_parity

# Public API - Heston Model
export HestonParams, HestonPathResult
export feller_condition
export generate_heston_paths
export heston_characteristic_function
export heston_call_mc, heston_put_mc
export heston_implied_vol

# Public API - SABR Model
export SABRParams
export sabr_implied_vol, sabr_smile
export calibrate_sabr
export sabr_delta, sabr_vega

# Public API - COS Method (Heston)
export COSConfig
export heston_cos_call, heston_cos_put
export heston_cos_greeks
export heston_smile_cos
export benchmark_cos_vs_mc

# Public API - Volatility Surface
export VolSurfacePoint, VolSmile, VolSurface
export moneyness, log_moneyness
export interpolate_smile, interpolate_surface
export build_surface_from_quotes
export fit_sabr_surface
export atm_vol, skew, butterfly
export term_structure
export validate_no_calendar_arbitrage
export smile_from_heston, smile_from_sabr

# Public API - GLWB
export RollupType, SIMPLE, COMPOUND, NONE
export GWBConfig, GWBState, StepResult, GLWBPricingResult
export simple_rollup, compound_rollup, calculate_rollup, apply_ratchet, is_anniversary, rollup_comparison
export step!, max_withdrawal, simulate_path!
export is_ruined, benefit_moneyness, gwb_to_av_ratio
export GLWBSimulator, glwb_price
export calculate_fair_fee, sensitivity_analysis
export default_mortality, soa_2012_iam_qx
export constant_mortality, zero_mortality
export convert_annual_to_step, life_expectancy, survival_probability

# Public API - Product Types
export PricingResult, FIAPricingResult, RILAPricingResult
export MarketParams
export MYGAProduct, FIAProduct, RILAProduct

# Public API - Product Pricers
export price_myga, myga_sensitivity, myga_breakeven_rate, myga_total_return
export price_fia
export price_rila, rila_greeks, compare_buffer_vs_floor

# Public API - Behavioral Models
# Configuration types
export LapseConfig, SOALapseConfig, LapseResult
export WithdrawalConfig, SOAWithdrawalConfig, WithdrawalResult
export ExpenseConfig, ExpenseResult
export BehavioralConfig, has_lapse, has_withdrawal, has_expenses, has_any_behavior

# Lapse functions
export calculate_lapse, calculate_path_lapses
export survival_from_lapses, lapse_probability
export moneyness_from_state, is_itm

# Withdrawal functions
export calculate_withdrawal, calculate_path_withdrawals
export total_withdrawals, average_utilization, withdrawal_amounts, utilization_rates
export withdrawal_efficiency, path_withdrawal_efficiency
export get_utilization_surface, utilization_by_itm

# Expense functions
export calculate_expense, calculate_acquisition_expense, calculate_path_expenses
export total_expenses, expense_amounts, pv_expenses
export expense_ratio, average_expense_ratio
export fixed_vs_variable_split, breakeven_av
export project_expenses, expense_sensitivity

# Interpolation functions
export linear_interpolate
export interpolate_surrender_by_duration, get_sc_cliff_multiplier, get_post_sc_decay_factor
export interpolate_surrender_by_age
export interpolate_utilization_by_duration, interpolate_utilization_by_age
export get_itm_sensitivity_factor, combined_utilization
export get_surrender_curve, get_utilization_curve

# SOA data constants
export SOA_2006_SURRENDER_BY_DURATION_7YR_SC, SOA_2006_SC_POSITION
export SOA_2006_SC_CLIFF_MULTIPLIER, SOA_2006_POST_SC_DECAY
export SOA_2006_FULL_SURRENDER_BY_AGE, SOA_2006_PARTIAL_WITHDRAWAL_BY_AGE
export SOA_2018_GLWB_UTILIZATION_BY_DURATION, SOA_2018_GLWB_UTILIZATION_BY_AGE
export SOA_2018_ITM_SENSITIVITY, SOA_2018_ITM_BREAKPOINTS
export SOA_2018_ITM_VS_NOT_ITM_BY_AGE, SOA_KEY_INSIGHTS

# GLWB behavioral integration helpers
export has_lapse_model, has_withdrawal_model, has_expense_model, has_behavioral_models

# Public API - Stress Testing
# Core types
export ScenarioType, HISTORICAL, ORSA, REGULATORY, CUSTOM
export RecoveryType, V_SHAPED, U_SHAPED, L_SHAPED, W_SHAPED
export StressScenario, CrisisProfile, HistoricalCrisis
export SensitivityParameter, SensitivityResult, TornadoData
export ReverseStressTarget, ReverseStressResult, ReverseStressReport
export StressTestResult, StressTestConfig, StressTestSummary

# ORSA scenarios
export ORSA_MODERATE_ADVERSE, ORSA_SEVERELY_ADVERSE, ORSA_EXTREMELY_ADVERSE
export ORSA_SCENARIOS

# Historical crises
export CRISIS_2008_GFC, CRISIS_2020_COVID, CRISIS_2000_DOTCOM
export CRISIS_2011_EURO_DEBT, CRISIS_2015_CHINA, CRISIS_2018_Q4, CRISIS_2022_RATES
export ALL_HISTORICAL_CRISES, FALLING_RATE_CRISES, RISING_RATE_CRISES

# Scenario functions
export crisis_to_scenario, get_crisis
export crises_by_severity, crises_by_duration, crises_by_recovery
export historical_scenarios
export interpolate_crisis_profile, crisis_scenario_at_month, generate_crisis_path
export print_crisis_summary, crisis_statistics

# Scenario builders
export create_equity_shock, create_rate_shock, create_vol_shock
export create_behavioral_shock, create_combined_scenario
export combine_scenarios, scale_scenario
export generate_equity_grid, generate_rate_grid, generate_2d_grid
export scenario_summary, is_adverse, severity_score, sort_by_severity

# Sensitivity analysis
export DEFAULT_EQUITY_PARAM, DEFAULT_RATE_PARAM, DEFAULT_VOL_PARAM
export DEFAULT_LAPSE_PARAM, DEFAULT_WITHDRAWAL_PARAM, DEFAULT_SENSITIVITY_PARAMS
export run_sensitivity_sweep, run_multi_sensitivity
export build_tornado_data, sort_tornado, top_n_tornado
export sensitivity_elasticity, monotonicity, max_impact, impact_at_extreme
export SensitivityConfig, SensitivityAnalyzer, run_analysis
export run_interaction_analysis, interaction_effect
export print_sensitivity_summary, print_tornado, impact_range

# Reverse stress testing
export RESERVE_EXHAUSTION, RBC_BREACH_200, RBC_BREACH_300, RESERVE_RATIO_50
export PREDEFINED_TARGETS
export triggers_target, find_breaking_point
export ReverseStressTester, run_reverse_test
export run_multi_target_reverse
export breaking_point_distance, breaking_point_severity, format_breaking_point
export print_reverse_report, vulnerability_summary
export binary_search_scenario, find_minimum_crisis

# Stress test runner
export calculate_reserve_impact, calculate_rbc_ratio
export StressTestRunner, orsa_runner, historical_runner, standard_runner
export run_scenario, run_all_scenarios, run_stress_test
export print_stress_summary, export_results
export quick_stress_test, compare_scenarios, stress_test_grid

end # module AnnuityCore
