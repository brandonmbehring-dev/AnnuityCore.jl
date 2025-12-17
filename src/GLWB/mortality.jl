"""
GLWB Mortality Functions.

[T1] Mortality decrements are essential for GLWB pricing as death terminates
the liability. We use a simplified approximation of SOA 2012 IAM (Individual
Annuity Mortality) tables.

Note: For production use, consider loading actual SOA tables via
MortalityTables.jl or similar packages.
"""


"""
    default_mortality(age; gender=:male) -> Float64

Default mortality function using Gompertz-Makeham approximation.

[T2] Approximation calibrated to SOA 2012 IAM Basic table.
Returns annual probability of death qx.

# Arguments
- `age::Int`: Current age
- `gender::Symbol=:male`: Gender (:male or :female)

# Returns
- `Float64`: Annual death probability qx

# Example
```julia
qx_65 = default_mortality(65)        # ~0.0091 for male
qx_80 = default_mortality(80)        # ~0.0446 for male
```
"""
function default_mortality(age::Int; gender::Symbol = :male)
    # Gompertz-Makeham: qx = A + B * exp(C * (age - x0))
    # Calibrated to approximate SOA 2012 IAM Basic

    if gender == :male
        # Male mortality (higher than female)
        A = 0.00005  # Accident component
        B = 0.00003
        C = 0.095
        x0 = 25
    else
        # Female mortality (lower than male)
        A = 0.00004
        B = 0.000025
        C = 0.090
        x0 = 25
    end

    qx = A + B * exp(C * (age - x0))
    return min(qx, 1.0)  # Cap at 1.0
end


"""
    soa_2012_iam_qx(age; gender=:male) -> Float64

SOA 2012 IAM mortality approximation.

Alias for `default_mortality` for clarity.
"""
const soa_2012_iam_qx = default_mortality


"""
    constant_mortality(qx_annual) -> Function

Create a constant mortality function (for testing).

# Arguments
- `qx_annual::Float64`: Constant annual death probability

# Returns
- `Function`: Mortality function that returns constant qx

# Example
```julia
mort = constant_mortality(0.01)  # 1% annual death rate
sim = GLWBSimulator(mortality=mort, ...)
```
"""
function constant_mortality(qx_annual::Float64)
    return (age::Int) -> qx_annual
end


"""
    zero_mortality() -> Function

Create a zero mortality function (immortal, for testing).

Useful for isolating market risk from mortality risk.
"""
function zero_mortality()
    return (age::Int) -> 0.0
end


"""
    convert_annual_to_step(qx_annual, dt) -> Float64

Convert annual mortality to per-step mortality.

[T1] Formula: qx_step = 1 - (1 - qx_annual)^dt

# Arguments
- `qx_annual::Float64`: Annual death probability
- `dt::Float64`: Timestep size in years

# Returns
- `Float64`: Death probability per timestep
"""
function convert_annual_to_step(qx_annual::Float64, dt::Float64)
    return 1.0 - (1.0 - qx_annual)^dt
end


"""
    life_expectancy(age, mortality; max_age=120) -> Float64

Calculate curtate life expectancy from mortality table.

[T1] e_x = Σ (k=1 to ∞) k_p_x where k_p_x = Π(j=0 to k-1) (1 - q_{x+j})

# Arguments
- `age::Int`: Starting age
- `mortality::Function`: Mortality function qx(age)
- `max_age::Int=120`: Maximum age for calculation

# Returns
- `Float64`: Expected remaining lifetime (years)
"""
function life_expectancy(age::Int, mortality::Function; max_age::Int = 120)
    ex = 0.0
    px_cum = 1.0  # Cumulative survival

    for k in 1:(max_age - age)
        qx = mortality(age + k - 1)
        px_cum *= (1.0 - qx)
        ex += px_cum
    end

    return ex
end


"""
    survival_probability(age, years, mortality) -> Float64

Calculate probability of surviving `years` from `age`.

[T1] n_p_x = Π(k=0 to n-1) (1 - q_{x+k})

# Arguments
- `age::Int`: Starting age
- `years::Int`: Number of years
- `mortality::Function`: Mortality function

# Returns
- `Float64`: Probability of surviving `years` years
"""
function survival_probability(age::Int, years::Int, mortality::Function)
    px = 1.0
    for k in 0:(years-1)
        qx = mortality(age + k)
        px *= (1.0 - qx)
    end
    return px
end
