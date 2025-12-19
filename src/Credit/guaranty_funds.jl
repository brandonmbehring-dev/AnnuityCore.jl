"""
State guaranty association coverage for life insurance and annuities.

[T2] Based on NOLHGA (National Organization of Life & Health Insurance
Guaranty Associations) published limits and state-specific statutes.

Key coverage limits (typical):
- Life insurance death benefits: 300,000
- Annuity benefits (deferred): 250,000
- Annuity benefits (in payout): 300,000
- Group annuities: 5,000,000

References
----------
[T2] NOLHGA. "How You're Protected."
     https://nolhga.com/policyholders/how-youre-protected/
[T2] State guaranty association websites and statutes
"""

#=============================================================================
# Standard Limits
=============================================================================#

"""
Standard NOLHGA limits (used as default for most states).
"""
const STANDARD_LIMITS = GuarantyFundCoverage(
    state = "DEFAULT",
    life_death_benefit = 300_000.0,
    life_cash_value = 100_000.0,
    annuity_deferred = 250_000.0,
    annuity_payout = 300_000.0,
    annuity_ssa = 250_000.0,
    group_annuity = 5_000_000.0,
    health = 500_000.0,
    coverage_percentage = 1.0
)

#=============================================================================
# State-Specific Limits
=============================================================================#

"""
State-specific guaranty fund limits where they differ from standard.
[T2] Based on NOLHGA and state guaranty association websites.
"""
const STATE_GUARANTY_LIMITS = Dict{String, GuarantyFundCoverage}(
    # California - 80% of benefits
    "CA" => GuarantyFundCoverage(
        state = "CA",
        life_death_benefit = 300_000.0,
        life_cash_value = 100_000.0,
        annuity_deferred = 250_000.0,
        annuity_payout = 300_000.0,
        annuity_ssa = 250_000.0,
        group_annuity = 5_000_000.0,
        health = 668_205.0,  # Inflation-adjusted as of 2024
        coverage_percentage = 0.80  # California covers only 80%
    ),

    # New York - higher limits across the board
    "NY" => GuarantyFundCoverage(
        state = "NY",
        life_death_benefit = 500_000.0,
        life_cash_value = 100_000.0,
        annuity_deferred = 500_000.0,
        annuity_payout = 500_000.0,
        annuity_ssa = 500_000.0,
        group_annuity = 5_000_000.0,
        health = 500_000.0,
        coverage_percentage = 1.0
    ),

    # Minnesota - higher SSA limits
    "MN" => GuarantyFundCoverage(
        state = "MN",
        life_death_benefit = 300_000.0,
        life_cash_value = 100_000.0,
        annuity_deferred = 250_000.0,
        annuity_payout = 300_000.0,
        annuity_ssa = 410_000.0,  # Higher for SSA and 10yr+ certain
        group_annuity = 5_000_000.0,
        health = 500_000.0,
        coverage_percentage = 1.0
    ),

    # North Carolina - higher SSA limits
    "NC" => GuarantyFundCoverage(
        state = "NC",
        life_death_benefit = 300_000.0,
        life_cash_value = 100_000.0,
        annuity_deferred = 300_000.0,
        annuity_payout = 300_000.0,
        annuity_ssa = 1_000_000.0,  # $1M for SSA
        group_annuity = 5_000_000.0,
        health = 500_000.0,
        coverage_percentage = 1.0
    ),

    # Texas - standard limits
    "TX" => GuarantyFundCoverage(
        state = "TX",
        life_death_benefit = 300_000.0,
        life_cash_value = 100_000.0,
        annuity_deferred = 250_000.0,
        annuity_payout = 300_000.0,
        annuity_ssa = 250_000.0,
        group_annuity = 5_000_000.0,
        health = 500_000.0,
        coverage_percentage = 1.0
    ),

    # Florida - standard limits
    "FL" => GuarantyFundCoverage(
        state = "FL",
        life_death_benefit = 300_000.0,
        life_cash_value = 100_000.0,
        annuity_deferred = 250_000.0,
        annuity_payout = 300_000.0,
        annuity_ssa = 250_000.0,
        group_annuity = 5_000_000.0,
        health = 500_000.0,
        coverage_percentage = 1.0
    ),

    # Washington - higher limits
    "WA" => GuarantyFundCoverage(
        state = "WA",
        life_death_benefit = 500_000.0,
        life_cash_value = 100_000.0,
        annuity_deferred = 500_000.0,
        annuity_payout = 500_000.0,
        annuity_ssa = 500_000.0,
        group_annuity = 5_000_000.0,
        health = 500_000.0,
        coverage_percentage = 1.0
    ),

    # New Jersey - higher limits
    "NJ" => GuarantyFundCoverage(
        state = "NJ",
        life_death_benefit = 500_000.0,
        life_cash_value = 100_000.0,
        annuity_deferred = 500_000.0,
        annuity_payout = 500_000.0,
        annuity_ssa = 500_000.0,
        group_annuity = 5_000_000.0,
        health = 500_000.0,
        coverage_percentage = 1.0
    ),
)

