"""
Mortality Table Functions.

Core actuarial mortality calculations:
- qx lookup and validation
- Survival probabilities (px, npx)
- Life expectancy (curtate and complete)
- Annuity factors
- Table transformations (improvement, blending)

Theory
------
[T1] qx = probability of death between age x and x+1
[T1] px = 1 - qx = probability of survival
[T1] npx = p_x × p_{x+1} × ... × p_{x+n-1} = n-year survival
[T1] e_x = Σ(kpx) for k=1 to omega-x = curtate life expectancy

Validators: actuarialmath, MortalityTables.jl
See: docs/CROSS_VALIDATION_MATRIX.md
"""

# ============================================================================
# Core Mortality Functions
# ============================================================================

"""
    get_qx(table, age)

Get mortality rate at age.

[T1] qx = probability of death between age x and x+1

# Arguments
- `table::MortalityTable`: Mortality table
- `age::Int`: Age to look up

# Returns
- `Float64`: Mortality rate qx

# Example
```julia
table = soa_2012_iam()
get_qx(table, 65)  # 0.0168
```
"""
function get_qx(table::MortalityTable, age::Int)::Float64
    age < table.min_age && error("Age $age below minimum age $(table.min_age)")
    age > table.max_age && return 1.0  # Certain death beyond omega

    idx = age - table.min_age + 1  # Julia 1-indexed
    table.qx[idx]
end

"""
    get_px(table, age)

Get survival rate at age.

[T1] px = 1 - qx

# Arguments
- `table::MortalityTable`: Mortality table
- `age::Int`: Age to look up

# Returns
- `Float64`: Survival rate px

# Example
```julia
table = soa_2012_iam()
get_px(table, 65)  # 0.9832
```
"""
function get_px(table::MortalityTable, age::Int)::Float64
    1.0 - get_qx(table, age)
end

"""
    npx(table, age, n)

Get n-year survival probability from age.

[T1] npx = p_x × p_{x+1} × ... × p_{x+n-1}

# Arguments
- `table::MortalityTable`: Mortality table
- `age::Int`: Starting age
- `n::Int`: Number of years

# Returns
- `Float64`: n-year survival probability

# Example
```julia
table = soa_2012_iam()
npx(table, 65, 10)  # ~0.82, 10-year survival from age 65
```
"""
function npx(table::MortalityTable, age::Int, n::Int)::Float64
    n <= 0 && return 1.0

    survival = 1.0
    for k in 0:(n-1)
        survival *= get_px(table, age + k)
        survival <= 0 && break
    end

    survival
end

"""
    nqx(table, age, n)

Get n-year death probability from age.

[T1] nqx = 1 - npx

# Arguments
- `table::MortalityTable`: Mortality table
- `age::Int`: Starting age
- `n::Int`: Number of years

# Returns
- `Float64`: n-year death probability
"""
function nqx(table::MortalityTable, age::Int, n::Int)::Float64
    1.0 - npx(table, age, n)
end

# ============================================================================
# Life Expectancy
# ============================================================================

"""
    life_expectancy(table, age)

Calculate curtate life expectancy at age.

[T1] e_x = Σ(kpx) for k=1 to omega-x

# Arguments
- `table::MortalityTable`: Mortality table
- `age::Int`: Starting age

# Returns
- `Float64`: Curtate life expectancy (complete years)

# Example
```julia
table = soa_2012_iam()
life_expectancy(table, 65)  # ~20.1
```
"""
function life_expectancy(table::MortalityTable, age::Int)::Float64
    age > table.max_age && return 0.0

    ex = 0.0
    for k in 1:(table.max_age - age + 1)
        kpx = npx(table, age, k)
        ex += kpx
        kpx < 1e-10 && break
    end

    ex
end

"""
    complete_life_expectancy(table, age)

Calculate complete life expectancy.

[T1] e°_x ≈ e_x + 0.5 (uniform distribution of deaths assumption)

# Arguments
- `table::MortalityTable`: Mortality table
- `age::Int`: Starting age

# Returns
- `Float64`: Complete life expectancy
"""
function complete_life_expectancy(table::MortalityTable, age::Int)::Float64
    life_expectancy(table, age) + 0.5
end

# ============================================================================
# Life Table Functions
# ============================================================================

"""
    lx(table, age; radix=100_000)

Calculate lx (number living at age x).

[T1] lx = radix × 0px

# Arguments
- `table::MortalityTable`: Mortality table
- `age::Int`: Age
- `radix::Int`: Starting population (default 100,000)

# Returns
- `Float64`: Number surviving to age x
"""
function lx(table::MortalityTable, age::Int; radix::Int = 100_000)::Float64
    age <= table.min_age && return Float64(radix)
    radix * npx(table, table.min_age, age - table.min_age)
