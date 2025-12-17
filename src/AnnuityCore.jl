"""
    AnnuityCore

Core pricing engine for annuity products: Black-Scholes, Greeks, payoffs, and Monte Carlo.

This package provides:
- Black-Scholes option pricing with full Greeks
- FIA payoff calculations (cap, participation, spread, trigger)
- RILA payoff calculations (buffer, floor, step-rate)
- Monte Carlo simulation engine with GBM path generation

# Example
```julia
using AnnuityCore

# Price a European call option (Black-Scholes)
price = black_scholes_call(100.0, 100.0, 0.05, 0.02, 0.20, 1.0)

# Price via Monte Carlo
mc_price = monte_carlo_price(100.0, 100.0, 0.05, 0.02, 0.20, 1.0)

# Calculate payoff with buffer protection
payoff = BufferPayoff(0.10, 0.20)
result = calculate(payoff, -0.05)  # Returns 0.0 (buffer absorbs loss)

# Full MC with engine
engine = MonteCarloEngine(n_paths=100000, seed=42)
params = GBMParams(100.0, 0.05, 0.02, 0.20, 1.0)
mc_result = price_european_call(engine, params, 100.0)
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

# Payoff types (needed by monte_carlo.jl)
include("Payoffs/base.jl")
include("Payoffs/fia.jl")
include("Payoffs/rila.jl")

# Monte Carlo engine (depends on payoffs)
include("Options/monte_carlo.jl")

# Validation gates
include("Validation/gates.jl")

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

end # module AnnuityCore
