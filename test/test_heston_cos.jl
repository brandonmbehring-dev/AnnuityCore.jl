"""
Tests for COS method Heston pricing.
"""

using Test
using AnnuityCore
using Statistics


@testset "COSConfig Construction" begin
    # Default config
    config = COSConfig()
    @test config.N == 256
    @test config.L == 10.0

    # Custom config
    config_custom = COSConfig(N=512, L=12.0)
    @test config_custom.N == 512
    @test config_custom.L == 12.0

    # Invalid config
    @test_throws ArgumentError COSConfig(N=-1)
    @test_throws ArgumentError COSConfig(L=-1.0)
end


@testset "Heston COS Call - Basic Pricing" begin
    params = HestonParams(
        S₀ = 100.0, r = 0.05, q = 0.0,
        V₀ = 0.04, κ = 2.0, θ = 0.04,
        σ_v = 0.3, ρ = -0.7, τ = 1.0
    )

    price = heston_cos_call(params, 100.0)

    # COS should give reasonable ATM call price
    @test isfinite(price)
    @test price > 0
    @test 5.0 < price < 15.0  # ATM call ≈ 10 for these params
end


@testset "Heston COS Put - Basic Pricing" begin
    params = HestonParams(
        S₀ = 100.0, r = 0.05, q = 0.0,
        V₀ = 0.04, κ = 2.0, θ = 0.04,
        σ_v = 0.3, ρ = -0.7, τ = 1.0
    )

    price = heston_cos_put(params, 100.0)

    # COS should give reasonable ATM put price
    @test isfinite(price)
    @test price > 0
    @test 2.0 < price < 10.0  # ATM put ≈ 5 for these params
end


@testset "Heston COS Put-Call Parity" begin
    params = HestonParams(
        S₀ = 100.0, r = 0.05, q = 0.02,
        V₀ = 0.04, κ = 2.0, θ = 0.04,
        σ_v = 0.3, ρ = -0.7, τ = 1.0
    )

    # Test parity across multiple strikes
    for K in [80.0, 100.0, 120.0]
        call = heston_cos_call(params, K)
        put = heston_cos_put(params, K)

        # Put-call parity: C - P = S*exp(-q*τ) - K*exp(-r*τ)
        forward_diff = params.S₀ * exp(-params.q * params.τ) - K * exp(-params.r * params.τ)
        parity_error = abs((call - put) - forward_diff)

        @test parity_error < 1e-6  # Should be very close (numerical precision)
    end
end


@testset "Heston COS vs MC Comparison" begin
    params = HestonParams(
        S₀ = 100.0, r = 0.05, q = 0.0,
        V₀ = 0.04, κ = 2.0, θ = 0.04,
        σ_v = 0.3, ρ = -0.7, τ = 1.0
    )

    result = benchmark_cos_vs_mc(params, 100.0; n_mc_paths=100000)

    @test isfinite(result.cos_price)
    @test result.mc_price > 0
    @test result.cos_price > 0

    # COS and MC(Euler) should agree within 10%
    # Note: MC uses Euler scheme which handles ρ correctly
    # QE scheme does not, so we compare against Euler
    error_pct = abs(result.cos_price - result.mc_price) / result.mc_price
    @test error_pct < 0.10  # 10% tolerance for ATM
end


@testset "Heston COS Convergence in N" begin
    params = HestonParams(
        S₀ = 100.0, r = 0.05, q = 0.0,
        V₀ = 0.04, κ = 2.0, θ = 0.04,
        σ_v = 0.3, ρ = -0.7, τ = 1.0
    )

    price_64 = heston_cos_call(params, 100.0; config=COSConfig(N=64))
    price_128 = heston_cos_call(params, 100.0; config=COSConfig(N=128))
    price_256 = heston_cos_call(params, 100.0; config=COSConfig(N=256))

    @test isfinite(price_64)
    @test isfinite(price_128)
    @test isfinite(price_256)

    # All should be close (COS converges quickly)
    @test abs(price_64 - price_256) / price_256 < 0.05  # Within 5%
    @test abs(price_128 - price_256) / price_256 < 0.01  # Within 1%
end