end

"""
    dx(table, age; radix=100_000)

Calculate dx (deaths between age x and x+1).

[T1] dx = lx × qx

# Arguments
- `table::MortalityTable`: Mortality table
- `age::Int`: Age
- `radix::Int`: Starting population

# Returns
- `Float64`: Expected deaths at age x
"""
function dx(table::MortalityTable, age::Int; radix::Int = 100_000)::Float64
    lx(table, age; radix) * get_qx(table, age)
end

# ============================================================================
# Annuity Functions
# ============================================================================

"""
    annuity_factor(table, age, r; n=nothing)

Calculate present value factor of life annuity due.

[T1] ä_x = Σ v^k × kpx for k=0 to n-1

# Arguments
- `table::MortalityTable`: Mortality table
- `age::Int`: Starting age
- `r::Float64`: Interest rate
- `n::Union{Int, Nothing}`: Term in years (nothing = life)

# Returns
- `Float64`: Annuity present value factor

# Example
```julia
table = soa_2012_iam()
annuity_factor(table, 65, 0.04)  # Life annuity, ~13.5
annuity_factor(table, 65, 0.04; n=10)  # 10-year temporary
```
"""
function annuity_factor(
    table::MortalityTable,
    age::Int,
    r::Float64;
    n::Union{Int, Nothing} = nothing
)::Float64
    v = 1.0 / (1.0 + r)
    max_term = isnothing(n) ? (table.max_age - age + 1) : min(n, table.max_age - age + 1)

    annuity = 0.0
    for k in 0:(max_term - 1)
        kpx = npx(table, age, k)
        annuity += (v ^ k) * kpx
        kpx < 1e-10 && break
    end

    annuity
end

"""
    annuity_immediate_factor(table, age, r; n=nothing)

Calculate present value factor of life annuity immediate.

[T1] a_x = ä_x - 1 (payments at end of period)

# Arguments
- `table::MortalityTable`: Mortality table
- `age::Int`: Starting age
- `r::Float64`: Interest rate
- `n::Union{Int, Nothing}`: Term in years (nothing = life)

# Returns
- `Float64`: Annuity immediate present value factor
"""
function annuity_immediate_factor(
    table::MortalityTable,
    age::Int,
    r::Float64;
    n::Union{Int, Nothing} = nothing
)::Float64
    annuity_factor(table, age, r; n) - 1.0
end

# ============================================================================
# Table Loaders
# ============================================================================

"""
    soa_2012_iam(; gender=MALE)

Load SOA 2012 IAM basic mortality table.

[T1] Standard annuitant mortality table from Society of Actuaries.
Table IDs: 3302 (Male), 3303 (Female)

# Arguments
- `gender::Gender`: MALE or FEMALE (default MALE)

# Returns
- `MortalityTable`: SOA 2012 IAM table

# Example
```julia
table = soa_2012_iam()
table = soa_2012_iam(gender=FEMALE)
```
"""
function soa_2012_iam(; gender::Gender = MALE)::MortalityTable
    qx = get_soa_2012_iam_qx_vector(gender)
    age_range = get_soa_2012_iam_age_range()

    MortalityTable(;
        table_name = gender == MALE ? "SOA 2012 IAM Basic - Male" : "SOA 2012 IAM Basic - Female",
        min_age = age_range.min_age,
        max_age = age_range.max_age,
        qx = qx,
        gender = gender
    )
end

"""
    soa_table(table_id)

Load SOA table by ID.

# Arguments
- `table_id::Int`: SOA table ID

# Returns
- `MortalityTable`: Requested table

# Supported Tables
- 3302: SOA 2012 IAM Basic - Male
- 3303: SOA 2012 IAM Basic - Female
"""
function soa_table(table_id::Int)::MortalityTable
    if table_id == 3302
        soa_2012_iam(gender = MALE)
    elseif table_id == 3303
        soa_2012_iam(gender = FEMALE)
    else
        error("SOA table $table_id not built-in. Use MortalityTables.jl for full access.")
    end
end

# ============================================================================
# Table Constructors
# ============================================================================

