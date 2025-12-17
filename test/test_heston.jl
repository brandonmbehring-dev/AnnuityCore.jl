"""
Tests for Heston stochastic volatility model.
"""

using Test
using AnnuityCore
using Statistics


@testset "HestonParams Construction" begin
    # Valid construction
    params = HestonParams(
        S₀ = 100.0, r = 0.05, q = 0.02,
        V₀ = 0.04, κ = 2.0, θ = 0.04,
        σ_v = 0.3, ρ = -0.7, τ = 1.0
    )
    @test params.S₀ == 100.0
    @test params.V₀ == 0.04
    @test params.ρ == -0.7

    # Default q = 0
    params_no_q = HestonParams(
        S₀ = 100.0, r = 0.05,
        V₀ = 0.04, κ = 2.0, θ = 0.04,
        σ_v = 0.3, ρ = -0.7, τ = 1.0
    )
    @test params_no_q.q == 0.0

    # Invalid parameters
    @test_throws ArgumentError HestonParams(
        S₀ = -100.0, r = 0.05, V₀ = 0.04,
        κ = 2.0, θ = 0.04, σ_v = 0.3, ρ = -0.7, τ = 1.0
    )
    @test_throws ArgumentError HestonParams(
        S₀ = 100.0, r = 0.05, V₀ = 0.04,
        κ = 2.0, θ = 0.04, σ_v = 0.3, ρ = -1.5, τ = 1.0  # ρ out of bounds
    )
end


@testset "Feller Condition" begin
    # Feller satisfied: 2κθ = 2*2*0.04 = 0.16 > σ_v² = 0.09
    params_feller = HestonParams(
        S₀ = 100.0, r = 0.05, V₀ = 0.04,
        κ = 2.0, θ = 0.04, σ_v = 0.3, ρ = -0.7, τ = 1.0
    )
    @test feller_condition(params_feller) == true

    # Feller violated: 2κθ = 2*0.5*0.04 = 0.04 < σ_v² = 0.16
    params_no_feller = HestonParams(
        S₀ = 100.0, r = 0.05, V₀ = 0.04,
        κ = 0.5, θ = 0.04, σ_v = 0.4, ρ = -0.7, τ = 1.0
    )
    @test feller_condition(params_no_feller) == false
end


@testset "Heston Path Generation - Euler" begin
    params = HestonParams(
        S₀ = 100.0, r = 0.05, q = 0.0,
        V₀ = 0.04, κ = 2.0, θ = 0.04,
        σ_v = 0.3, ρ = -0.7, τ = 1.0
    )

    result = generate_heston_paths(params, 1000, 252; seed=42, scheme=:euler)

    @test size(result.spot_paths) == (1000, 253)
    @test size(result.variance_paths) == (1000, 253)
    @test all(result.spot_paths[:, 1] .== 100.0)
    @test all(result.variance_paths[:, 1] .== 0.04)

    # Terminal prices should be positive
    @test all(result.spot_paths[:, end] .> 0)

    # Variance should be mostly positive (some may go slightly negative with Euler)
    @test mean(result.variance_paths[:, end] .> 0) > 0.9
end


@testset "Heston Path Generation - QE Scheme" begin
    params = HestonParams(
        S₀ = 100.0, r = 0.05, q = 0.0,
        V₀ = 0.04, κ = 2.0, θ = 0.04,
        σ_v = 0.3, ρ = -0.7, τ = 1.0
    )

    result = generate_heston_paths(params, 1000, 252; seed=42, scheme=:qe)

    @test size(result.spot_paths) == (1000, 253)

    # QE should keep variance non-negative
    @test all(result.variance_paths .>= 0)

    # Terminal spot should be positive
    @test all(result.spot_paths[:, end] .> 0)
end


