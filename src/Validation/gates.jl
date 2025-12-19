"""
Validation Gates - HALT/PASS framework for pricing validation.

Implements a multi-stage validation system that checks pricing results
for sanity before allowing them to be used. Gates can HALT (reject with
diagnostics), WARN (proceed with caution), or PASS (allow to proceed).

See: CONSTITUTION.md Section 5
See: docs/knowledge/domain/mgsv_mva.md for regulatory bounds

# Core Types
- `ValidationResult`: Enum (HALT, PASS, WARN)
- `GateResult`: Detailed result from a single gate check
- `ValidationReport`: Collection of results from all gates

# Gate Types
- `PresentValueBoundsGate`: PV within reasonable bounds
- `DurationBoundsGate`: Duration positive and bounded
- `FIAOptionBudgetGate`: Embedded option vs budget check
- `FIAExpectedCreditGate`: Expected credit non-negative
- `RILAMaxLossGate`: Max loss consistent with protection
- `RILAProtectionValueGate`: Protection value bounded
- `ArbitrageBoundsGate`: No-arbitrage violations
- `ProductParameterSanityGate`: Parameter sanity bounds

# Validation Engine
- `ValidationEngine`: Runs multiple gates on pricing results
- `validate_pricing_result`: Quick validation function
- `ensure_valid`: Validate and raise on failure

# Example
```julia
using AnnuityCore

# Create a pricing result
result = FIAPricingResult(
    100.0, 5.0, 3.0, 0.08, 0.55, 0.035,
    Dict{Symbol, Any}()
)

# Validate
report = validate_pricing_result(result, premium=100.0)
if !report.passed
    for gate in halted_gates(report)
        println("HALT: \$(gate.message)")
    end
end

# Or validate and raise
valid_result = ensure_valid(result, premium=100.0)
```

[T1] Based on no-arbitrage principles:
- Option value cannot exceed underlying price
- Put-call parity must hold
- PV must be non-negative
"""

#=============================================================================
# Core Types
=============================================================================#

"""
    ValidationResult

Status of a validation check.

# Values
- `HALT`: Critical failure, stop processing
- `PASS`: Validation passed
- `WARN`: Non-critical issue, proceed with caution
"""
@enum ValidationResult HALT PASS WARN


"""
    GateResult

Detailed result from a single validation gate check.

# Fields
- `status::ValidationResult`: HALT, PASS, or WARN
- `gate_name::String`: Name of the gate that was checked
- `message::String`: Explanation of the result
- `value::Union{Any, Nothing}`: The value that was checked
- `threshold::Union{Any, Nothing}`: The threshold that was applied
"""
struct GateResult
    status::ValidationResult
    gate_name::String
    message::String
    value::Union{Any, Nothing}
    threshold::Union{Any, Nothing}

    function GateResult(;
        status::ValidationResult,
        gate_name::String,
        message::String,
        value::Union{Any, Nothing} = nothing,
        threshold::Union{Any, Nothing} = nothing
    )
        new(status, gate_name, message, value, threshold)
    end
end

"""Check if gate passed (PASS or WARN, not HALT)."""
passed(result::GateResult)::Bool = result.status != HALT


"""
    ValidationReport

Complete validation report from all gates.

# Fields
- `results::Vector{GateResult}`: Results from all gates
"""
struct ValidationReport
    results::Vector{GateResult}
end

"""Get worst status across all gates."""
function overall_status(report::ValidationReport)::ValidationResult
    any(r -> r.status == HALT, report.results) && return HALT
    any(r -> r.status == WARN, report.results) && return WARN
    return PASS
end

"""Check if all gates passed (no HALTs)."""
passed(report::ValidationReport)::Bool = overall_status(report) != HALT

"""Get all gates that halted."""
halted_gates(report::ValidationReport)::Vector{GateResult} =
    filter(r -> r.status == HALT, report.results)

"""Get all gates that warned."""
warned_gates(report::ValidationReport)::Vector{GateResult} =
    filter(r -> r.status == WARN, report.results)

"""Convert report to dictionary for logging."""
function Base.Dict(report::ValidationReport)
    Dict(
        :overall_status => string(overall_status(report)),
        :passed => passed(report),
        :n_halted => length(halted_gates(report)),
        :n_warned => length(warned_gates(report)),
        :results => [
            Dict(
                :gate => r.gate_name,
                :status => string(r.status),
                :message => r.message,
                :value => r.value,
                :threshold => r.threshold
            )
            for r in report.results
        ]
    )
end


