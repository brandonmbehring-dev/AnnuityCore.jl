"""
Base types for payoff calculations.

Provides the abstract type hierarchy and common result types
for FIA and RILA payoff calculations.
"""

"""
    AbstractPayoff

Abstract base type for all payoff calculations.

Subtypes:
- `FIAPayoff`: Fixed indexed annuity payoffs (0% floor enforced)
- `RILAPayoff`: Registered index-linked annuity payoffs (can be negative)
"""
abstract type AbstractPayoff end

"""
    FIAPayoff <: AbstractPayoff

Abstract type for FIA (Fixed Indexed Annuity) payoffs.

[T1] FIA contracts guarantee a minimum 0% floor on credited returns.
All FIA payoff implementations must enforce this floor.
"""
abstract type FIAPayoff <: AbstractPayoff end

"""
    RILAPayoff <: AbstractPayoff

Abstract type for RILA (Registered Index-Linked Annuity) payoffs.

[T1] RILA contracts can have negative credited returns but provide
downside protection through buffers or floors.
"""
abstract type RILAPayoff <: AbstractPayoff end


"""
    PayoffResult{T}

Result of a payoff calculation with metadata.

# Fields
- `credited_return::T`: The credited return (decimal)
- `cap_applied::Bool`: Whether the cap was applied
- `floor_applied::Bool`: Whether the floor was applied
- `buffer_applied::Bool`: Whether buffer protection was applied
"""
struct PayoffResult{T<:Real}
    credited_return::T
    cap_applied::Bool
    floor_applied::Bool
    buffer_applied::Bool
end

# Convenience constructor
function PayoffResult(credited_return::T;
                      cap_applied::Bool=false,
                      floor_applied::Bool=false,
                      buffer_applied::Bool=false) where T<:Real
    PayoffResult(credited_return, cap_applied, floor_applied, buffer_applied)
end


"""
    calculate(payoff::AbstractPayoff, index_return::Real) -> PayoffResult

Calculate the credited return for a given index return.

This is the main dispatch point for payoff calculations.
Each payoff type implements its own method.

# Arguments
- `payoff::AbstractPayoff`: The payoff specification
- `index_return::Real`: The index return (decimal, e.g., -0.15 for -15%)

# Returns
- `PayoffResult`: The credited return with metadata
"""
function calculate end
