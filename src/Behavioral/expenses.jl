"""
Expense Modeling for Annuity Products.

Models insurance company expenses for GLWB pricing:
- Fixed per-policy expenses (administrative costs)
- Variable AV-based expenses (M&E charges)
- Acquisition costs (commissions, underwriting)
- Inflation adjustment for fixed costs

Theory
------
[T1] Total expense at time t:
    expense(t) = per_policy × (1 + inflation)^t + pct_of_av × AV(t)

[T2] Industry benchmarks (varies by company size):
- Per-policy: \$75-150/year
- M&E: 1.0-2.0% of AV
- Acquisition: 3-8% of premium
"""


# =============================================================================
# Core Expense Calculation
# =============================================================================

"""
    calculate_expense(config::ExpenseConfig, av, year) -> ExpenseResult

Calculate expense for a single period.

[T1] expense = per_policy × (1 + inflation)^year + pct_of_av × AV

# Arguments
- `config::ExpenseConfig`: Expense configuration
- `av::Real`: Current account value
- `year::Int`: Contract year (0-indexed, year 0 = issue)

# Returns
- `ExpenseResult`: Calculated expense with components

# Example
```julia
config = ExpenseConfig(per_policy_annual=100.0, pct_of_av_annual=0.015)
result = calculate_expense(config, 100_000.0, 5)
result.total_expense  # ~100*(1.025)^5 + 0.015*100_000 ≈ 1613
```
"""
function calculate_expense(
    config::ExpenseConfig,
    av::Real,
    year::Int
)
    av >= 0 || throw(ArgumentError("AV cannot be negative, got $av"))
    year >= 0 || throw(ArgumentError("Year cannot be negative, got $year"))

    # Per-policy component with inflation
    inflation_factor = (1 + config.inflation_rate) ^ year
    per_policy_component = config.per_policy_annual * inflation_factor

    # AV-based component (M&E charges)
    av_component = config.pct_of_av_annual * av

    # Total expense
    total_expense = per_policy_component + av_component

    return ExpenseResult(total_expense, per_policy_component, av_component)
end


"""
    calculate_acquisition_expense(config::ExpenseConfig, premium) -> Float64

Calculate one-time acquisition expense at issue.

[T1] acquisition = acquisition_pct × premium

# Arguments
- `config::ExpenseConfig`: Expense configuration
- `premium::Real`: Initial premium amount

# Returns
- `Float64`: Acquisition expense

# Example
```julia
config = ExpenseConfig(acquisition_pct=0.05)
calculate_acquisition_expense(config, 100_000.0)  # 5_000.0
```
"""
function calculate_acquisition_expense(config::ExpenseConfig, premium::Real)
    premium >= 0 || throw(ArgumentError("Premium cannot be negative, got $premium"))
    return config.acquisition_pct * premium
end


# =============================================================================
# Path-Based Calculations
# =============================================================================

"""
    calculate_path_expenses(config::ExpenseConfig, av_path; include_acquisition=true, premium=nothing) -> Vector{ExpenseResult}

Calculate expenses along a simulation path.

# Arguments
- `config::ExpenseConfig`: Expense configuration
- `av_path::Vector{<:Real}`: Path of AV values

# Keyword Arguments
- `include_acquisition::Bool=true`: Include acquisition cost in year 0
- `premium::Union{Real, Nothing}=nothing`: Premium for acquisition (defaults to av_path[1])

# Returns
- `Vector{ExpenseResult}`: Expense results at each time step
"""
function calculate_path_expenses(
    config::ExpenseConfig,
    av_path::Vector{<:Real};
    include_acquisition::Bool = true,
    premium::Union{Real, Nothing} = nothing
)
    n = length(av_path)
    results = Vector{ExpenseResult}(undef, n)

    # Determine premium for acquisition cost
    acq_premium = premium !== nothing ? premium : (n > 0 ? av_path[1] : 0.0)

    for t in 1:n
        year = t - 1  # 0-indexed year
        result = calculate_expense(config, av_path[t], year)

        # Add acquisition cost to year 0
        if t == 1 && include_acquisition
            acq_cost = calculate_acquisition_expense(config, acq_premium)
            result = ExpenseResult(
                result.total_expense + acq_cost,
                result.per_policy_component + acq_cost,  # Include in per-policy for reporting
                result.av_component
            )
        end

        results[t] = result
    end

    return results
