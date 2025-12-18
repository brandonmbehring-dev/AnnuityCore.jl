"""
Interpolation Utilities.

Shared interpolation functions for mortality and yield curve calculations:
- Linear interpolation
- Log-linear interpolation
- Cubic spline (placeholder)

These utilities support both mortality table and yield curve operations.
"""

# ============================================================================
# Linear Interpolation
# ============================================================================

"""
    linear_interp(x, xs, ys)

Linear interpolation at point x given vectors xs and ys.

# Arguments
- `x::Float64`: Point to interpolate at
- `xs::Vector{Float64}`: X coordinates (must be sorted ascending)
- `ys::Vector{Float64}`: Y values at each x

# Returns
- `Float64`: Interpolated y value

# Note
Uses flat extrapolation at boundaries.

# Example
```julia
xs = [1.0, 2.0, 3.0]
ys = [10.0, 20.0, 30.0]
linear_interp(1.5, xs, ys)  # 15.0
```
"""
function linear_interp(x::Float64, xs::Vector{Float64}, ys::Vector{Float64})::Float64
    length(xs) == length(ys) || error("xs and ys must have same length")
    length(xs) > 0 || error("xs must have at least one element")

    # Boundary cases
    x <= xs[1] && return ys[1]
    x >= xs[end] && return ys[end]

    # Find bracketing indices
    idx = searchsortedfirst(xs, x)
    idx_low = max(1, idx - 1)
    idx_high = min(length(xs), idx)

    # Handle exact match
    xs[idx_low] == x && return ys[idx_low]
    xs[idx_high] == x && return ys[idx_high]

    # Linear interpolation
    x1, x2 = xs[idx_low], xs[idx_high]
    y1, y2 = ys[idx_low], ys[idx_high]

    frac = (x - x1) / (x2 - x1)
    y1 + frac * (y2 - y1)
end

"""
    linear_interp(x, xs::AbstractVector, ys::AbstractVector)

Generic version accepting any AbstractVector.
"""
function linear_interp(x::Float64, xs::AbstractVector, ys::AbstractVector)::Float64
    linear_interp(x, collect(Float64, xs), collect(Float64, ys))
end

# ============================================================================
# Log-Linear Interpolation
# ============================================================================

"""
    log_linear_interp(x, xs, ys)

Log-linear interpolation at point x.

Interpolates log(y) linearly, then exponentiates.
Useful for discount factors to maintain no-arbitrage.

# Arguments
- `x::Float64`: Point to interpolate at
- `xs::Vector{Float64}`: X coordinates
- `ys::Vector{Float64}`: Y values (must be positive)

# Returns
- `Float64`: Interpolated y value

# Example
```julia
xs = [1.0, 2.0]
ys = [0.95, 0.90]  # Discount factors
log_linear_interp(1.5, xs, ys)  # ≈ 0.924
```
"""
function log_linear_interp(x::Float64, xs::Vector{Float64}, ys::Vector{Float64})::Float64
    all(y -> y > 0, ys) || error("All y values must be positive for log-linear interpolation")

    log_ys = log.(ys)
    log_y = linear_interp(x, xs, log_ys)
    exp(log_y)
end

# ============================================================================
# Cubic Spline (Simplified)
# ============================================================================