#=============================================================================
# Coverage Lookup Functions
=============================================================================#

"""
    get_state_coverage(state::String) -> GuarantyFundCoverage

Get guaranty fund coverage limits for a state.

[T2] Returns state-specific limits if available, else standard limits.

# Arguments
- `state`: Two-letter state code (e.g., "CA", "NY")

# Returns
- `GuarantyFundCoverage` for the state

# Example
```julia
coverage = get_state_coverage("CA")
coverage.annuity_deferred     # 250000.0
coverage.coverage_percentage  # 0.8
```
"""
function get_state_coverage(state::String)::GuarantyFundCoverage
    state_upper = uppercase(strip(state))

    # Check if we have state-specific limits
    if haskey(STATE_GUARANTY_LIMITS, state_upper)
        return STATE_GUARANTY_LIMITS[state_upper]
    end

    # Return standard limits with state code
    GuarantyFundCoverage(
        state = state_upper,
        life_death_benefit = STANDARD_LIMITS.life_death_benefit,
        life_cash_value = STANDARD_LIMITS.life_cash_value,
        annuity_deferred = STANDARD_LIMITS.annuity_deferred,
        annuity_payout = STANDARD_LIMITS.annuity_payout,
        annuity_ssa = STANDARD_LIMITS.annuity_ssa,
        group_annuity = STANDARD_LIMITS.group_annuity,
        health = STANDARD_LIMITS.health,
        coverage_percentage = STANDARD_LIMITS.coverage_percentage
    )
end

"""
    get_coverage_limit(state::String, coverage_type::CoverageType) -> Float64

Get the coverage limit for a specific type in a state.

# Arguments
- `state`: Two-letter state code
- `coverage_type`: Type of coverage

# Returns
- Coverage limit in dollars
"""
function get_coverage_limit(state::String, coverage_type::CoverageType)::Float64
    coverage = get_state_coverage(state)

    if coverage_type == LIFE_DEATH_BENEFIT
        coverage.life_death_benefit
    elseif coverage_type == LIFE_CASH_VALUE
        coverage.life_cash_value
    elseif coverage_type == ANNUITY_DEFERRED
        coverage.annuity_deferred
    elseif coverage_type == ANNUITY_PAYOUT
        coverage.annuity_payout
    elseif coverage_type == ANNUITY_SSA
        coverage.annuity_ssa
    elseif coverage_type == GROUP_ANNUITY
        coverage.group_annuity
    elseif coverage_type == HEALTH
        coverage.health
    else
        error("CRITICAL: Unknown coverage type $coverage_type")
    end
end

#=============================================================================
# Coverage Calculation Functions
=============================================================================#

"""
    calculate_covered_amount(benefit_amount::Float64, state::String, coverage_type::CoverageType) -> Float64

Calculate amount covered by state guaranty fund.

[T2] Returns minimum of benefit and state limit, adjusted by coverage %.

# Arguments
- `benefit_amount`: Total benefit/contract value
- `state`: Two-letter state code
- `coverage_type`: Type of coverage

# Returns
- Amount covered by guaranty fund

# Example
```julia
calculate_covered_amount(300000, "CA", ANNUITY_DEFERRED)
# 200000.0 (80% of 250k limit)

calculate_covered_amount(100000, "TX", ANNUITY_DEFERRED)
# 100000.0 (full amount, under limit)
```
"""
function calculate_covered_amount(
    benefit_amount::Float64,
    state::String,
    coverage_type::CoverageType
)::Float64
    benefit_amount <= 0 && return 0.0

    coverage = get_state_coverage(state)
    limit = get_coverage_limit(state, coverage_type)

    # Apply limit
    capped = min(benefit_amount, limit)

    # Apply coverage percentage
    capped * coverage.coverage_percentage
end

"""
    calculate_uncovered_amount(benefit_amount::Float64, state::String, coverage_type::CoverageType) -> Float64

Calculate amount NOT covered by state guaranty fund.

This is the amount exposed to insurer credit risk.

# Arguments
- `benefit_amount`: Total benefit/contract value
- `state`: Two-letter state code
- `coverage_type`: Type of coverage

# Returns
- Amount at credit risk (not covered by guaranty)

# Example
```julia
calculate_uncovered_amount(500000, "TX", ANNUITY_DEFERRED)
# 250000.0 (500k - 250k limit)

calculate_uncovered_amount(100000, "TX", ANNUITY_DEFERRED)
# 0.0 (fully covered)
```
"""
function calculate_uncovered_amount(
    benefit_amount::Float64,
    state::String,
    coverage_type::CoverageType
)::Float64
    covered = calculate_covered_amount(benefit_amount, state, coverage_type)
    max(0.0, benefit_amount - covered)