#=============================================================================
# Gate Interface
=============================================================================#

"""
    AbstractValidationGate

Base type for validation gates.

Subtypes must implement `check(gate, result; context...)`.
"""
abstract type AbstractValidationGate end

"""Gate name for identification."""
gate_name(::AbstractValidationGate)::String = "base_gate"

"""
    check(gate, result; context...) -> GateResult

Check the pricing result against this gate.

# Arguments
- `gate::AbstractValidationGate`: The gate to check
- `result`: Pricing result to validate (PricingResult, FIAPricingResult, or RILAPricingResult)
- `context...`: Additional context (premium, cap_rate, buffer_rate, etc.)

# Returns
- `GateResult` with status, message, and optional value/threshold
"""
function check end


#=============================================================================
# Gate Implementations
=============================================================================#

"""
    PresentValueBoundsGate

Check that present value is within reasonable bounds.

[T1] PV should be positive and not unreasonably large.

# Fields
- `min_pv::Float64`: Minimum allowed PV (default 0.0)
- `max_pv_multiple::Float64`: Maximum PV as multiple of premium (default 3.0)
"""
struct PresentValueBoundsGate <: AbstractValidationGate
    min_pv::Float64
    max_pv_multiple::Float64

    function PresentValueBoundsGate(;
        min_pv::Float64 = 0.0,
        max_pv_multiple::Float64 = 3.0
    )
        new(min_pv, max_pv_multiple)
    end
end

gate_name(::PresentValueBoundsGate) = "present_value_bounds"

function check(gate::PresentValueBoundsGate, result; premium::Float64 = 100.0, kwargs...)
    pv = result.present_value
    max_pv = premium * gate.max_pv_multiple

    if pv < gate.min_pv
        return GateResult(
            status = HALT,
            gate_name = gate_name(gate),
            message = "PV $(round(pv, digits=4)) below minimum $(gate.min_pv)",
            value = pv,
            threshold = gate.min_pv
        )
    end

    if pv > max_pv
        return GateResult(
            status = HALT,
            gate_name = gate_name(gate),
            message = "PV $(round(pv, digits=4)) exceeds $(gate.max_pv_multiple)x premium",
            value = pv,
            threshold = max_pv
        )
    end

    GateResult(
        status = PASS,
        gate_name = gate_name(gate),
        message = "PV $(round(pv, digits=4)) within bounds",
        value = pv
    )
end


"""
    DurationBoundsGate

Check that duration is within reasonable bounds.

[T1] Duration should be positive and not exceed maximum term.

# Fields
- `max_duration::Float64`: Maximum allowed duration in years (default 30.0)
"""
struct DurationBoundsGate <: AbstractValidationGate
    max_duration::Float64

    DurationBoundsGate(; max_duration::Float64 = 30.0) = new(max_duration)
end

gate_name(::DurationBoundsGate) = "duration_bounds"

function check(gate::DurationBoundsGate, result; kwargs...)
    # Check if result has duration field
    if !hasproperty(result, :duration)
        return GateResult(
            status = PASS,
            gate_name = gate_name(gate),
            message = "Duration not available in result type"
        )
    end

    dur = result.duration

    if dur < 0
        return GateResult(
            status = HALT,
            gate_name = gate_name(gate),
            message = "Duration $(round(dur, digits=4)) is negative",
            value = dur,
            threshold = 0.0
        )
    end

    if dur > gate.max_duration
        return GateResult(
            status = HALT,
            gate_name = gate_name(gate),
            message = "Duration $(round(dur, digits=4)) exceeds maximum $(gate.max_duration)",
            value = dur,
            threshold = gate.max_duration
        )
    end

    GateResult(
        status = PASS,
        gate_name = gate_name(gate),
        message = "Duration $(round(dur, digits=4)) within bounds",
        value = dur
    )
end


"""
    FIAOptionBudgetGate

Check FIA embedded option value against option budget.

[T1] Option value should not exceed budget significantly.

# Fields
- `tolerance::Float64`: Allowed excess over budget (default 0.10 = 10%)
"""
struct FIAOptionBudgetGate <: AbstractValidationGate
    tolerance::Float64

    FIAOptionBudgetGate(; tolerance::Float64 = 0.10) = new(tolerance)
end

gate_name(::FIAOptionBudgetGate) = "fia_option_budget"