"""
    gompertz_table(; a=0.0001, b=0.08, min_age=0, max_age=120, gender=UNISEX)

Create Gompertz mortality table.

[T1] qx = a × e^(b × age), capped at 1.0

# Arguments
- `a::Float64`: Base mortality parameter
- `b::Float64`: Aging parameter
- `min_age::Int`: Minimum age
- `max_age::Int`: Maximum age
- `gender::Gender`: Gender specification

# Returns
- `MortalityTable`: Gompertz mortality table

# Example
```julia
table = gompertz_table(a=0.0001, b=0.08)
get_qx(table, 65)  # ~0.019
```
"""
function gompertz_table(;
    a::Float64 = 0.0001,
    b::Float64 = 0.08,
    min_age::Int = 0,
    max_age::Int = 120,
    gender::Gender = UNISEX
)::MortalityTable
    a > 0 || error("Parameter a must be positive")
    b > 0 || error("Parameter b must be positive")

    ages = min_age:max_age
    qx = [min(a * exp(b * age), 1.0) for age in ages]

    MortalityTable(;
        table_name = "Gompertz (a=$a, b=$b)",
        min_age = min_age,
        max_age = max_age,
        qx = qx,
        gender = gender
    )
end

"""
    from_dict(qx_dict; table_name="Custom", gender=UNISEX)

Create mortality table from dictionary.

# Arguments
- `qx_dict::Dict{Int, Float64}`: Age -> qx mapping
- `table_name::String`: Table name
- `gender::Gender`: Gender specification

# Returns
- `MortalityTable`: Custom mortality table

# Example
```julia
qx = Dict(65 => 0.02, 66 => 0.022, 67 => 0.024)
table = from_dict(qx; table_name="Custom")
```
"""
function from_dict(
    qx_dict::Dict{Int, Float64};
    table_name::String = "Custom",
    gender::Gender = UNISEX
)::MortalityTable
    isempty(qx_dict) && error("qx_dict cannot be empty")

    ages = sort(collect(keys(qx_dict)))
    min_age = first(ages)
    max_age = last(ages)

    # Fill gaps with linear interpolation
    qx = Vector{Float64}(undef, max_age - min_age + 1)
    for (i, age) in enumerate(min_age:max_age)
        if haskey(qx_dict, age)
            qx[i] = qx_dict[age]
        else
            # Linear interpolation
            lower = maximum(a for a in ages if a < age)
            upper = minimum(a for a in ages if a > age)
            frac = (age - lower) / (upper - lower)
            qx[i] = qx_dict[lower] + frac * (qx_dict[upper] - qx_dict[lower])
        end
    end

    MortalityTable(;
        table_name = table_name,
        min_age = min_age,
        max_age = max_age,
        qx = qx,
        gender = gender
    )
end

# ============================================================================
# Table Transformations
# ============================================================================

"""
    with_improvement(table, improvement_rate, projection_years)

Apply mortality improvement factors to table.

[T1] qx_improved = qx × (1 - improvement_rate)^years

# Arguments
- `table::MortalityTable`: Base mortality table
- `improvement_rate::Float64`: Annual improvement rate (e.g., 0.01 for 1%)
- `projection_years::Int`: Years of improvement to apply

# Returns
- `MortalityTable`: Improved mortality table

# Example
```julia
base = soa_2012_iam()
improved = with_improvement(base, 0.01, 10)  # 1% annual improvement for 10 years
get_qx(improved, 65) < get_qx(base, 65)  # true
```
"""
function with_improvement(
    table::MortalityTable,
    improvement_rate::Float64,
    projection_years::Int
)::MortalityTable
    projection_years <= 0 && return table
    0.0 <= improvement_rate <= 1.0 || error("Improvement rate must be in [0, 1]")

    factor = (1.0 - improvement_rate) ^ projection_years
    improved_qx = min.(table.qx .* factor, 1.0)

    MortalityTable(;
        table_name = "$(table.table_name) + $(projection_years)yr improvement",
        min_age = table.min_age,
        max_age = table.max_age,
        qx = improved_qx,
        gender = table.gender
    )
end

"""
    blend_tables(table1, table2, weight1)

Blend two mortality tables.

[T1] qx_blend = w × qx1 + (1-w) × qx2

# Arguments
- `table1::MortalityTable`: First table
- `table2::MortalityTable`: Second table
- `weight1::Float64`: Weight for table1 (0 to 1)

# Returns
- `MortalityTable`: Blended table

# Example
```julia
male = soa_2012_iam(gender=MALE)
female = soa_2012_iam(gender=FEMALE)
unisex = blend_tables(male, female, 0.5)
```
"""
function blend_tables(
    table1::MortalityTable,
    table2::MortalityTable,
    weight1::Float64
)::MortalityTable
    table1.min_age == table2.min_age && table1.max_age == table2.max_age ||
        error("Tables must have same age range")
    0.0 <= weight1 <= 1.0 || error("Weight must be in [0, 1]")

    weight2 = 1.0 - weight1
    blended_qx = weight1 .* table1.qx .+ weight2 .* table2.qx

    w1_pct = round(Int, weight1 * 100)
    w2_pct = 100 - w1_pct

    MortalityTable(;
        table_name = "Blend: $w1_pct% $(table1.table_name) / $w2_pct% $(table2.table_name)",
        min_age = table1.min_age,
        max_age = table1.max_age,
        qx = blended_qx,
        gender = UNISEX
    )
