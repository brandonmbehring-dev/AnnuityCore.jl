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

# GLWB (Guaranteed Lifetime Withdrawal Benefit)
include("GLWB/types.jl")
include("GLWB/rollup.jl")
include("GLWB/tracker.jl")
include("GLWB/mortality.jl")
include("GLWB/path_sim.jl")

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

end # module AnnuityCore