function check(gate::FIAOptionBudgetGate, result::FIAPricingResult; kwargs...)
    if result.option_budget <= 0
        return GateResult(
            status = HALT,
            gate_name = gate_name(gate),
            message = "Option budget is zero or negative",
            value = result.option_budget
        )
    end

    ratio = result.embedded_option_value / result.option_budget

    if ratio > 1 + gate.tolerance
        excess_pct = (ratio - 1) * 100
        return GateResult(
            status = HALT,
            gate_name = gate_name(gate),
            message = "Embedded option value $(round(result.embedded_option_value, digits=4)) " *
                      "exceeds budget $(round(result.option_budget, digits=4)) by $(round(excess_pct, digits=1))%",
            value = ratio,
            threshold = 1 + gate.tolerance
        )
    end

    GateResult(
        status = PASS,
        gate_name = gate_name(gate),
        message = "Option value within budget (ratio: $(round(ratio, digits=2)))",
        value = ratio
    )
end

# Skip for non-FIA results
function check(gate::FIAOptionBudgetGate, result; kwargs...)
    GateResult(
        status = PASS,
        gate_name = gate_name(gate),
        message = "Not a FIA result, skipping"
    )
end


"""
    FIAExpectedCreditGate

Check FIA expected credit is non-negative and bounded.

[T1] FIA has 0% floor, so expected credit >= 0.
[T1] Expected credit should not exceed cap rate significantly.
"""
struct FIAExpectedCreditGate <: AbstractValidationGate end

gate_name(::FIAExpectedCreditGate) = "fia_expected_credit"

function check(gate::FIAExpectedCreditGate, result::FIAPricingResult; cap_rate = nothing, kwargs...)
    if result.expected_credit < -0.001  # Small tolerance for numerical error
        return GateResult(
            status = HALT,
            gate_name = gate_name(gate),
            message = "Expected credit $(round(result.expected_credit, digits=4)) is negative " *
                      "(violates 0% floor)",
            value = result.expected_credit,
            threshold = 0.0
        )
    end

    # Check against cap if provided
    if cap_rate !== nothing && result.expected_credit > cap_rate + 0.02
        return GateResult(
            status = HALT,
            gate_name = gate_name(gate),
            message = "Expected credit $(round(result.expected_credit, digits=4)) exceeds " *
                      "cap rate $(round(cap_rate, digits=4))",
            value = result.expected_credit,
            threshold = cap_rate
        )
    end

    GateResult(
        status = PASS,
        gate_name = gate_name(gate),
        message = "Expected credit $(round(result.expected_credit, digits=4)) within bounds",
        value = result.expected_credit
    )
end

# Skip for non-FIA results
function check(gate::FIAExpectedCreditGate, result; kwargs...)
    GateResult(
        status = PASS,
        gate_name = gate_name(gate),
        message = "Not a FIA result, skipping"
    )
end


"""
    RILAMaxLossGate

Check RILA max loss is consistent with protection type.

[T1] Buffer: max_loss = 1 - buffer_rate (unlimited beyond buffer)
[T1] Floor: max_loss = abs(floor_rate) (capped loss)
"""
struct RILAMaxLossGate <: AbstractValidationGate end

gate_name(::RILAMaxLossGate) = "rila_max_loss"

function check(gate::RILAMaxLossGate, result::RILAPricingResult; buffer_rate = nothing, kwargs...)
    if result.max_loss < 0
        return GateResult(
            status = HALT,
            gate_name = gate_name(gate),
            message = "Max loss $(round(result.max_loss, digits=4)) is negative",
            value = result.max_loss,
            threshold = 0.0
        )
    end

    if result.max_loss > 1.0
        return GateResult(
            status = HALT,
            gate_name = gate_name(gate),
            message = "Max loss $(round(result.max_loss, digits=4)) exceeds 100%",
            value = result.max_loss,
            threshold = 1.0
        )
    end

    # Verify consistency with protection type
    if buffer_rate !== nothing
        if result.protection_type == :buffer
            expected_max_loss = 1.0 - buffer_rate
            if abs(result.max_loss - expected_max_loss) > 0.01
                return GateResult(
                    status = WARN,
                    gate_name = gate_name(gate),
                    message = "Buffer max loss $(round(result.max_loss, digits=4)) doesn't match " *
                              "expected $(round(expected_max_loss, digits=4))",
                    value = result.max_loss,
                    threshold = expected_max_loss
                )
            end
        elseif result.protection_type == :floor
            if abs(result.max_loss - buffer_rate) > 0.01
                return GateResult(
                    status = WARN,
                    gate_name = gate_name(gate),
                    message = "Floor max loss $(round(result.max_loss, digits=4)) doesn't match " *
                              "floor rate $(round(buffer_rate, digits=4))",
                    value = result.max_loss,
                    threshold = buffer_rate
                )
            end
        end
    end

    GateResult(
        status = PASS,
        gate_name = gate_name(gate),
        message = "Max loss $(round(result.max_loss, digits=4)) is valid",
        value = result.max_loss
    )
