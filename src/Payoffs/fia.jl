"""
FIA (Fixed Indexed Annuity) payoff calculations.

Implements crediting methods:
- Cap: min(return, cap)
- Participation: participation_rate × return (optionally capped)
- Spread: max(0, return - spread) (optionally capped)
- Trigger: fixed rate if threshold met, else 0

[T1] All FIA payoffs enforce a 0% floor - no negative credited returns.
"""

# =============================================================================
# Capped Call Payoff
# =============================================================================

"""
    CappedCallPayoff{T} <: FIAPayoff

FIA cap method: credits min(index_return, cap_rate), floored at floor_rate.

[T1] Formula: credited = max(floor, min(return, cap))

# Fields
- `cap_rate::T`: Maximum credited return (decimal)
- `floor_rate::T`: Minimum credited return (decimal, typically 0.0)

# Example
```julia
payoff = CappedCallPayoff(0.10, 0.0)  # 10% cap, 0% floor
calculate(payoff, 0.15)  # Returns 0.10 (capped)
calculate(payoff, 0.05)  # Returns 0.05 (uncapped)
calculate(payoff, -0.10) # Returns 0.00 (floored)
```
"""
struct CappedCallPayoff{T<:Real} <: FIAPayoff
    cap_rate::T
    floor_rate::T
end

# Constructor with default floor
CappedCallPayoff(cap_rate::T) where T<:Real = CappedCallPayoff(cap_rate, zero(T))

function calculate(p::CappedCallPayoff{T}, index_return::Real) where T
    r = T(index_return)

    # Apply cap
    capped = min(r, p.cap_rate)
    cap_applied = r > p.cap_rate

    # Apply floor (enforce 0% minimum for FIA)
    floored = max(capped, p.floor_rate)
    floor_applied = capped < p.floor_rate

    PayoffResult(floored; cap_applied=cap_applied, floor_applied=floor_applied)
end


# =============================================================================
# Participation Payoff
# =============================================================================

"""
    ParticipationPayoff{T} <: FIAPayoff

FIA participation method: credits participation_rate × index_return.

[T1] Formula: credited = max(floor, min(participation × return, cap))

# Fields
- `participation_rate::T`: Participation rate (decimal, e.g., 0.80 for 80%)
- `cap_rate::Union{T,Nothing}`: Optional cap on credited return
- `floor_rate::T`: Minimum credited return (decimal, typically 0.0)

# Example
```julia
payoff = ParticipationPayoff(0.80, 0.15, 0.0)  # 80% participation, 15% cap
calculate(payoff, 0.20)  # Returns 0.15 (0.80 × 0.20 = 0.16, capped at 0.15)
calculate(payoff, 0.10)  # Returns 0.08 (0.80 × 0.10)
```
"""
struct ParticipationPayoff{T<:Real} <: FIAPayoff
    participation_rate::T
    cap_rate::Union{T,Nothing}
    floor_rate::T
end

# Constructor with defaults
function ParticipationPayoff(participation_rate::T;
                             cap_rate::Union{T,Nothing}=nothing,
                             floor_rate::T=zero(T)) where T<:Real
    ParticipationPayoff(participation_rate, cap_rate, floor_rate)
end

function calculate(p::ParticipationPayoff{T}, index_return::Real) where T
    r = T(index_return)

    # Apply participation rate
    credited = p.participation_rate * r

    # Apply cap if present
    cap_applied = false
    if p.cap_rate !== nothing && credited > p.cap_rate
        credited = p.cap_rate
        cap_applied = true
    end

    # Apply floor (enforce 0% minimum for FIA)
    floor_applied = credited < p.floor_rate
    credited = max(credited, p.floor_rate)

    PayoffResult(credited; cap_applied=cap_applied, floor_applied=floor_applied)
end


# =============================================================================
# Spread Payoff
# =============================================================================

"""
    SpreadPayoff{T} <: FIAPayoff

FIA spread method: credits index_return minus spread, floored at 0.

[T1] Formula: credited = max(floor, min(max(0, return - spread), cap))

# Fields
- `spread_rate::T`: Spread deducted from return (decimal)
- `cap_rate::Union{T,Nothing}`: Optional cap on credited return
- `floor_rate::T`: Minimum credited return (decimal, typically 0.0)

# Example
```julia
payoff = SpreadPayoff(0.02, nothing, 0.0)  # 2% spread, no cap
calculate(payoff, 0.10)  # Returns 0.08 (0.10 - 0.02)
calculate(payoff, 0.01)  # Returns 0.00 (spread > return, floored)
```
"""
struct SpreadPayoff{T<:Real} <: FIAPayoff
    spread_rate::T
    cap_rate::Union{T,Nothing}
    floor_rate::T
end

# Constructor with defaults
function SpreadPayoff(spread_rate::T;
                      cap_rate::Union{T,Nothing}=nothing,
                      floor_rate::T=zero(T)) where T<:Real
    SpreadPayoff(spread_rate, cap_rate, floor_rate)
end

function calculate(p::SpreadPayoff{T}, index_return::Real) where T
    r = T(index_return)

    # Apply spread (can go negative before floor)
    credited = r - p.spread_rate

    # Apply cap if present
    cap_applied = false
    if p.cap_rate !== nothing && credited > p.cap_rate
        credited = p.cap_rate
        cap_applied = true
    end

    # Apply floor (enforce 0% minimum for FIA)
    floor_applied = credited < p.floor_rate
    credited = max(credited, p.floor_rate)

    PayoffResult(credited; cap_applied=cap_applied, floor_applied=floor_applied)
end


# =============================================================================
# Trigger Payoff
# =============================================================================

"""
    TriggerPayoff{T} <: FIAPayoff

FIA trigger method: credits fixed rate if index return >= threshold.

[T1] Formula: credited = trigger_rate if return >= threshold, else floor

Note: "At threshold" means >= threshold triggers the rate.

# Fields
- `trigger_rate::T`: Rate credited when triggered (decimal)
- `trigger_threshold::T`: Minimum return to trigger (decimal)
- `floor_rate::T`: Rate when not triggered (decimal, typically 0.0)

# Example
```julia
payoff = TriggerPayoff(0.08, 0.0, 0.0)  # 8% if positive, 0% otherwise
calculate(payoff, 0.01)   # Returns 0.08 (triggered)
calculate(payoff, 0.0)    # Returns 0.08 (at threshold = triggered)
calculate(payoff, -0.01)  # Returns 0.00 (not triggered)
```
"""
struct TriggerPayoff{T<:Real} <: FIAPayoff
    trigger_rate::T
    trigger_threshold::T
    floor_rate::T
end

# Constructor with defaults
function TriggerPayoff(trigger_rate::T;
                       trigger_threshold::T=zero(T),
                       floor_rate::T=zero(T)) where T<:Real
    TriggerPayoff(trigger_rate, trigger_threshold, floor_rate)
end

function calculate(p::TriggerPayoff{T}, index_return::Real) where T
    r = T(index_return)

    # Check if threshold is met (>= triggers)
    triggered = r >= p.trigger_threshold

    credited = triggered ? p.trigger_rate : p.floor_rate

    # Floor is effectively applied when not triggered
    floor_applied = !triggered

    PayoffResult(credited; cap_applied=false, floor_applied=floor_applied)
end
