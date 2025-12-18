"""
Yield Curve Functions.

Core yield curve calculations:
- Zero rate interpolation
- Discount factors
- Forward rates
- Nelson-Siegel curve construction
- Par rates and duration

Theory
------
[T1] Nelson-Siegel: y(τ) = β₀ + β₁(1-e^(-τ/λ))/(τ/λ) + β₂((1-e^(-τ/λ))/(τ/λ) - e^(-τ/λ))
[T1] Discount factor: P(t) = e^(-r(t) × t)
[T1] Forward rate: f(t₁,t₂) = (r(t₂)t₂ - r(t₁)t₁)/(t₂ - t₁)

Validators: QuantLib, PyCurve
See: docs/CROSS_VALIDATION_MATRIX.md
"""

# ============================================================================
# Nelson-Siegel Rate Function
# ============================================================================

"""
    nelson_siegel_rate(params, t)

Calculate rate at maturity t using Nelson-Siegel model.

[T1] y(t) = β₀ + β₁(1-e^(-t/τ))/(t/τ) + β₂((1-e^(-t/τ))/(t/τ) - e^(-t/τ))

# Arguments
- `params::NelsonSiegelParams`: Model parameters
- `t::Float64`: Maturity in years

# Returns
- `Float64`: Zero rate at maturity t

# Properties
- Short rate (t→0): β₀ + β₁
- Long rate (t→∞): β₀
- Hump location: approximately τ

# Example
```julia
params = NelsonSiegelParams(beta0=0.04, beta1=-0.02, beta2=0.01, tau=2.0)
nelson_siegel_rate(params, 5.0)  # ~0.039
```
"""
function nelson_siegel_rate(params::NelsonSiegelParams, t::Float64)::Float64
    t <= 0 && return params.beta0 + params.beta1  # Short rate limit

    x = t / params.tau
    exp_term = exp(-x)
    term1 = (1.0 - exp_term) / x
    term2 = term1 - exp_term

    params.beta0 + params.beta1 * term1 + params.beta2 * term2
end

# ============================================================================
# Core Yield Curve Functions
# ============================================================================

"""
    get_rate(curve, t)

Get interpolated zero rate at maturity t.

[T1] Uses configured interpolation method with flat extrapolation.

# Arguments
- `curve::YieldCurve`: Yield curve
- `t::Float64`: Maturity in years

# Returns
- `Float64`: Zero rate (continuous compounding)

# Example
```julia
curve = from_points([1.0, 2.0, 5.0, 10.0], [0.03, 0.035, 0.04, 0.045])
get_rate(curve, 3.0)  # Interpolated rate
```
"""
function get_rate(curve::YieldCurve, t::Float64)::Float64
    t <= 0 && error("Maturity must be positive, got $t")

    # Flat extrapolation at ends
    t <= curve.maturities[1] && return curve.rates[1]
    t >= curve.maturities[end] && return curve.rates[end]

    # Interpolation based on method
    if curve.interpolation == LINEAR
        linear_interp(t, curve.maturities, curve.rates)
    elseif curve.interpolation == LOG_LINEAR
        # Log-linear on discount factors
        log_df = -curve.maturities .* curve.rates
        log_df_t = linear_interp(t, curve.maturities, log_df)
        -log_df_t / t
    else  # CUBIC - fallback to linear for now
        linear_interp(t, curve.maturities, curve.rates)
    end
end

"""
    discount_factor(curve, t)

Calculate discount factor at maturity t.

[T1] P(t) = e^(-r(t) × t)

# Arguments
- `curve::YieldCurve`: Yield curve
- `t::Float64`: Maturity in years

# Returns
- `Float64`: Discount factor ∈ (0, 1]

# Example
```julia
curve = flat_curve(0.04)
discount_factor(curve, 5.0)  # e^(-0.04 * 5) ≈ 0.8187
```
"""
function discount_factor(curve::YieldCurve, t::Float64)::Float64
    t <= 0 && return 1.0
    r = get_rate(curve, t)
    exp(-r * t)
end

"""
    discount_factors(curve, maturities)

Calculate discount factors for multiple maturities.

# Arguments
- `curve::YieldCurve`: Yield curve
- `maturities::Vector{Float64}`: Array of maturities

# Returns
- `Vector{Float64}`: Discount factors
"""
function discount_factors(curve::YieldCurve, maturities::Vector{Float64})::Vector{Float64}
    [discount_factor(curve, t) for t in maturities]
end