end

# Skip for non-RILA results
function check(gate::RILAMaxLossGate, result; kwargs...)
    GateResult(
        status = PASS,
        gate_name = gate_name(gate),
        message = "Not a RILA result, skipping"
    )
end


"""
    RILAProtectionValueGate

Check RILA protection value is positive and bounded.

[T1] Protection should have positive value.
[T1] Protection value shouldn't exceed premium significantly.

# Fields
- `max_protection_pct::Float64`: Maximum protection value as percentage of premium (default 0.50)
"""
struct RILAProtectionValueGate <: AbstractValidationGate
    max_protection_pct::Float64

    RILAProtectionValueGate(; max_protection_pct::Float64 = 0.50) = new(max_protection_pct)
end

gate_name(::RILAProtectionValueGate) = "rila_protection_value"

function check(gate::RILAProtectionValueGate, result::RILAPricingResult; premium::Float64 = 100.0, kwargs...)
    if result.protection_value < 0
        return GateResult(
            status = HALT,
            gate_name = gate_name(gate),
            message = "Protection value $(round(result.protection_value, digits=4)) is negative",
            value = result.protection_value,
            threshold = 0.0
        )
    end

    max_protection = premium * gate.max_protection_pct

    if result.protection_value > max_protection
        return GateResult(
            status = WARN,
            gate_name = gate_name(gate),
            message = "Protection value $(round(result.protection_value, digits=4)) exceeds " *
                      "$(round(gate.max_protection_pct * 100, digits=0))% of premium",
            value = result.protection_value,
            threshold = max_protection
        )
    end

    GateResult(
        status = PASS,
        gate_name = gate_name(gate),
        message = "Protection value $(round(result.protection_value, digits=4)) is valid",
        value = result.protection_value
    )
end

# Skip for non-RILA results
function check(gate::RILAProtectionValueGate, result; kwargs...)
    GateResult(
        status = PASS,
        gate_name = gate_name(gate),
        message = "Not a RILA result, skipping"
    )
end


"""
    ArbitrageBoundsGate

Check for no-arbitrage violations.

[T1] Option value <= underlying value (no free money)
[T1] Protection value <= max potential loss
"""
struct ArbitrageBoundsGate <: AbstractValidationGate end

gate_name(::ArbitrageBoundsGate) = "arbitrage_bounds"

function check(gate::ArbitrageBoundsGate, result::FIAPricingResult; premium::Float64 = 100.0, kwargs...)
    # Check option value doesn't exceed premium
    if result.embedded_option_value > premium
        return GateResult(
            status = HALT,
            gate_name = gate_name(gate),
            message = "Option value $(round(result.embedded_option_value, digits=4)) exceeds " *
                      "premium $(round(premium, digits=4)) (arbitrage violation)",
            value = result.embedded_option_value,
            threshold = premium
        )
    end

    GateResult(
        status = PASS,
        gate_name = gate_name(gate),
        message = "No arbitrage violations detected"
    )
end

function check(gate::ArbitrageBoundsGate, result::RILAPricingResult; premium::Float64 = 100.0, kwargs...)
    # Check protection value doesn't exceed max potential loss
    max_loss_value = premium * result.max_loss
    if result.protection_value > max_loss_value
        return GateResult(
            status = HALT,
            gate_name = gate_name(gate),
            message = "Protection value $(round(result.protection_value, digits=4)) exceeds " *
                      "max loss value $(round(max_loss_value, digits=4))",
            value = result.protection_value,
            threshold = max_loss_value
        )
    end

    GateResult(
        status = PASS,
        gate_name = gate_name(gate),
        message = "No arbitrage violations detected"
    )
end

# Default for other result types
function check(gate::ArbitrageBoundsGate, result; kwargs...)
    GateResult(
        status = PASS,
        gate_name = gate_name(gate),
        message = "No arbitrage violations detected"
    )
end