"""
    cubic_interp(x, xs, ys)

Cubic spline interpolation (simplified implementation).

This is a basic natural cubic spline. For production use,
consider using Interpolations.jl for more robust implementation.

# Arguments
- `x::Float64`: Point to interpolate at
- `xs::Vector{Float64}`: X coordinates
- `ys::Vector{Float64}`: Y values

# Returns
- `Float64`: Interpolated y value

# Note
Falls back to linear interpolation for small datasets (n < 4).
"""
function cubic_interp(x::Float64, xs::Vector{Float64}, ys::Vector{Float64})::Float64
    n = length(xs)

    # For small datasets, use linear
    n < 4 && return linear_interp(x, xs, ys)

    # Boundary cases
    x <= xs[1] && return ys[1]
    x >= xs[end] && return ys[end]

    # Natural cubic spline coefficients
    # Using simplified Thomas algorithm
    h = diff(xs)
    δ = diff(ys) ./ h

    # Build tridiagonal system for second derivatives
    n_interior = n - 2
    if n_interior < 1
        return linear_interp(x, xs, ys)
    end

    # Diagonal elements
    diag_main = [2.0 * (h[i] + h[i+1]) for i in 1:n_interior]
    diag_lower = h[2:n_interior]
    diag_upper = h[2:n_interior]
    rhs = [6.0 * (δ[i+1] - δ[i]) for i in 1:n_interior]

    # Solve tridiagonal system (Thomas algorithm)
    M = zeros(n)  # Second derivatives
    if n_interior == 1
        M[2] = rhs[1] / diag_main[1]
    else
        # Forward elimination
        c_prime = zeros(n_interior)
        d_prime = zeros(n_interior)

        c_prime[1] = diag_upper[1] / diag_main[1]
        d_prime[1] = rhs[1] / diag_main[1]

        for i in 2:n_interior
            denom = diag_main[i] - diag_lower[i-1] * c_prime[i-1]
            if i < n_interior
                c_prime[i] = diag_upper[i] / denom
            end
            d_prime[i] = (rhs[i] - diag_lower[i-1] * d_prime[i-1]) / denom
        end

        # Back substitution
        M[n-1] = d_prime[n_interior]
        for i in (n_interior-1):-1:1
            M[i+1] = d_prime[i] - c_prime[i] * M[i+2]
        end
    end

    # Natural spline: M[1] = M[n] = 0 (already initialized)

    # Find interval and evaluate
    idx = searchsortedfirst(xs, x)
    idx = min(max(idx, 2), n)
    i = idx - 1

    dx = x - xs[i]
    h_i = h[i]

    # Cubic polynomial evaluation
    a = (M[i+1] - M[i]) / (6.0 * h_i)
    b = M[i] / 2.0
    c = δ[i] - h_i * (2.0 * M[i] + M[i+1]) / 6.0
    d = ys[i]

    d + dx * (c + dx * (b + dx * a))
end

# ============================================================================
# Interpolation Dispatcher
# ============================================================================

"""
    interpolate(x, xs, ys, method)

Dispatch to appropriate interpolation method.

# Arguments
- `x::Float64`: Point to interpolate at
- `xs::Vector{Float64}`: X coordinates
- `ys::Vector{Float64}`: Y values
- `method::InterpolationMethod`: Interpolation method

# Returns
- `Float64`: Interpolated y value
"""
function interpolate(
    x::Float64,
    xs::Vector{Float64},
    ys::Vector{Float64},
    method::InterpolationMethod
)::Float64
    if method == LINEAR
        linear_interp(x, xs, ys)
    elseif method == LOG_LINEAR
        log_linear_interp(x, xs, ys)
    elseif method == CUBIC
        cubic_interp(x, xs, ys)
    else
        error("Unknown interpolation method: $method")
    end
end

# ============================================================================
# Vector Interpolation
# ============================================================================

"""
    interpolate_vector(x_new, xs, ys; method=LINEAR)

Interpolate at multiple points.

# Arguments
- `x_new::Vector{Float64}`: Points to interpolate at
- `xs::Vector{Float64}`: X coordinates
- `ys::Vector{Float64}`: Y values
- `method::InterpolationMethod`: Interpolation method

# Returns
- `Vector{Float64}`: Interpolated values
"""
function interpolate_vector(
    x_new::Vector{Float64},
    xs::Vector{Float64},
    ys::Vector{Float64};
    method::InterpolationMethod = LINEAR
)::Vector{Float64}
    [interpolate(x, xs, ys, method) for x in x_new]
end

# ============================================================================
# Extrapolation Helpers
# ============================================================================

"""
    extrapolate_flat(x, xs, ys)

Linear interpolation with flat extrapolation.

# Arguments
- `x::Float64`: Point
- `xs::Vector{Float64}`: X coordinates
- `ys::Vector{Float64}`: Y values

# Returns
- `Float64`: Value (flat at boundaries)
"""
function extrapolate_flat(x::Float64, xs::Vector{Float64}, ys::Vector{Float64})::Float64
    x < xs[1] && return ys[1]
    x > xs[end] && return ys[end]
    linear_interp(x, xs, ys)
end

"""
    extrapolate_linear(x, xs, ys)

Linear interpolation with linear extrapolation.

# Arguments
- `x::Float64`: Point
- `xs::Vector{Float64}`: X coordinates
- `ys::Vector{Float64}`: Y values

# Returns
- `Float64`: Value (linear extrapolation at boundaries)
"""
function extrapolate_linear(x::Float64, xs::Vector{Float64}, ys::Vector{Float64})::Float64
    if x < xs[1]
        # Extrapolate using first two points
        slope = (ys[2] - ys[1]) / (xs[2] - xs[1])
        return ys[1] + slope * (x - xs[1])
    elseif x > xs[end]
        # Extrapolate using last two points
        n = length(xs)
        slope = (ys[n] - ys[n-1]) / (xs[n] - xs[n-1])
        return ys[n] + slope * (x - xs[n])
    else
        linear_interp(x, xs, ys)
    end
end