"""
    forward_rate(curve, t1, t2)

Calculate forward rate between t1 and t2.

[T1] f(t₁,t₂) = (r(t₂)t₂ - r(t₁)t₁)/(t₂ - t₁)

# Arguments
- `curve::YieldCurve`: Yield curve
- `t1::Float64`: Start maturity
- `t2::Float64`: End maturity

# Returns
- `Float64`: Forward rate (continuously compounded)

# Example
```julia
curve = from_points([1.0, 2.0], [0.03, 0.04])
forward_rate(curve, 1.0, 2.0)  # 1y forward 1y from now = 0.05
```
"""
function forward_rate(curve::YieldCurve, t1::Float64, t2::Float64)::Float64
    t2 <= t1 && error("t2 ($t2) must be greater than t1 ($t1)")

    t1 <= 0 && return get_rate(curve, t2)  # Spot rate to t2

    r1 = get_rate(curve, t1)
    r2 = get_rate(curve, t2)

    (r2 * t2 - r1 * t1) / (t2 - t1)
end

"""
    instantaneous_forward(curve, t)

Calculate instantaneous forward rate at time t.

[T1] f(t) = lim_{Δt→0} f(t, t+Δt) ≈ r(t) + t × dr/dt

# Arguments
- `curve::YieldCurve`: Yield curve
- `t::Float64`: Time in years

# Returns
- `Float64`: Instantaneous forward rate
"""
function instantaneous_forward(curve::YieldCurve, t::Float64)::Float64
    t <= 0 && error("Time must be positive")
    dt = 0.001  # Small increment
    forward_rate(curve, t, t + dt)
end

"""
    par_rate(curve, maturity; frequency=2)

Calculate par rate for given maturity.

[T1] Par rate: coupon rate where bond prices at par.

# Arguments
- `curve::YieldCurve`: Discount curve
- `maturity::Float64`: Bond maturity in years
- `frequency::Int`: Coupon frequency per year (default 2 = semi-annual)

# Returns
- `Float64`: Par rate (annualized)

# Example
```julia
curve = flat_curve(0.04)
par_rate(curve, 10.0)  # ≈ 0.04 for flat curve
```
"""
function par_rate(curve::YieldCurve, maturity::Float64; frequency::Int = 2)::Float64
    maturity <= 0 && error("Maturity must be positive, got $maturity")
    frequency > 0 || error("Frequency must be positive")

    # Payment times
    n_payments = Int(ceil(maturity * frequency))
    dt = 1.0 / frequency
    times = [i * dt for i in 1:n_payments]
    times[end] = maturity  # Ensure exact final time

    # Discount factors
    dfs = discount_factors(curve, times)

    # Par rate: (1 - P(T)) / sum(P(ti)/frequency)
    pv_annuity = sum(dfs) / frequency
    final_df = dfs[end]

    (1.0 - final_df) / pv_annuity
end

# ============================================================================
# Curve Constructors
# ============================================================================

"""
    from_nelson_siegel(beta0, beta1, beta2, tau; as_of_date="", maturities=nothing)

Construct yield curve from Nelson-Siegel parameters.

[T1] y(τ) = β₀ + β₁(1-e^(-τ/λ))/(τ/λ) + β₂((1-e^(-τ/λ))/(τ/λ) - e^(-τ/λ))

# Arguments
- `beta0::Float64`: Long-term level (asymptotic rate)
- `beta1::Float64`: Short-term slope
- `beta2::Float64`: Curvature
- `tau::Float64`: Decay parameter (λ)
- `as_of_date::String`: Curve date
- `maturities::Union{Vector{Float64}, Nothing}`: Maturities to evaluate

# Returns
- `YieldCurve`: Nelson-Siegel curve

# Example
```julia
curve = from_nelson_siegel(0.04, -0.02, 0.01, 2.0)
get_rate(curve, 10.0)  # Long-term rate approaching β₀
```
"""
function from_nelson_siegel(
    beta0::Float64,
    beta1::Float64,
    beta2::Float64,
    tau::Float64;
    as_of_date::String = "",
    maturities::Union{Vector{Float64}, Nothing} = nothing
)::YieldCurve
    tau > 0 || error("Tau must be positive, got $tau")

    params = NelsonSiegelParams(; beta0, beta1, beta2, tau)

    maturities = isnothing(maturities) ?
        [0.25, 0.5, 1.0, 2.0, 3.0, 5.0, 7.0, 10.0, 15.0, 20.0, 30.0] :
        maturities

    rates = [nelson_siegel_rate(params, t) for t in maturities]

    YieldCurve(;
        maturities = maturities,
        rates = rates,
        as_of_date = as_of_date,
        curve_type = "nelson_siegel"
    )