"""
    ProductParameterSanityGate

Check product parameters are within reasonable bounds.

Sanity checks to catch data errors or misentered products:
- cap_rate: 0-30% (highest observed caps ~25%)
- participation_rate: 0-300% (leveraged products exist but rare)
- buffer_rate: 0-30% (buffers >25% uncommon)
- spread_rate: 0-10% (spreads >5% uncommon)

# Constants
- `MAX_CAP_RATE = 0.30` (30%)
- `MAX_PARTICIPATION_RATE = 3.00` (300%)
- `MAX_BUFFER_RATE = 0.30` (30%)
- `MAX_SPREAD_RATE = 0.10` (10%)
"""
struct ProductParameterSanityGate <: AbstractValidationGate end

const MAX_CAP_RATE = 0.30
const MAX_PARTICIPATION_RATE = 3.00
const MAX_BUFFER_RATE = 0.30
const MAX_SPREAD_RATE = 0.10

gate_name(::ProductParameterSanityGate) = "product_parameter_sanity"

function check(gate::ProductParameterSanityGate, result;
               cap_rate = nothing,
               participation_rate = nothing,
               buffer_rate = nothing,
               spread_rate = nothing,
               kwargs...)

    issues = String[]

    # Check cap rate
    if cap_rate !== nothing
        if cap_rate < 0
            push!(issues, "cap_rate $(round(cap_rate, digits=4)) is negative")
        elseif cap_rate > MAX_CAP_RATE
            push!(issues, "cap_rate $(round(cap_rate, digits=4)) exceeds maximum $(round(MAX_CAP_RATE * 100, digits=0))%")
        end
    end

    # Check participation rate
    if participation_rate !== nothing
        if participation_rate <= 0
            push!(issues, "participation_rate $(round(participation_rate, digits=4)) must be > 0")
        elseif participation_rate > MAX_PARTICIPATION_RATE
            push!(issues, "participation_rate $(round(participation_rate, digits=4)) exceeds maximum $(round(MAX_PARTICIPATION_RATE * 100, digits=0))%")
        end
    end

    # Check buffer rate
    if buffer_rate !== nothing
        if buffer_rate < 0
            push!(issues, "buffer_rate $(round(buffer_rate, digits=4)) is negative")
        elseif buffer_rate > MAX_BUFFER_RATE
            push!(issues, "buffer_rate $(round(buffer_rate, digits=4)) exceeds maximum $(round(MAX_BUFFER_RATE * 100, digits=0))%")
        end
    end

    # Check spread rate
    if spread_rate !== nothing
        if spread_rate < 0
            push!(issues, "spread_rate $(round(spread_rate, digits=4)) is negative")
        elseif spread_rate > MAX_SPREAD_RATE
            push!(issues, "spread_rate $(round(spread_rate, digits=4)) exceeds maximum $(round(MAX_SPREAD_RATE * 100, digits=0))%")
        end
    end

    if !isempty(issues)
        return GateResult(
            status = HALT,
            gate_name = gate_name(gate),
            message = "Parameter sanity check failed: $(join(issues, "; "))",
            value = issues
        )
    end

    GateResult(
        status = PASS,
        gate_name = gate_name(gate),
        message = "Product parameters within sanity bounds"
    )
end


#=============================================================================
# Standalone Validation Functions (Original API)
=============================================================================#

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
                               tolerance::Real = 1e-10)
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
                                  r::Real, q::Real, τ::Real; tolerance::Real = 0.01)
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


#=============================================================================
# Validation Engine
=============================================================================#

"""
    ValidationEngine

Engine for running validation gates on pricing results.

Combines multiple gates and produces a validation report.

# Fields
- `gates::Vector{AbstractValidationGate}`: Gates to run

# Example
```julia
engine = ValidationEngine()
report = validate(engine, result, premium=100.0)
if passed(report)
    println("Validation passed")
else
    for gate in halted_gates(report)
        println("HALT: \$(gate.message)")
    end
end
```
"""
struct ValidationEngine
    gates::Vector{AbstractValidationGate}

    function ValidationEngine(gates::Vector{<:AbstractValidationGate} = default_gates())
        new(Vector{AbstractValidationGate}(gates))
    end
end

"""Create default set of validation gates."""
function default_gates()::Vector{AbstractValidationGate}
    AbstractValidationGate[
        PresentValueBoundsGate(),
        DurationBoundsGate(),
        FIAOptionBudgetGate(),
        FIAExpectedCreditGate(),
        RILAMaxLossGate(),
        RILAProtectionValueGate(),
        ArbitrageBoundsGate(),
        ProductParameterSanityGate()
    ]
end

