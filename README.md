# AnnuityCore.jl

Core pricing engine for annuity products: Black-Scholes, Greeks, payoffs, and Monte Carlo.

## Installation

```julia
using Pkg
Pkg.add(url="https://github.com/brandonmbehring-dev/AnnuityCore.jl")
```

## Quick Start

```julia
using AnnuityCore

# Price a European call option
call = black_scholes_call(100.0, 100.0, 0.05, 0.02, 0.20, 1.0)
# => ~8.916

# Get Greeks
greeks = black_scholes_greeks(100.0, 100.0, 0.05, 0.02, 0.20, 1.0)
# => BSGreeks(delta=0.577, gamma=0.019, vega=0.375, theta=-6.41, rho=0.453)

# Calculate FIA cap payoff
cap_payoff = CappedCallPayoff(0.10, 0.0)  # 10% cap, 0% floor
result = calculate(cap_payoff, 0.15)      # 15% index return
# => credited_return = 0.10 (capped)

# Calculate RILA buffer payoff
buffer_payoff = BufferPayoff(0.10, 0.20)  # 10% buffer, 20% cap
result = calculate(buffer_payoff, -0.05)  # -5% index return
# => credited_return = 0.0 (buffer absorbs loss)
```

## Features

### Black-Scholes Pricing
- European call/put pricing with dividends
- Full Greeks calculation (delta, gamma, vega, theta, rho)
- Parametric types for automatic differentiation support

### FIA Payoffs
- **CappedCallPayoff**: `min(return, cap)` with 0% floor
- **ParticipationPayoff**: `participation × return` with optional cap
- **SpreadPayoff**: `return - spread` floored at 0%
- **TriggerPayoff**: Fixed rate if threshold met

### RILA Payoffs
- **BufferPayoff**: Absorbs first X% of losses
- **FloorPayoff**: Limits maximum loss to X%
- **BufferWithFloorPayoff**: Combined protection
- **StepRateBufferPayoff**: Tiered buffer protection

### Validation Gates
- No-arbitrage bounds checking
- Put-call parity verification
- HALT/PASS/WARN framework

## Validation

All implementations validated against:
- Hull textbook Example 15.6 (BS pricing)
- 135 hand-verified payoff truth tables
- Python cross-validation (annuity-pricing package)

## Benchmarks

```bash
julia --project=. benchmark/benchmarks.jl
```

Typical performance on modern hardware:
- BS call pricing: ~50 ns
- Payoff calculation: ~5-10 ns
- TTFX: < 3 seconds

## Testing

```bash
julia --project=. -e 'using Pkg; Pkg.test()'
```

## License

MIT