end

"""
    from_points(maturities, rates; as_of_date="", curve_type="custom", interpolation=LINEAR)

Create yield curve from explicit points.

# Arguments
- `maturities::Vector{Float64}`: Maturities in years
- `rates::Vector{Float64}`: Zero rates (continuous compounding)
- `as_of_date::String`: Curve date
- `curve_type::String`: Description of curve
- `interpolation::InterpolationMethod`: Interpolation method

# Returns
- `YieldCurve`: Custom curve

# Example
```julia
curve = from_points([1.0, 5.0, 10.0], [0.03, 0.04, 0.045])
get_rate(curve, 3.0)  # Interpolated
```
"""
function from_points(
    maturities::Vector{Float64},
    rates::Vector{Float64};
    as_of_date::String = "",
    curve_type::String = "custom",
    interpolation::InterpolationMethod = LINEAR
)::YieldCurve
    YieldCurve(;
        maturities = maturities,
        rates = rates,
        as_of_date = as_of_date,
        curve_type = curve_type,
        interpolation = interpolation
    )
end

"""
    flat_curve(rate; as_of_date="")

Create flat yield curve at constant rate.

# Arguments
- `rate::Float64`: Constant rate
- `as_of_date::String`: Curve date

# Returns
- `YieldCurve`: Flat curve

# Example
```julia
curve = flat_curve(0.04)
get_rate(curve, 10.0)  # 0.04
discount_factor(curve, 5.0)  # e^(-0.04 * 5)
```
"""
function flat_curve(rate::Float64; as_of_date::String = "")::YieldCurve
    maturities = [0.25, 1.0, 5.0, 10.0, 30.0]
    rates = fill(rate, length(maturities))

    YieldCurve(;
        maturities = maturities,
        rates = rates,
        as_of_date = as_of_date,
        curve_type = "flat"
    )
end

"""
    upward_sloping_curve(short_rate, long_rate; as_of_date="")

Create upward-sloping curve (normal yield curve).

# Arguments
- `short_rate::Float64`: 1-year rate
- `long_rate::Float64`: 30-year rate
- `as_of_date::String`: Curve date

# Returns
- `YieldCurve`: Upward-sloping curve
"""
function upward_sloping_curve(
    short_rate::Float64,
    long_rate::Float64;
    as_of_date::String = ""
)::YieldCurve
    maturities = [0.25, 0.5, 1.0, 2.0, 3.0, 5.0, 7.0, 10.0, 20.0, 30.0]
    # Log-linear interpolation between short and long
    rates = [
        short_rate + (long_rate - short_rate) * log(1 + t) / log(31)
        for t in maturities
    ]

    YieldCurve(;
        maturities = maturities,
        rates = rates,
        as_of_date = as_of_date,
        curve_type = "upward_sloping"
    )
end

"""
    inverted_curve(short_rate, long_rate; as_of_date="")

Create inverted yield curve.

# Arguments
- `short_rate::Float64`: 1-year rate (higher)
- `long_rate::Float64`: 30-year rate (lower)
- `as_of_date::String`: Curve date

# Returns
- `YieldCurve`: Inverted curve
"""
function inverted_curve(
    short_rate::Float64,
    long_rate::Float64;
    as_of_date::String = ""
)::YieldCurve
    short_rate > long_rate || @warn "Inverted curve expects short_rate > long_rate"
    upward_sloping_curve(short_rate, long_rate; as_of_date)
end

# ============================================================================
# Curve Transformations
# ============================================================================

"""
    shift_curve(curve, shift)

Apply parallel shift to yield curve.

# Arguments
- `curve::YieldCurve`: Original curve
- `shift::Float64`: Rate shift (e.g., 0.01 for +100bps)

# Returns
- `YieldCurve`: Shifted curve

# Example
```julia
curve = flat_curve(0.04)
shocked = shift_curve(curve, 0.01)  # +100bps
get_rate(shocked, 5.0)  # 0.05
```
"""
function shift_curve(curve::YieldCurve, shift::Float64)::YieldCurve
    YieldCurve(;
        maturities = copy(curve.maturities),
        rates = curve.rates .+ shift,
        as_of_date = curve.as_of_date,
        curve_type = "$(curve.curve_type)_shifted",
        interpolation = curve.interpolation
    )
