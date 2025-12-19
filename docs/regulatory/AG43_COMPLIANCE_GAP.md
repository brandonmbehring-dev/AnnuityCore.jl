# AG43/VM-21/VM-22 Compliance Gap Analysis

**Status**: PROTOTYPE - EDUCATIONAL USE ONLY

This document details what the AnnuityCore.jl regulatory module provides versus what production regulatory filings require.

---

## What This Implementation Provides

### VM-21 (Variable Annuities)

| Component | Implementation | Notes |
|-----------|---------------|-------|
| CTE(70) calculation | Yes | Average of worst 30% scenarios |
| Standard Scenario Amount (SSA) | Yes | Simplified deterministic projection |
| CSV floor | Yes | Basic floor enforcement |
| Reserve = max(CTE70, SSA, CSV) | Yes | Core VM-21 formula |
| Scenario generation | Simplified | GBM equity + Vasicek rates |
| Sensitivity analysis | Yes | GWB, age, AV shocks |

### VM-22 (Fixed Annuities)

| Component | Implementation | Notes |
|-----------|---------------|-------|
| Net Premium Reserve (NPR) | Yes | Basic NPR calculation |
| Deterministic Reserve (DR) | Yes | Single scenario projection |
| Stochastic Reserve (SR) | Yes | CTE(70) over scenarios |
| Stochastic Exclusion Test (SET) | Yes | Liability/asset ratio test |
| Single Scenario Test (SST) | Yes | Simplified test |

### Scenario Generation

| Component | Implementation | Notes |
|-----------|---------------|-------|
| Interest rate paths | Vasicek model | dr = kappa(theta - r)dt + sigma*dW |
| Equity return paths | GBM | dS/S = mu*dt + sigma*dW |
| Risk-neutral scenarios | Yes | Drift = r - q |
| Correlated shocks | Yes | Cholesky decomposition |
| Reproducibility | Yes | Seeded RNG |

---

## What's Missing for Production Compliance

### 1. NAIC-Prescribed Scenario Generators

**Required**: GOES (Generator of Economic Scenarios) or AAA ESG

**Gap**: Our implementation uses simplified Vasicek + GBM models instead of the NAIC-prescribed generators.

```
Current: Vasicek(kappa=0.20, theta=0.04, sigma=0.01)
Required: NAIC VM-20 prescribed generator with:
  - Mean reversion target calibrated to Treasury forwards
  - Volatility calibrated to swaption market
  - Fund mapping for equity scenarios
```

**Impact**: Scenario distributions will differ from prescribed requirements. Not acceptable for statutory reporting.

### 2. Conditional Dynamic Hedging Scenarios (CDHS)

**Required**: VM-21 Section 4.D requires CDHS for companies with hedging programs.

**Gap**: Not implemented.

```
Missing:
- Hedge program modeling
- Dynamic rebalancing simulation
- Basis risk quantification
- Hedge breakage scenarios
```

### 3. Complete Policy Data Model

**Required**: Full contract feature representation per VM-21 Section 3.

**Gap**: Simplified `PolicyData` struct captures only:
- Account value, GWB, age, CSV
- Withdrawal rate, fee rate

```
Missing fields:
- Death benefit type (GMDB variants)
- Income benefit phase/deferral
- Step-up provisions
- Rider charges by benefit
- Subaccount allocations
- Free withdrawal amounts
- Surrender charge schedules
- Contract anniversary logic
```

### 4. Prescribed Mortality Tables

**Required**: VM-21 Section 6.C specifies mortality tables with improvement scales.

**Gap**: Uses SOA 2012 IAM as default, no mortality improvement.

```
Required:
- 2012 IAM with Scale G2
- Gender-distinct tables
- Select and ultimate structure
- Mortality improvement projection
- Credibility blending for company experience
```

### 5. Asset Portfolio Modeling

**Required**: VM-21 Section 4.A.4 requires asset/liability matching analysis.

**Gap**: Not implemented - we model liability only.

```
Missing:
- Asset portfolio representation
- Reinvestment assumptions
- Disinvestment assumptions
- Credit spreads by rating
- Default and recovery assumptions
- Asset cash flow projection
```

### 6. Credibility Weighting

**Required**: VM-21 Section 6 allows company experience with credibility procedures.

**Gap**: Uses static industry tables only.

```
Missing:
- Company experience data integration
- Credibility factor calculation
- Blending methodology
- Experience study requirements
```

### 7. Hedge Effectiveness Testing

**Required**: For companies using the Hedging Effectiveness approach.

**Gap**: Not implemented.

```
Missing:
- Hedge attribution analysis
- Error quantification
- E-factor calculation
- Clearly Defined Hedging Strategy documentation
```

### 8. Actuarial Certification Requirements

**Required**: FSA/MAAA certification for filed reserves.

**Gap**: This is a software implementation, not an actuarial opinion.

```
Required for filing:
- Qualified actuary certification
- Actuarial Memorandum
- VM-31 reporting requirements
- Internal controls documentation
```

---

## Quantified Gap Impact

| Gap | Impact on Reserve | Severity |
|-----|-------------------|----------|
| Scenario generator | 10-30% difference | CRITICAL |
| Mortality improvement | 3-8% understatement | HIGH |
| Asset modeling | Unknown (liability-only) | HIGH |
| Policy features | 5-15% depending on book | MEDIUM |
| CDHS | Significant for hedgers | HIGH |

---

## Appropriate Use Cases

### Acceptable Uses

1. **Education**: Understanding VM-21/VM-22 mechanics
2. **Research**: Exploring reserve sensitivity to assumptions
3. **Prototyping**: Initial product design analysis
4. **Training**: Actuarial student learning tool
5. **Benchmarking**: Rough order-of-magnitude estimates

### NOT Acceptable For

1. **Statutory filings**: NAIC Annual Statement
2. **Rate filings**: State insurance department submissions
3. **GAAP/IFRS**: Financial statement reserves
4. **Pricing decisions**: Production rate setting
5. **Reinsurance**: Treaty pricing or reserving

---

## Path to Production Compliance

For organizations needing production-ready VM-21/VM-22:

### Option 1: Commercial Vendor

| Vendor | Product | Notes |
|--------|---------|-------|
| Moody's | AXIS | Industry standard for VA |
| Milliman | MG-ALFA | Widely used |
| Towers Watson | MoSes | Life and annuity |
| FIS | Prophet | Global platform |

### Option 2: Build on This Foundation

Required enhancements:

1. **Integrate AAA ESG** (~3-6 months)
   - License AAA Economic Scenario Generator
   - Build Julia wrapper for scenario files
   - Implement fund mapping

2. **Extend Policy Model** (~2-3 months)
   - Add all VM-21 required fields
   - Contract feature library
   - Validation against actual inforce

3. **Add Asset Module** (~3-6 months)
   - Asset class definitions
   - Cash flow projection
   - Credit/default modeling

4. **Mortality Enhancement** (~1-2 months)
   - Scale G2 improvement
   - Credibility framework
   - Experience data integration

5. **Documentation/Controls** (~2-3 months)
   - Actuarial memorandum templates
   - VM-31 reporting
   - SOC 2 controls for model governance

**Total estimated effort**: 12-18 months with qualified actuarial team.

---

## References

- NAIC Valuation Manual (VM-20, VM-21, VM-22)
- AAA Practice Note: Application of the Valuation Manual
- SOA Research Report: Variable Annuity Statutory Reserve and Capital
- Academy of Actuaries: GOES Documentation

---

## Version History

| Version | Date | Change |
|---------|------|--------|
| 1.0 | 2025-12-19 | Initial gap analysis |
