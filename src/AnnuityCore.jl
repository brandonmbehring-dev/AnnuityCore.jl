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

# Validation gates (depends on Products for FIAPricingResult, RILAPricingResult)
include("Validation/gates.jl")

# Stress Testing
include("StressTesting/StressTesting.jl")

# Data Loaders (Mortality tables, Yield curves)
include("Loaders/Loaders.jl")

# Competitive Analysis (Market positioning, Rankings, Spreads)
include("Competitive/Competitive.jl")

# Credit Risk (AM Best ratings, Guaranty funds, CVA)
include("Credit/Credit.jl")

# Rate Setting (MYGA rate recommendations)
include("RateSetting/RateSetting.jl")

# Regulatory (VM-21, VM-22, Scenario Generation)
include("Regulatory/Regulatory.jl")

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

# Validation - Core Types
export ValidationResult, HALT, PASS, WARN
export GateResult, ValidationReport
export passed, overall_status, halted_gates, warned_gates

# Validation - Gate Types
export AbstractValidationGate, gate_name, check
export PresentValueBoundsGate, DurationBoundsGate
export FIAOptionBudgetGate, FIAExpectedCreditGate
export RILAMaxLossGate, RILAProtectionValueGate
export ArbitrageBoundsGate, ProductParameterSanityGate
export MAX_CAP_RATE, MAX_PARTICIPATION_RATE, MAX_BUFFER_RATE, MAX_SPREAD_RATE

# Validation - Engine and Convenience
export ValidationEngine, default_gates
export validate, validate_and_raise
export validate_pricing_result, ensure_valid
export print_validation_report

# Validation - Standalone Functions
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

# Public API - Data Loaders (Mortality)
export Gender, MALE, FEMALE, UNISEX
export MortalityTable
export get_qx, get_px, npx, nqx
export life_expectancy, complete_life_expectancy
export lx, dx
export annuity_factor, annuity_immediate_factor
export calculate_annuity_pv
export soa_2012_iam, soa_table
export gompertz_table, from_dict
export with_improvement, blend_tables
export compare_life_expectancy, validate_mortality_table
export get_soa_2012_iam_qx_vector, get_soa_2012_iam_age_range
export SOA_2012_IAM_MALE_QX, SOA_2012_IAM_FEMALE_QX
export SOA_2012_IAM_MALE_KEY_POINTS, SOA_2012_IAM_FEMALE_KEY_POINTS
export SOA_TABLE_IDS

# Public API - Data Loaders (Yield Curves)
export InterpolationMethod, LINEAR, LOG_LINEAR, CUBIC
export YieldCurve, NelsonSiegelParams
export get_rate, discount_factor, discount_factors
export forward_rate, instantaneous_forward, par_rate
export nelson_siegel_rate
export from_nelson_siegel, from_points, flat_curve
export upward_sloping_curve, inverted_curve
export shift_curve, steepen_curve, scale_curve
export macaulay_duration, modified_duration, dv01, convexity
export present_value, annuity_pv
export validate_yield_curve, curve_summary

# Public API - Data Loaders (Treasury)
export TREASURY_MATURITIES, FRED_TREASURY_SERIES

# Public API - Interpolation Utilities
export linear_interp, log_linear_interp, cubic_interp
export interpolate, interpolate_vector
export extrapolate_flat, extrapolate_linear

# Public API - Competitive Analysis
# Types
export WINKProduct, ProductData
export PositionResult, DistributionStats
export CompanyRanking, ProductRanking
export SpreadResult, SpreadDistribution
export TreasuryCurve

# Positioning functions
export analyze_position, get_distribution_stats
export get_percentile_thresholds, compare_to_peers
export filter_products
export calculate_percentile, calculate_rank
export calculate_quartile, get_position_label
export position_summary

# Ranking functions
export RankBy, BEST_RATE, AVG_RATE, PRODUCT_COUNT
export rank_companies, rank_products, get_company_rank
export MarketSummary, market_summary
export rate_leaders_by_duration
export CompetitiveLandscape, competitive_landscape
export group_by_company, group_by_duration
export calculate_tier
export print_company_rankings, print_product_rankings