end

# ============================================================================
# Comparison and Analysis
# ============================================================================

"""
    compare_life_expectancy(tables; ages=nothing)

Compare life expectancy across tables.

# Arguments
- `tables::Dict{String, MortalityTable}`: Named tables to compare
- `ages::Union{Vector{Int}, Nothing}`: Ages to evaluate (default: [55, 60, 65, 70, 75, 80])

# Returns
- `Dict{String, Dict{Int, Float64}}`: Life expectancy by table and age

# Example
```julia
tables = Dict(
    "Male" => soa_2012_iam(gender=MALE),
    "Female" => soa_2012_iam(gender=FEMALE)
)
results = compare_life_expectancy(tables)
results["Male"][65]  # ~20.1
```
"""
function compare_life_expectancy(
    tables::Dict{String, MortalityTable};
    ages::Union{Vector{Int}, Nothing} = nothing
)::Dict{String, Dict{Int, Float64}}
    ages = isnothing(ages) ? [55, 60, 65, 70, 75, 80] : ages

    results = Dict{String, Dict{Int, Float64}}()
    for (name, table) in tables
        results[name] = Dict{Int, Float64}()
        for age in ages
            results[name][age] = life_expectancy(table, age)
        end
    end

    results
end

"""
    calculate_annuity_pv(table, age, annual_payment, discount_rate; term=nothing, timing=:beginning)

Calculate present value of life annuity.

[T1] PV = payment × ä_x (due) or payment × a_x (immediate)

# Arguments
- `table::MortalityTable`: Mortality table
- `age::Int`: Annuitant age
- `annual_payment::Float64`: Annual payment amount
- `discount_rate::Float64`: Interest rate
- `term::Union{Int, Nothing}`: Term in years (nothing = life)
- `timing::Symbol`: :beginning (annuity due) or :end (immediate)

# Returns
- `Float64`: Present value

# Example
```julia
table = soa_2012_iam()
pv = calculate_annuity_pv(table, 65, 10_000.0, 0.04)  # ~135,000
```
"""
function calculate_annuity_pv(
    table::MortalityTable,
    age::Int,
    annual_payment::Float64,
    discount_rate::Float64;
    term::Union{Int, Nothing} = nothing,
    timing::Symbol = :beginning
)::Float64
    timing in (:beginning, :end) || error("Timing must be :beginning or :end")

    factor = annuity_factor(table, age, discount_rate; n = term)

    if timing == :end
        factor = annuity_immediate_factor(table, age, discount_rate; n = term)
    end

    annual_payment * factor
end

# ============================================================================
# Validation Utilities
# ============================================================================

"""
    validate_mortality_table(table)

Validate mortality table integrity.

# Arguments
- `table::MortalityTable`: Table to validate

# Returns
- `NamedTuple`: Validation results

# Checks
- qx bounds: 0 ≤ qx ≤ 1
- Monotonicity: qx generally increasing with age
- Terminal: qx(omega) = 1 or approaching 1
"""
function validate_mortality_table(table::MortalityTable)
    issues = String[]

    # Check bounds
    if any(q -> q < 0.0 || q > 1.0, table.qx)
        push!(issues, "qx values outside [0, 1]")
    end

    # Check terminal age
    if table.qx[end] < 0.99
        push!(issues, "Terminal qx not approaching 1.0")
    end

    # Check monotonicity after age 30 (roughly)
    idx_30 = max(1, 30 - table.min_age + 1)
    if idx_30 < length(table.qx)
        later_qx = table.qx[idx_30:end]
        non_monotonic = sum(diff(later_qx) .< -0.01)  # Allow small decreases
        if non_monotonic > 3
            push!(issues, "Non-monotonic qx after age 30 ($non_monotonic decreases)")
        end
    end

    # Summary
    (
        valid = isempty(issues),
        issues = issues,
        qx_range = (minimum(table.qx), maximum(table.qx)),
        life_exp_65 = life_expectancy(table, 65)
    )
end