end

"""
    steepen_curve(curve, short_shift, long_shift)

Apply non-parallel shift (steepening/flattening).

# Arguments
- `curve::YieldCurve`: Original curve
- `short_shift::Float64`: Shift at short end
- `long_shift::Float64`: Shift at long end

# Returns
- `YieldCurve`: Transformed curve
"""
function steepen_curve(
    curve::YieldCurve,
    short_shift::Float64,
    long_shift::Float64
)::YieldCurve
    # Linear interpolation of shift across maturities
    min_t = curve.maturities[1]
    max_t = curve.maturities[end]
    shifts = [
        short_shift + (long_shift - short_shift) * (t - min_t) / (max_t - min_t)
        for t in curve.maturities
    ]

    YieldCurve(;
        maturities = copy(curve.maturities),
        rates = curve.rates .+ shifts,
        as_of_date = curve.as_of_date,
        curve_type = "$(curve.curve_type)_steepened",
        interpolation = curve.interpolation
    )
end

"""
    scale_curve(curve, factor)

Scale all rates by a factor.

# Arguments
- `curve::YieldCurve`: Original curve
- `factor::Float64`: Scaling factor (e.g., 1.1 for +10%)

# Returns
- `YieldCurve`: Scaled curve
"""
function scale_curve(curve::YieldCurve, factor::Float64)::YieldCurve
    factor > 0 || error("Factor must be positive")

    YieldCurve(;
        maturities = copy(curve.maturities),
        rates = curve.rates .* factor,
        as_of_date = curve.as_of_date,
        curve_type = "$(curve.curve_type)_scaled",
        interpolation = curve.interpolation
    )
end

# ============================================================================
# Duration and Risk Measures
# ============================================================================

"""
    macaulay_duration(curve, cash_flows, times)

Calculate Macaulay duration.

[T1] D = Σ(t × CF_t × P(t)) / Σ(CF_t × P(t))

# Arguments
- `curve::YieldCurve`: Discount curve
- `cash_flows::Vector{Float64}`: Cash flow amounts
- `times::Vector{Float64}`: Cash flow times

# Returns
- `Float64`: Macaulay duration

# Example
```julia
curve = flat_curve(0.04)
cfs = [5.0, 5.0, 5.0, 5.0, 105.0]  # 5% coupon bond
times = [1.0, 2.0, 3.0, 4.0, 5.0]
macaulay_duration(curve, cfs, times)  # ~4.45 years
```
"""
function macaulay_duration(
    curve::YieldCurve,
    cash_flows::Vector{Float64},
    times::Vector{Float64}
)::Float64
    length(cash_flows) == length(times) || error("Cash flows and times must have same length")

    dfs = discount_factors(curve, times)
    pv_cfs = cash_flows .* dfs
    total_pv = sum(pv_cfs)

    total_pv > 0 || error("Total PV must be positive")

    sum(times .* pv_cfs) / total_pv
end

"""
    modified_duration(curve, cash_flows, times)

Calculate modified duration.

[T1] D_mod = D_mac / (1 + y)

# Arguments
- `curve::YieldCurve`: Discount curve
- `cash_flows::Vector{Float64}`: Cash flow amounts
- `times::Vector{Float64}`: Cash flow times

# Returns
- `Float64`: Modified duration
"""
function modified_duration(
    curve::YieldCurve,
    cash_flows::Vector{Float64},
    times::Vector{Float64}
)::Float64
    d_mac = macaulay_duration(curve, cash_flows, times)
    # Use average rate as yield approximation
    avg_rate = sum(get_rate(curve, t) for t in times) / length(times)
    d_mac / (1 + avg_rate)
end

"""
    dv01(curve, cash_flows, times)

Calculate DV01 (dollar value of 01 = 1 basis point).

[T1] DV01 ≈ PV × D_mod × 0.0001

# Arguments
- `curve::YieldCurve`: Discount curve
- `cash_flows::Vector{Float64}`: Cash flow amounts
- `times::Vector{Float64}`: Cash flow times

# Returns
- `Float64`: DV01 (dollar change per basis point)
"""
function dv01(
    curve::YieldCurve,
    cash_flows::Vector{Float64},
    times::Vector{Float64}
)::Float64
    dfs = discount_factors(curve, times)
    total_pv = sum(cash_flows .* dfs)
    d_mod = modified_duration(curve, cash_flows, times)
    total_pv * d_mod * 0.0001
end