end


# =============================================================================
# Expense Metrics
# =============================================================================

"""
    total_expenses(results::Vector{ExpenseResult}) -> Float64

Sum all expenses from a path.
"""
function total_expenses(results::Vector{ExpenseResult})
    return sum(r.total_expense for r in results)
end


"""
    expense_amounts(results::Vector{ExpenseResult}) -> Vector{Float64}

Extract expense amounts from results.
"""
function expense_amounts(results::Vector{ExpenseResult})
    return [r.total_expense for r in results]
end


"""
    pv_expenses(results::Vector{ExpenseResult}, discount_rate::Real; dt::Real=1.0) -> Float64

Calculate present value of expenses.

[T1] PV = Σ expense(t) × e^(-r × t × dt)

# Arguments
- `results::Vector{ExpenseResult}`: Expense results from path
- `discount_rate::Real`: Annual discount rate
- `dt::Real=1.0`: Time step size in years

# Returns
- `Float64`: Present value of all expenses
"""
function pv_expenses(
    results::Vector{ExpenseResult},
    discount_rate::Real;
    dt::Real = 1.0
)
    pv = 0.0
    for (t, result) in enumerate(results)
        time = (t - 1) * dt
        df = exp(-discount_rate * time)
        pv += result.total_expense * df
    end
    return pv
end


"""
    pv_expenses(expenses::Vector{<:Real}, discount_rate::Real; dt::Real=1.0) -> Float64

Calculate present value of expense amounts directly.
"""
function pv_expenses(
    expenses::Vector{<:Real},
    discount_rate::Real;
    dt::Real = 1.0
)
    pv = 0.0
    for (t, expense) in enumerate(expenses)
        time = (t - 1) * dt
        df = exp(-discount_rate * time)
        pv += expense * df
    end
    return pv
end


# =============================================================================
# Expense Ratio Analysis
# =============================================================================

"""
    expense_ratio(config::ExpenseConfig, av::Real, year::Int=0) -> Float64

Calculate expense ratio (expenses as % of AV).

[T1] ratio = total_expense / AV

# Arguments
- `config::ExpenseConfig`: Expense configuration
- `av::Real`: Current account value
- `year::Int=0`: Contract year for inflation adjustment

# Returns
- `Float64`: Expense ratio (decimal, e.g., 0.02 = 2%)
"""
function expense_ratio(config::ExpenseConfig, av::Real, year::Int=0)
    av > 0 || return 0.0
    result = calculate_expense(config, av, year)
    return result.total_expense / av
end


"""
    average_expense_ratio(config::ExpenseConfig, av_path::Vector{<:Real}) -> Float64

Calculate average expense ratio across a path.
"""
function average_expense_ratio(config::ExpenseConfig, av_path::Vector{<:Real})
    isempty(av_path) && return 0.0
    ratios = [expense_ratio(config, av, t-1) for (t, av) in enumerate(av_path)]
    return sum(ratios) / length(ratios)
end


# =============================================================================
# Expense Component Analysis
# =============================================================================

"""
    fixed_vs_variable_split(config::ExpenseConfig, av::Real, year::Int=0) -> NamedTuple

Calculate proportion of expenses that are fixed vs variable.

# Returns
- `NamedTuple{(:fixed_pct, :variable_pct), Tuple{Float64, Float64}}`
"""
function fixed_vs_variable_split(config::ExpenseConfig, av::Real, year::Int=0)
    result = calculate_expense(config, av, year)
    total = result.total_expense

    if total > 0
        fixed_pct = result.per_policy_component / total
        variable_pct = result.av_component / total
    else
        fixed_pct = 0.0
        variable_pct = 0.0
    end

    return (fixed_pct=fixed_pct, variable_pct=variable_pct)
