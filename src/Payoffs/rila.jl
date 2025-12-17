"""
RILA (Registered Index-Linked Annuity) payoff calculations.

Implements protection methods:
- Buffer: Absorbs first X% of losses
- Floor: Limits maximum loss to X%
- Buffer+Floor: Combined protection
- Step-rate: Tiered buffer protection

[T1] RILA payoffs can be negative (unlike FIA), but provide downside protection.
"""

# =============================================================================
# Buffer Payoff
# =============================================================================

"""
    BufferPayoff{T} <: RILAPayoff

RILA buffer protection: absorbs first buffer_rate% of losses.

[T1] Formula:
- If return >= 0: credited = min(return, cap)
- If return < 0 and return >= -buffer: credited = 0 (buffer absorbs)
- If return < -buffer: credited = return + buffer (excess loss)

# Fields
- `buffer_rate::T`: Buffer protection level (decimal, e.g., 0.10 for 10%)
- `cap_rate::Union{T,Nothing}`: Optional cap on gains

# Example
```julia
payoff = BufferPayoff(0.10, 0.20)  # 10% buffer, 20% cap
calculate(payoff, 0.25)   # Returns 0.20 (capped)
calculate(payoff, 0.05)   # Returns 0.05
calculate(payoff, -0.05)  # Returns 0.00 (buffer absorbs)
calculate(payoff, -0.10)  # Returns 0.00 (exact buffer boundary)
calculate(payoff, -0.15)  # Returns -0.05 (excess loss)
```
"""
struct BufferPayoff{T<:Real} <: RILAPayoff
    buffer_rate::T
    cap_rate::Union{T,Nothing}
end

# Constructor with default cap
BufferPayoff(buffer_rate::T) where T<:Real = BufferPayoff(buffer_rate, nothing)

function calculate(p::BufferPayoff{T}, index_return::Real) where T
    r = T(index_return)

    cap_applied = false
    buffer_applied = false

    if r >= 0
        # Positive return: apply cap if present
        if p.cap_rate !== nothing && r > p.cap_rate
            credited = p.cap_rate
            cap_applied = true
        else
            credited = r
        end
    else
        # Negative return: apply buffer
        buffer_applied = true
        if r >= -p.buffer_rate
            # Within buffer zone: fully protected
            credited = zero(T)
        else
            # Beyond buffer: excess loss passed through
            credited = r + p.buffer_rate
        end
    end

    PayoffResult(credited; cap_applied=cap_applied, buffer_applied=buffer_applied)
end


# =============================================================================
# Floor Payoff
# =============================================================================

"""
    FloorPayoff{T} <: RILAPayoff

RILA floor protection: limits maximum loss to floor_rate.

[T1] Formula:
- If return >= floor: credited = min(return, cap)
- If return < floor: credited = floor (loss limited)

# Fields
- `floor_rate::T`: Maximum loss (decimal, negative, e.g., -0.10 for -10%)
- `cap_rate::Union{T,Nothing}`: Optional cap on gains

# Example
```julia
payoff = FloorPayoff(-0.10, 0.20)  # -10% floor, 20% cap
calculate(payoff, 0.25)   # Returns 0.20 (capped)
calculate(payoff, -0.05)  # Returns -0.05 (no floor applied)
calculate(payoff, -0.10)  # Returns -0.10 (at floor)
calculate(payoff, -0.25)  # Returns -0.10 (floor limits loss)
```
"""
struct FloorPayoff{T<:Real} <: RILAPayoff
    floor_rate::T
    cap_rate::Union{T,Nothing}
end

# Constructor with default cap
FloorPayoff(floor_rate::T) where T<:Real = FloorPayoff(floor_rate, nothing)

function calculate(p::FloorPayoff{T}, index_return::Real) where T
    r = T(index_return)

    cap_applied = false
    floor_applied = false

    # Apply floor first
    if r < p.floor_rate
        credited = p.floor_rate
        floor_applied = true
    else
        credited = r
    end

    # Apply cap if present and return is positive
    if p.cap_rate !== nothing && credited > p.cap_rate
        credited = p.cap_rate
        cap_applied = true
    end

    PayoffResult(credited; cap_applied=cap_applied, floor_applied=floor_applied)
end


# =============================================================================
# Buffer with Floor Payoff
# =============================================================================