@testset "Heston MC Call Pricing" begin
    params = HestonParams(
        S₀ = 100.0, r = 0.05, q = 0.0,
        V₀ = 0.04, κ = 2.0, θ = 0.04,
        σ_v = 0.3, ρ = -0.7, τ = 1.0
    )

    # ATM call
    result = heston_call_mc(params, 100.0; n_paths=50000, seed=42)

    @test result.price > 0
    @test result.std_error > 0
    @test result.std_error < 0.5  # Reasonable precision

    # Price should be in reasonable range for ATM call
    # BS ATM call with 20% vol ≈ $8
    @test 5.0 < result.price < 15.0

    # OTM call should be cheaper
    result_otm = heston_call_mc(params, 120.0; n_paths=50000, seed=42)
    @test result_otm.price < result.price
end


@testset "Heston MC Put Pricing" begin
    params = HestonParams(
        S₀ = 100.0, r = 0.05, q = 0.0,
        V₀ = 0.04, κ = 2.0, θ = 0.04,
        σ_v = 0.3, ρ = -0.7, τ = 1.0
    )

    result = heston_put_mc(params, 100.0; n_paths=50000, seed=42)

    @test result.price > 0
    @test result.std_error > 0

    # Put-call parity check (approximate due to MC error)
    call_result = heston_call_mc(params, 100.0; n_paths=50000, seed=42)
    forward_diff = params.S₀ * exp(-params.q * params.τ) -
                   100.0 * exp(-params.r * params.τ)

    parity_error = abs(call_result.price - result.price - forward_diff)
    @test parity_error < 1.0  # Within MC error
end


@testset "Heston Characteristic Function" begin
    params = HestonParams(
        S₀ = 100.0, r = 0.05, q = 0.0,
        V₀ = 0.04, κ = 2.0, θ = 0.04,
        σ_v = 0.3, ρ = -0.7, τ = 1.0
    )

    # CF at u=0 should give 1 (in log terms, E[S_T] discounted)
    cf_0 = heston_characteristic_function(0.0, params)
    @test abs(cf_0 - 1.0) < 1e-10

    # CF should be well-defined for typical frequencies
    cf_1 = heston_characteristic_function(1.0, params)
    @test isfinite(abs(cf_1))

    # Complex input
    cf_complex = heston_characteristic_function(complex(1.0, 0.5), params)
    @test isfinite(abs(cf_complex))
end


@testset "Heston Reproducibility" begin
    params = HestonParams(
        S₀ = 100.0, r = 0.05, q = 0.0,
        V₀ = 0.04, κ = 2.0, θ = 0.04,
        σ_v = 0.3, ρ = -0.7, τ = 1.0
    )

    # Same seed should give same results
    result1 = heston_call_mc(params, 100.0; n_paths=10000, seed=123)
    result2 = heston_call_mc(params, 100.0; n_paths=10000, seed=123)

    @test result1.price == result2.price
end


@testset "Heston Negative Correlation Effect" begin
    # Negative correlation: when spot drops, vol rises (leverage effect)
    # This should increase put prices relative to calls
    # NOTE: Use Euler scheme which correctly handles correlation ρ

    params_neg_rho = HestonParams(
        S₀ = 100.0, r = 0.05, q = 0.0,
        V₀ = 0.04, κ = 2.0, θ = 0.04,
        σ_v = 0.3, ρ = -0.7, τ = 1.0
    )

    params_pos_rho = HestonParams(
        S₀ = 100.0, r = 0.05, q = 0.0,
        V₀ = 0.04, κ = 2.0, θ = 0.04,
        σ_v = 0.3, ρ = 0.7, τ = 1.0
    )

    # OTM put should be more expensive with negative correlation
    # Use Euler scheme which correctly implements spot-variance correlation
    put_neg = heston_put_mc(params_neg_rho, 80.0; n_paths=50000, seed=42, scheme=:euler)
    put_pos = heston_put_mc(params_pos_rho, 80.0; n_paths=50000, seed=42, scheme=:euler)

    @test put_neg.price > put_pos.price
end