"""
    validate(engine, result; context...) -> ValidationReport

Run all validation gates on a pricing result.

# Arguments
- `engine::ValidationEngine`: The validation engine
- `result`: Pricing result to validate
- `context...`: Additional context (premium, cap_rate, buffer_rate, etc.)

# Returns
- `ValidationReport` with all gate results
"""
function validate(engine::ValidationEngine, result; kwargs...)
    results = GateResult[]
    for gate in engine.gates
        gate_result = check(gate, result; kwargs...)
        push!(results, gate_result)
    end
    ValidationReport(results)
end

"""
    validate_and_raise(engine, result; context...) -> result

Validate and raise exception on HALT.

# Arguments
- `engine::ValidationEngine`: The validation engine
- `result`: Pricing result to validate
- `context...`: Additional context

# Returns
- The same result if validation passes

# Throws
- `ErrorException` if any gate HALTs
"""
function validate_and_raise(engine::ValidationEngine, result; kwargs...)
    report = validate(engine, result; kwargs...)

    if !passed(report)
        halt_messages = [g.message for g in halted_gates(report)]
        error(
            "CRITICAL: Validation failed. HALTs:\n" *
            join(["  - $m" for m in halt_messages], "\n")
        )
    end

    result
end


#=============================================================================
# Convenience Functions
=============================================================================#

"""
    validate_pricing_result(result; context...) -> ValidationReport

Quick validation of a pricing result using default gates.

# Arguments
- `result`: Pricing result to validate
- `context...`: Additional context (premium, cap_rate, buffer_rate, etc.)

# Returns
- `ValidationReport` with all gate results

# Example
```julia
report = validate_pricing_result(result, premium=100.0)
if !passed(report)
    println("Validation failed!")
end
```
"""
function validate_pricing_result(result; kwargs...)
    engine = ValidationEngine()
    validate(engine, result; kwargs...)
end


"""
    ensure_valid(result; context...) -> result

Validate and raise if invalid, using default gates.

# Arguments
- `result`: Pricing result to validate
- `context...`: Additional context

# Returns
- The same result if valid

# Throws
- `ErrorException` if validation fails

# Example
```julia
valid_result = ensure_valid(result, premium=100.0)
```
"""
function ensure_valid(result; kwargs...)
    engine = ValidationEngine()
    validate_and_raise(engine, result; kwargs...)
end


#=============================================================================
# Display Functions
=============================================================================#

"""Print gate result in human-readable format."""
function Base.show(io::IO, result::GateResult)
    status_char = result.status == PASS ? "✓" : (result.status == WARN ? "⚠" : "✗")
    print(io, "[$status_char] $(result.gate_name): $(result.message)")
end

"""Print validation report in human-readable format."""
function Base.show(io::IO, report::ValidationReport)
    status = overall_status(report)
    status_str = status == PASS ? "PASSED" : (status == WARN ? "WARNED" : "HALTED")
    println(io, "ValidationReport: $status_str")
    println(io, "  Halted: $(length(halted_gates(report)))")
    println(io, "  Warned: $(length(warned_gates(report)))")
    println(io, "  Passed: $(count(r -> r.status == PASS, report.results))")
    for result in report.results
        println(io, "    ", result)
    end
end

"""
    print_validation_report(report::ValidationReport; io::IO=stdout)

Print detailed validation report.
"""
function print_validation_report(report::ValidationReport; io::IO = stdout)
    status = overall_status(report)
    status_str = status == PASS ? "PASSED ✓" : (status == WARN ? "WARNED ⚠" : "HALTED ✗")

    println(io, "=" ^ 60)
    println(io, "Validation Report: $status_str")
    println(io, "=" ^ 60)

    # Print halted gates first
    halted = halted_gates(report)
    if !isempty(halted)
        println(io, "\n❌ HALTED GATES ($(length(halted))):")
        for g in halted
            println(io, "  • $(g.gate_name): $(g.message)")
            g.value !== nothing && println(io, "    Value: $(g.value)")
            g.threshold !== nothing && println(io, "    Threshold: $(g.threshold)")
        end
    end

    # Print warned gates
    warned = warned_gates(report)
    if !isempty(warned)
        println(io, "\n⚠️  WARNED GATES ($(length(warned))):")
        for g in warned
            println(io, "  • $(g.gate_name): $(g.message)")
        end
    end

    # Print passed gates
    passed_gates = filter(r -> r.status == PASS, report.results)
    if !isempty(passed_gates)
        println(io, "\n✓ PASSED GATES ($(length(passed_gates))):")
        for g in passed_gates
            println(io, "  • $(g.gate_name)")
        end
    end

    println(io, "=" ^ 60)
end