end


# =============================================================================
# Breakeven Analysis
# =============================================================================

"""
    breakeven_av(config::ExpenseConfig, target_ratio::Real, year::Int=0) -> Float64

Calculate AV needed for expense ratio to equal target.

[T1] Solve: per_policy / AV + pct_of_av = target_ratio
     → AV = per_policy / (target_ratio - pct_of_av)

# Arguments
- `config::ExpenseConfig`: Expense configuration
- `target_ratio::Real`: Target expense ratio (e.g., 0.02 for 2%)
- `year::Int=0`: Contract year for inflation adjustment

# Returns
- `Float64`: Required AV (Inf if not achievable)

# Example
```julia
config = ExpenseConfig(per_policy_annual=100.0, pct_of_av_annual=0.015)
breakeven_av(config, 0.02)  # AV needed for 2% expense ratio
```
"""
function breakeven_av(config::ExpenseConfig, target_ratio::Real, year::Int=0)
    # per_policy * inflation^year / AV + pct_of_av = target
    # → AV = per_policy * inflation^year / (target - pct_of_av)

    denominator = target_ratio - config.pct_of_av_annual

    if denominator <= 0
        return Inf  # Cannot achieve target ratio
    end

    inflation_factor = (1 + config.inflation_rate) ^ year
    per_policy_adjusted = config.per_policy_annual * inflation_factor

    return per_policy_adjusted / denominator
end


# =============================================================================
# Projection Functions
# =============================================================================

"""
    project_expenses(config::ExpenseConfig, initial_av::Real, growth_rate::Real, n_years::Int) -> Vector{ExpenseResult}

Project expenses assuming constant AV growth rate.

# Arguments
- `config::ExpenseConfig`: Expense configuration
- `initial_av::Real`: Starting AV
- `growth_rate::Real`: Annual AV growth rate (decimal)
- `n_years::Int`: Number of years to project

# Returns
- `Vector{ExpenseResult}`: Projected expenses
"""
function project_expenses(
    config::ExpenseConfig,
    initial_av::Real,
    growth_rate::Real,
    n_years::Int
)
    n_years > 0 || throw(ArgumentError("n_years must be positive, got $n_years"))

    av_path = [initial_av * (1 + growth_rate)^(t-1) for t in 1:n_years]
    return calculate_path_expenses(config, av_path; include_acquisition=true, premium=initial_av)
end


"""
    expense_sensitivity(config::ExpenseConfig, av::Real; inflation_range=0.0:0.01:0.05) -> Dict{Float64, Float64}

Calculate expense sensitivity to inflation rate.

# Arguments
- `config::ExpenseConfig`: Base expense configuration
- `av::Real`: Account value for calculation
- `inflation_range::AbstractRange`: Inflation rates to evaluate

# Returns
- `Dict{Float64, Float64}`: Mapping of inflation rate to 10-year PV of expenses
"""
function expense_sensitivity(
    config::ExpenseConfig,
    av::Real;
    inflation_range::AbstractRange = 0.0:0.01:0.05
)
    results = Dict{Float64, Float64}()

    for inflation in inflation_range
        # Create modified config
        modified_config = ExpenseConfig(
            per_policy_annual=config.per_policy_annual,
            pct_of_av_annual=config.pct_of_av_annual,
            acquisition_pct=config.acquisition_pct,
            inflation_rate=inflation
        )

        # Project 10 years with flat AV
        av_path = fill(av, 10)
        expenses = calculate_path_expenses(modified_config, av_path; include_acquisition=false)
        pv = pv_expenses(expenses, 0.05)  # 5% discount rate

        results[inflation] = pv
    end

    return results
end