"""
    convexity(curve, cash_flows, times)

Calculate convexity.

[T1] C = Σ(t² × CF_t × P(t)) / (PV × (1+y)²)

# Arguments
- `curve::YieldCurve`: Discount curve
- `cash_flows::Vector{Float64}`: Cash flow amounts
- `times::Vector{Float64}`: Cash flow times

# Returns
- `Float64`: Convexity
"""
function convexity(
    curve::YieldCurve,
    cash_flows::Vector{Float64},
    times::Vector{Float64}
)::Float64
    dfs = discount_factors(curve, times)
    pv_cfs = cash_flows .* dfs
    total_pv = sum(pv_cfs)
    avg_rate = sum(get_rate(curve, t) for t in times) / length(times)

    sum((times .^ 2) .* pv_cfs) / (total_pv * (1 + avg_rate)^2)
end

# ============================================================================
# Present Value Functions
# ============================================================================

"""
    present_value(curve, cash_flows, times)

Calculate present value of cash flows.

# Arguments
- `curve::YieldCurve`: Discount curve
- `cash_flows::Vector{Float64}`: Cash flow amounts
- `times::Vector{Float64}`: Cash flow times

# Returns
- `Float64`: Present value
"""
function present_value(
    curve::YieldCurve,
    cash_flows::Vector{Float64},
    times::Vector{Float64}
)::Float64
    length(cash_flows) == length(times) || error("Cash flows and times must have same length")
    dfs = discount_factors(curve, times)
    sum(cash_flows .* dfs)
end

"""
    annuity_pv(curve, payment, n_periods, frequency)

Calculate PV of level annuity.

# Arguments
- `curve::YieldCurve`: Discount curve
- `payment::Float64`: Payment per period
- `n_periods::Int`: Number of periods
- `frequency::Int`: Periods per year

# Returns
- `Float64`: Present value
"""
function annuity_pv(
    curve::YieldCurve,
    payment::Float64,
    n_periods::Int,
    frequency::Int
)::Float64
    times = [i / frequency for i in 1:n_periods]
    cash_flows = fill(payment, n_periods)
    present_value(curve, cash_flows, times)
end

# ============================================================================
# Validation Utilities
# ============================================================================

"""
    validate_yield_curve(curve)

Validate yield curve for arbitrage-free conditions.

# Arguments
- `curve::YieldCurve`: Curve to validate

# Returns
- `NamedTuple`: Validation results

# Checks
- Positive rates (typically)
- Discount factors decreasing
- Forward rates positive (no arbitrage)
"""
function validate_yield_curve(curve::YieldCurve)
    issues = String[]

    # Check discount factors are decreasing
    dfs = discount_factors(curve, curve.maturities)
    if any(diff(dfs) .> 0)
        push!(issues, "Discount factors not monotonically decreasing")
    end

    # Check forward rates are positive (roughly)
    for i in 1:(length(curve.maturities) - 1)
        t1 = curve.maturities[i]
        t2 = curve.maturities[i + 1]
        fwd = forward_rate(curve, t1, t2)
        if fwd < -0.05  # Allow slightly negative for inverted curves
            push!(issues, "Large negative forward rate between $t1 and $t2: $fwd")
        end
    end

    # Summary
    (
        valid = isempty(issues),
        issues = issues,
        rate_range = (minimum(curve.rates), maximum(curve.rates)),
        df_range = (minimum(dfs), maximum(dfs))
    )
end

"""
    curve_summary(curve)

Generate summary statistics for yield curve.

# Returns
NamedTuple with curve characteristics
"""
function curve_summary(curve::YieldCurve)
    dfs = discount_factors(curve, curve.maturities)

    # Compute key rate points
    short_rate = length(curve.maturities) > 0 ? curve.rates[1] : NaN
    long_rate = length(curve.maturities) > 0 ? curve.rates[end] : NaN
    spread = long_rate - short_rate

    # Slope classification
    slope = if spread > 0.005
        :upward
    elseif spread < -0.005
        :inverted
    else
        :flat
    end

    (
        curve_type = curve.curve_type,
        as_of_date = curve.as_of_date,
        n_points = length(curve.maturities),
        maturity_range = (minimum(curve.maturities), maximum(curve.maturities)),
        rate_range = (minimum(curve.rates), maximum(curve.rates)),
        short_rate = short_rate,
        long_rate = long_rate,
        spread_10y_2y = get_rate(curve, 10.0) - get_rate(curve, 2.0),
        slope = slope
    )
end
