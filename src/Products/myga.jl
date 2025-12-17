"""
MYGA (Multi-Year Guaranteed Annuity) Pricer.

MYGA is the simplest annuity product:
- Fixed rate locked for entire term
- Principal 100% protected
- Deterministic cash flows (no optionality)

[T1] Value = PV of guaranteed maturity value
"""


"""
    price_myga(product, principal; discount_rate) -> PricingResult

Price MYGA product (deterministic cash flow).

[T1] Formulas:
- Maturity Value: FV = Principal × (1 + rate)^years
- Present Value: PV = FV / (1 + discount)^years
- Duration (Macaulay): D = years (for zero-coupon)
- Modified Duration: D_mod = D / (1 + discount)
- Convexity: C = years × (years + 1) / (1 + discount)^2

# Arguments
- `product::MYGAProduct`: MYGA product specification
- `principal::Real=100_000`: Initial premium amount
- `discount_rate::Union{Real, Nothing}=nothing`: Discount rate. If nothing, uses product rate.

# Returns
- `PricingResult`: Contains present_value, duration, convexity, and details

# Example
```julia
product = MYGAProduct(fixed_rate=0.045, guarantee_duration=5)
result = price_myga(product, 100_000.0)
# result.present_value ≈ 100_000 (when discount = product rate)
# result.duration = 5.0
```
"""
function price_myga(
    product::MYGAProduct{T},
    principal::Real = T(100_000);
    discount_rate::Union{Real, Nothing} = nothing
) where T<:Real
    rate = product.fixed_rate
    years = product.guarantee_duration
    disc = discount_rate === nothing ? rate : T(discount_rate)
    principal_t = T(principal)

    # Validation
    disc >= -1 || throw(ArgumentError("discount_rate must be > -1"))

    # [T1] Maturity value: FV = Principal × (1 + rate)^years
    maturity_value = principal_t * (1 + rate)^years

    # [T1] Present value: PV = FV / (1 + discount)^years
    present_value = maturity_value / (1 + disc)^years

    # [T1] Duration (Macaulay) for zero-coupon = time to maturity
    duration = T(years)

    # [T1] Modified duration: D_mod = D / (1 + discount)
    modified_duration = duration / (1 + disc)

    # [T1] Convexity for zero-coupon: C = T × (T + 1) / (1 + discount)^2
    convexity = T(years * (years + 1)) / (1 + disc)^2

    # Build details dictionary
    details = Dict{Symbol, Any}(
        :principal => principal_t,
        :fixed_rate => rate,
        :guarantee_duration => years,
        :discount_rate => disc,
        :maturity_value => maturity_value,
        :modified_duration => modified_duration,
        :effective_yield => rate,
    )

    PricingResult(present_value, duration, convexity, details)
end


"""
    myga_sensitivity(product, principal, discount_rate; bump_size) -> NamedTuple

Calculate interest rate sensitivity for MYGA.

Returns DV01 (dollar value of 1 basis point move) and convexity effect.

# Arguments
- `product::MYGAProduct`: MYGA product specification
- `principal::Real`: Initial premium amount
- `discount_rate::Real`: Current discount rate
- `bump_size::Real=0.0001`: Rate bump size (default: 1 basis point)

# Returns
- `NamedTuple`: (dv01, convexity_effect, duration, modified_duration)
"""
function myga_sensitivity(
    product::MYGAProduct{T},
    principal::Real,
    discount_rate::Real;
    bump_size::Real = 0.0001
) where T<:Real
    base = price_myga(product, principal; discount_rate=discount_rate)

    # Bump up
    up = price_myga(product, principal; discount_rate=discount_rate + bump_size)

    # Bump down
    down = price_myga(product, principal; discount_rate=discount_rate - bump_size)

    # DV01: change in value per 1bp
    dv01 = (down.present_value - up.present_value) / 2

    # Convexity effect
    convexity_effect = (up.present_value + down.present_value - 2 * base.present_value) / bump_size^2

    (
        dv01 = dv01,
        convexity_effect = convexity_effect,
        duration = base.duration,
        modified_duration = base.details[:modified_duration]
    )
end


"""
    myga_breakeven_rate(product, principal, target_pv) -> Float64

Find the discount rate that produces target present value.

Uses bisection search to solve for the breakeven rate.

# Arguments
- `product::MYGAProduct`: MYGA product specification
- `principal::Real`: Initial premium amount
- `target_pv::Real`: Target present value to achieve

# Returns
- `Float64`: Discount rate that produces target PV
"""
function myga_breakeven_rate(
    product::MYGAProduct{T},
    principal::Real,
    target_pv::Real;
    tol::Real = 1e-10,
    max_iter::Int = 100
) where T<:Real
    # Bounds for bisection
    low = -0.5
    high = 1.0

    for _ in 1:max_iter
        mid = (low + high) / 2
        result = price_myga(product, principal; discount_rate=mid)

        if abs(result.present_value - target_pv) < tol
            return mid
        elseif result.present_value > target_pv
            low = mid  # Need higher rate to decrease PV
        else
            high = mid  # Need lower rate to increase PV
        end
    end

    return (low + high) / 2
end


"""
    myga_total_return(product) -> Float64

Calculate total return at maturity.

[T1] Total Return = (1 + rate)^years - 1

# Example
```julia
product = MYGAProduct(fixed_rate=0.045, guarantee_duration=5)
myga_total_return(product)  # ≈ 0.2462 (24.62%)
```
"""
function myga_total_return(product::MYGAProduct{T}) where T<:Real
    (1 + product.fixed_rate)^product.guarantee_duration - 1
end