# Spread functions
export calculate_spread, calculate_product_spread
export calculate_market_spreads, get_spread_distribution
export analyze_spread_position
export DurationSpreadSummary, spread_by_duration
export interpolate_treasury, build_treasury_curve
export ProductSpread, SpreadComparison
export compare_spread_to_market
export print_spread_distribution, print_spread_by_duration

# Competitive constants
export TREASURY_SERIES

# Utility functions
export rates, durations, companies

# Public API - Credit Risk
# AM Best Rating types and functions
export AMBestRating
export A_PLUS_PLUS, A_PLUS, A, A_MINUS
export B_PLUS_PLUS, B_PLUS, B, B_MINUS
export C_PLUS_PLUS, C_PLUS, C, C_MINUS
export D, E, F, S
export RatingPD
export rating_from_string, rating_to_string
export is_secure, is_vulnerable
export get_annual_pd, get_cumulative_pd, get_hazard_rate
export get_pd_term_structure, get_survival_probability
export compare_ratings, pd_summary, print_pd_table
export RATING_STRINGS, STRING_TO_RATING
export AM_BEST_IMPAIRMENT_RATES

# Guaranty fund types and functions
export CoverageType
export LIFE_DEATH_BENEFIT, LIFE_CASH_VALUE
export ANNUITY_DEFERRED, ANNUITY_PAYOUT, ANNUITY_SSA
export GROUP_ANNUITY, HEALTH
export GuarantyFundCoverage
export get_state_coverage, get_coverage_limit
export calculate_covered_amount, calculate_uncovered_amount
export get_coverage_ratio
export compare_state_coverage, states_with_higher_limits
export print_state_coverage, print_coverage_comparison
export STANDARD_LIMITS, STATE_GUARANTY_LIMITS, US_STATE_CODES

# CVA types and functions
export CVAResult
export DEFAULT_INSURANCE_LGD
export calculate_exposure_profile
export calculate_cva, calculate_cva_term_structure
export calculate_credit_adjusted_price
export calculate_credit_spread
export cva_sensitivity_to_rating, cva_sensitivity_to_term
export print_cva_result, print_credit_spreads

# Public API - Rate Setting
# Types
export RateRecommendation, MarginAnalysis, SensitivityPoint
export ConfidenceLevel, HIGH, MEDIUM, LOW
export confidence_string

# Configuration
export RateRecommenderConfig, DEFAULT_RECOMMENDER_CONFIG

# Main recommendation functions
export recommend_rate, recommend_for_spread
export analyze_margin, sensitivity_analysis

# Helper functions
export get_comparables, calculate_rate_percentile
export assess_confidence, build_rationale

# Convenience functions
export quick_rate_recommendation, rate_grid
export compare_recommendations, print_sensitivity_analysis

# Display functions
export print_recommendation, print_margin_analysis

# Public API - Regulatory (VM-21, VM-22)
# [PROTOTYPE] EDUCATIONAL USE ONLY - NOT FOR REGULATORY FILING

# Scenario types
export EconomicScenario, AG43Scenarios
export VasicekParams, EquityParams, RiskNeutralEquityParams
export get_rate_matrix, get_equity_matrix
export risk_neutral_drift, to_equity_params

# Scenario generation
export ScenarioGenerator
export generate_ag43_scenarios, generate_risk_neutral_scenarios
export generate_rate_scenarios, generate_equity_scenarios
export generate_deterministic_scenarios
export calculate_scenario_statistics

# VM-21 types
export PolicyData, VM21Result

# VM-21 calculator
export VM21Calculator
export calculate_cte, calculate_cte70
export calculate_ssa, calculate_reserve
export calculate_cte_levels
export vm21_sensitivity_analysis

# VM-22 types
export ReserveType, DETERMINISTIC, STOCHASTIC
export FixedAnnuityPolicy, StochasticExclusionResult, VM22Result
export get_av

# VM-22 calculator
export VM22Calculator
export calculate_net_premium_reserve
export calculate_deterministic_reserve, calculate_stochastic_reserve
export stochastic_exclusion_test, single_scenario_test
export compare_reserve_methods, vm22_sensitivity

end # module AnnuityCore