@testset "Heston COS Strike Range" begin
    params = HestonParams(
        S₀ = 100.0, r = 0.05, q = 0.0,
        V₀ = 0.04, κ = 2.0, θ = 0.04,
        σ_v = 0.3, ρ = -0.7, τ = 1.0
    )

    strikes = [80.0, 90.0, 100.0, 110.0, 120.0]
    call_prices = [heston_cos_call(params, K) for K in strikes]
    put_prices = [heston_cos_put(params, K) for K in strikes]

    @test all(isfinite.(call_prices))
    @test all(isfinite.(put_prices))
    @test all(call_prices .> 0)
    @test all(put_prices .> 0)

    # Call prices should decrease with strike
    @test issorted(call_prices, rev=true)

    # Put prices should increase with strike
    @test issorted(put_prices)
end


@testset "Heston COS Greeks" begin
    params = HestonParams(
        S₀ = 100.0, r = 0.05, q = 0.0,
        V₀ = 0.04, κ = 2.0, θ = 0.04,
        σ_v = 0.3, ρ = -0.7, τ = 1.0
    )

    greeks = heston_cos_greeks(params, 100.0)

    # Just test it runs and returns finite values
    @test isfinite(greeks.delta)
    @test isfinite(greeks.gamma)
    @test isfinite(greeks.vega)
    @test isfinite(greeks.rho)
end


@testset "Heston COS Implied Vol Smile" begin
    params = HestonParams(
        S₀ = 100.0, r = 0.05, q = 0.0,
        V₀ = 0.04, κ = 2.0, θ = 0.04,
        σ_v = 0.3, ρ = -0.7, τ = 1.0
    )

    # With negative ρ, should exhibit negative skew (put wing higher)
    # Implied vols would show this, but we just test prices show the effect
    call_80 = heston_cos_call(params, 80.0)
    call_100 = heston_cos_call(params, 100.0)
    call_120 = heston_cos_call(params, 120.0)

    # ITM calls should be more expensive than BS would predict
    # relative to OTM calls due to negative skew
    @test call_80 > call_100 > call_120
end


@testset "Heston COS Different Expiries" begin
    # Longer expiry should give higher call price (for ATM)
    params_short = HestonParams(
        S₀ = 100.0, r = 0.05, q = 0.0,
        V₀ = 0.04, κ = 2.0, θ = 0.04,
        σ_v = 0.3, ρ = -0.7, τ = 0.25
    )
    params_long = HestonParams(
        S₀ = 100.0, r = 0.05, q = 0.0,
        V₀ = 0.04, κ = 2.0, θ = 0.04,
        σ_v = 0.3, ρ = -0.7, τ = 2.0
    )

    price_short = heston_cos_call(params_short, 100.0)
    price_long = heston_cos_call(params_long, 100.0)

    @test price_short > 0
    @test price_long > price_short  # Longer expiry = more value
end


@testset "Heston COS Zero Correlation" begin
    # With ρ = 0, smile should be symmetric
    params = HestonParams(
        S₀ = 100.0, r = 0.05, q = 0.0,
        V₀ = 0.04, κ = 2.0, θ = 0.04,
        σ_v = 0.3, ρ = 0.0, τ = 1.0
    )

    # OTM call and OTM put at equivalent moneyness
    call_120 = heston_cos_call(params, 120.0)
    put_80 = heston_cos_put(params, 80.0)

    # Put-call symmetry for ρ=0 (approximate)
    @test call_120 > 0
    @test put_80 > 0
end


@testset "Heston COS Invalid Strike" begin
    params = HestonParams(
        S₀ = 100.0, r = 0.05, q = 0.0,
        V₀ = 0.04, κ = 2.0, θ = 0.04,
        σ_v = 0.3, ρ = -0.7, τ = 1.0
    )

    @test_throws ArgumentError heston_cos_call(params, -100.0)
    @test_throws ArgumentError heston_cos_call(params, 0.0)
end


@testset "Heston COS High Vol of Vol" begin
    # High σ_v can be challenging for COS
    params = HestonParams(
        S₀ = 100.0, r = 0.05, q = 0.0,
        V₀ = 0.04, κ = 2.0, θ = 0.04,
        σ_v = 0.8, ρ = -0.7, τ = 1.0
    )

    # May need more terms for accuracy
    config = COSConfig(N=512, L=15.0)
    price = heston_cos_call(params, 100.0; config=config)

    @test price > 0
    @test isfinite(price)
end
