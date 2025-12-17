"""
Validation gates for option pricing.

Implements HALT/PASS/WARN framework for catching pricing errors
before they propagate.

[T1] Based on no-arbitrage principles:
- Option value cannot exceed underlying price
- Put-call parity must hold
"""

"""
    ValidationResult

Result of a validation check.

# Values
- `HALT`: Critical failure, stop processing
- `PASS`: Validation passed
- `WARN`: Non-critical issue, proceed with caution
"""
@enum ValidationResult HALT PASS WARN


"""
    validate_no_arbitrage(option_value, underlying_price; tolerance=1e-10) -> ValidationResult

Check that option value does not exceed underlying price.

[T1] No-arbitrage principle: A call option gives the right to buy
at strike K, so its value cannot exceed the underlying price S.
Similarly, a put cannot exceed K (ignoring discounting).

# Arguments
- `option_value::Real`: The computed option price
- `underlying_price::Real`: The spot price S
- `tolerance::Real`: Numerical tolerance for comparison

# Returns
- `HALT` if option_value > underlying_price + tolerance
- `PASS` otherwise
"""
function validate_no_arbitrage(option_value::Real, underlying_price::Real;
                               tolerance::Real=1e-10)
    if option_value > underlying_price + tolerance
        return HALT
    end
    return PASS
end


"""
    validate_put_call_parity(call, put, S, K, r, q, τ; tolerance=0.01) -> ValidationResult

Check that put-call parity holds.

[T1] Put-call parity (Hull, Eq. 11.6):
    C - P = S·e^(-qτ) - K·e^(-rτ)

This is a fundamental arbitrage relationship that must hold
for any consistent pricing model.

# Arguments
- `call::Real`: Call option price
- `put::Real`: Put option price
- `S::Real`: Spot price
- `K::Real`: Strike price
- `r::Real`: Risk-free rate
- `q::Real`: Dividend yield
- `τ::Real`: Time to expiry
- `tolerance::Real`: Maximum acceptable violation

# Returns
- `HALT` if |violation| > tolerance
- `WARN` if 0.001 < |violation| <= tolerance
- `PASS` otherwise
"""
function validate_put_call_parity(call::Real, put::Real, S::Real, K::Real,
                                  r::Real, q::Real, τ::Real; tolerance::Real=0.01)
    # Put-call parity: C - P = S·e^(-qτ) - K·e^(-rτ)
    lhs = call - put
    rhs = S * exp(-q * τ) - K * exp(-r * τ)
    violation = abs(lhs - rhs)

    if violation > tolerance
        return HALT
    elseif violation > 0.001
        return WARN
    end
    return PASS
end
