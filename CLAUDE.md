# AnnuityCore.jl

Core pricing engine for annuity products. Base layer of the Annuity Julia package suite.

## Development

### Build & Test

```bash
# Run tests
julia --project=. -e "using Pkg; Pkg.test()"

# Run benchmarks
julia --project=. benchmark/benchmarks.jl

# REPL development
julia --project=.
```

### Architecture Notes

**Package Suite Hierarchy**:
```
AnnuityCore.jl  ← YOU ARE HERE (base math layer)
    ↑
AnnuityData.jl  (product schemas, no Core dependency)
    ↑
AnnuityProducts.jl (uses both Core + Data)
```

**Key Design Decisions**:

1. **Parametric types for AD support**: All pricing functions accept `Real` subtypes to enable Zygote autodiff
2. **Validation gates**: HALT/PASS/WARN framework catches impossible scenarios before they propagate
3. **No-arbitrage enforcement**: Put-call parity and bounds checking are mandatory, not optional

**Dependencies**:
- `Zygote`: Automatic differentiation for Greeks and sensitivities
- `Distributions`: Probability distributions for Monte Carlo
- `StableRNGs`: Reproducible random number generation

### Testing Patterns

**Truth table validation**: 135 hand-verified payoff scenarios in `test/fixtures/`
- Each payoff type has exhaustive edge cases
- Python cross-validation against `annuity-pricing` package
- Hull textbook examples for Black-Scholes

**What to test for new payoffs**:
1. Zero return edge case
2. Exact threshold boundaries (cap hit, buffer exhausted)
3. Extreme values (+/- 100%)
4. Put-call parity if applicable

## Contributing

**Before adding a new payoff type**:
1. Document the crediting formula mathematically
2. Create truth table with 10+ test cases
3. Verify against textbook or industry source
4. Add to payoff type hierarchy in `src/payoffs/`

**Code style**: Follow existing patterns—immutable structs, pure functions, explicit types.

---

**Hub**: @~/Claude/lever_of_archimedes/
**Related**: AnnuityData.jl, AnnuityProducts.jl