"""
    BufferWithFloorPayoff{T} <: RILAPayoff

RILA combined buffer and floor protection.

[T1] Formula:
- First applies buffer (absorbs initial losses)
- Then applies floor (limits remaining loss)

# Fields
- `buffer_rate::T`: Buffer protection level (decimal)
- `floor_rate::T`: Maximum loss after buffer (decimal, negative)
- `cap_rate::Union{T,Nothing}`: Optional cap on gains

# Example
```julia
payoff = BufferWithFloorPayoff(0.10, -0.10, 0.20)
# 10% buffer, then -10% floor, 20% cap
calculate(payoff, -0.15)  # Buffer absorbs 10%, remaining -5% passed
calculate(payoff, -0.30)  # Buffer absorbs 10%, -20% becomes -10% (floored)
```
"""
struct BufferWithFloorPayoff{T<:Real} <: RILAPayoff
    buffer_rate::T
    floor_rate::T
    cap_rate::Union{T,Nothing}
end

function calculate(p::BufferWithFloorPayoff{T}, index_return::Real) where T
    r = T(index_return)

    cap_applied = false
    floor_applied = false
    buffer_applied = false

    if r >= 0
        # Positive return: apply cap if present
        if p.cap_rate !== nothing && r > p.cap_rate
            credited = p.cap_rate
            cap_applied = true
        else
            credited = r
        end
    else
        # Negative return: apply buffer first
        buffer_applied = true
        if r >= -p.buffer_rate
            # Within buffer zone: fully protected
            credited = zero(T)
        else
            # Beyond buffer: apply floor to excess loss
            excess_loss = r + p.buffer_rate  # negative value
            if excess_loss < p.floor_rate
                credited = p.floor_rate
                floor_applied = true
            else
                credited = excess_loss
            end
        end
    end

    PayoffResult(credited; cap_applied=cap_applied, floor_applied=floor_applied,
                 buffer_applied=buffer_applied)
end


# =============================================================================
# Step-Rate Buffer Payoff
# =============================================================================

"""
    StepRateBufferPayoff{T} <: RILAPayoff

RILA step-rate (tiered) buffer protection.

Two-tier protection where different buffer rates apply to different loss levels.

# Fields
- `tier1_buffer::T`: First tier buffer (e.g., 0.10 for first 10%)
- `tier2_buffer::T`: Second tier buffer (additional protection)
- `tier2_protection::T`: Protection rate in tier 2 (e.g., 0.50 for 50%)
- `cap_rate::Union{T,Nothing}`: Optional cap on gains

# Example
```julia
# First 10% fully absorbed, next losses 50% absorbed
payoff = StepRateBufferPayoff(0.10, 0.10, 0.50, 0.20)
calculate(payoff, -0.05)  # Returns 0.00 (tier 1 absorbs)
calculate(payoff, -0.15)  # Returns -0.025 (tier 2: 50% of excess -5%)
```
"""
struct StepRateBufferPayoff{T<:Real} <: RILAPayoff
    tier1_buffer::T
    tier2_buffer::T
    tier2_protection::T
    cap_rate::Union{T,Nothing}
end

# Constructor with default cap
function StepRateBufferPayoff(tier1_buffer::T, tier2_buffer::T, tier2_protection::T) where T<:Real
    StepRateBufferPayoff(tier1_buffer, tier2_buffer, tier2_protection, nothing)
end

function calculate(p::StepRateBufferPayoff{T}, index_return::Real) where T
    r = T(index_return)

    cap_applied = false
    buffer_applied = false

    if r >= 0
        # Positive return: apply cap if present
        if p.cap_rate !== nothing && r > p.cap_rate
            credited = p.cap_rate
            cap_applied = true
        else
            credited = r
        end
    else
        buffer_applied = true
        abs_loss = abs(r)

        if abs_loss <= p.tier1_buffer
            # Tier 1: fully absorbed
            credited = zero(T)
        elseif abs_loss <= p.tier1_buffer + p.tier2_buffer
            # Tier 2: partially absorbed
            tier2_loss = abs_loss - p.tier1_buffer
            credited = -tier2_loss * (1 - p.tier2_protection)
        else
            # Beyond tier 2: full loss passed through after buffers
            tier2_absorbed = p.tier2_buffer * p.tier2_protection
            total_absorbed = p.tier1_buffer + tier2_absorbed
            credited = r + total_absorbed
        end
    end

    PayoffResult(credited; cap_applied=cap_applied, buffer_applied=buffer_applied)
end