end

"""
    get_coverage_ratio(benefit_amount::Float64, state::String, coverage_type::CoverageType) -> Float64

Get ratio of benefit covered by guaranty fund.

# Arguments
- `benefit_amount`: Total benefit/contract value
- `state`: Two-letter state code
- `coverage_type`: Type of coverage

# Returns
- Coverage ratio (0 to 1)
"""
function get_coverage_ratio(
    benefit_amount::Float64,
    state::String,
    coverage_type::CoverageType
)::Float64
    benefit_amount <= 0 && return 0.0

    covered = calculate_covered_amount(benefit_amount, state, coverage_type)
    covered / benefit_amount
end

#=============================================================================
# State Comparison Functions
=============================================================================#

"""
    compare_state_coverage(state1::String, state2::String, coverage_type::CoverageType) -> NamedTuple

Compare coverage limits between two states.

# Returns
Named tuple with limits and which state offers better coverage.
"""
function compare_state_coverage(
    state1::String,
    state2::String,
    coverage_type::CoverageType
)
    cov1 = get_state_coverage(state1)
    cov2 = get_state_coverage(state2)

    limit1 = get_coverage_limit(state1, coverage_type)
    limit2 = get_coverage_limit(state2, coverage_type)

    # Effective limit considers coverage percentage
    effective1 = limit1 * cov1.coverage_percentage
    effective2 = limit2 * cov2.coverage_percentage

    (
        state1_limit = limit1,
        state1_percentage = cov1.coverage_percentage,
        state1_effective = effective1,
        state2_limit = limit2,
        state2_percentage = cov2.coverage_percentage,
        state2_effective = effective2,
        better_state = effective1 >= effective2 ? state1 : state2
    )
end

"""
    states_with_higher_limits(coverage_type::CoverageType) -> Vector{String}

Get list of states with higher-than-standard limits for a coverage type.
"""
function states_with_higher_limits(coverage_type::CoverageType)::Vector{String}
    standard_limit = get_coverage_limit("DEFAULT", coverage_type)

    higher_states = String[]
    for (state, coverage) in STATE_GUARANTY_LIMITS
        state_limit = get_coverage_limit(state, coverage_type)
        if state_limit > standard_limit
            push!(higher_states, state)
        end
    end

    sort(higher_states)
end

#=============================================================================
# Display Functions
=============================================================================#

"""
    print_state_coverage(state::String; io::IO=stdout)

Print coverage summary for a state.
"""
function print_state_coverage(state::String; io::IO = stdout)
    coverage = get_state_coverage(state)

    println(io, "Guaranty Fund Coverage: $(coverage.state)")
    println(io, "-" ^ 40)
    println(io, "Life Death Benefit:  \$$(Int(coverage.life_death_benefit))")
    println(io, "Life Cash Value:     \$$(Int(coverage.life_cash_value))")
    println(io, "Annuity Deferred:    \$$(Int(coverage.annuity_deferred))")
    println(io, "Annuity Payout:      \$$(Int(coverage.annuity_payout))")
    println(io, "Annuity SSA:         \$$(Int(coverage.annuity_ssa))")
    println(io, "Group Annuity:       \$$(Int(coverage.group_annuity))")
    println(io, "Health:              \$$(Int(coverage.health))")
    println(io, "Coverage %:          $(Int(coverage.coverage_percentage * 100))%")
end

"""
    print_coverage_comparison(states::Vector{String}, coverage_type::CoverageType; io::IO=stdout)

Print comparison of coverage across multiple states.
"""
function print_coverage_comparison(
    states::Vector{String},
    coverage_type::CoverageType;
    io::IO = stdout
)
    println(io, "State Guaranty Coverage Comparison: $coverage_type")
    println(io, "-" ^ 50)
    println(io, rpad("State", 8), rpad("Limit", 15), rpad("Coverage %", 12), "Effective")
    println(io, "-" ^ 50)

    for state in states
        coverage = get_state_coverage(state)
        limit = get_coverage_limit(state, coverage_type)
        effective = limit * coverage.coverage_percentage

        println(io,
            rpad(state, 8),
            rpad("\$$(Int(limit))", 15),
            rpad("$(Int(coverage.coverage_percentage * 100))%", 12),
            "\$$(Int(effective))"
        )
    end
end
