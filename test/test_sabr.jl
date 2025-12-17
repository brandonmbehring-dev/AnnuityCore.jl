"""
Tests for SABR stochastic volatility model.
"""

using Test
using AnnuityCore


@testset "SABRParams Construction" begin
    # Valid construction
    params = SABRParams(F=100.0, α=0.20, β=0.5, ρ=-0.3, ν=0.4, τ=1.0)
    @test params.F == 100.0
    @test params.α == 0.20
    @test params.β == 0.5
    @test params.ρ == -0.3
    @test params.ν == 0.4
    @test params.τ == 1.0

    # Defaults
    params_default = SABRParams(F=100.0, α=0.20, ν=0.4, τ=1.0)
    @test params_default.β == 1.0  # Default lognormal
    @test params_default.ρ == 0.0  # Default no correlation

    # Invalid parameters
    @test_throws ArgumentError SABRParams(F=-100.0, α=0.20, ν=0.4, τ=1.0)
    @test_throws ArgumentError SABRParams(F=100.0, α=-0.20, ν=0.4, τ=1.0)
    @test_throws ArgumentError SABRParams(F=100.0, α=0.20, β=1.5, ν=0.4, τ=1.0)
    @test_throws ArgumentError SABRParams(F=100.0, α=0.20, ρ=-1.5, ν=0.4, τ=1.0)
end


@testset "SABR ATM Implied Vol" begin
    # At ATM, SABR implied vol should be close to α / F^(1-β)
    params = SABRParams(F=100.0, α=0.20, β=0.5, ρ=0.0, ν=0.0, τ=1.0)

    σ_atm = sabr_implied_vol(params, 100.0)

    # With ν=0 and ρ=0, ATM vol ≈ α / F^(1-β) = 0.20 / 100^0.5 = 0.02
    @test abs(σ_atm - 0.02) < 0.01

    # Lognormal SABR (β=1): ATM vol ≈ α
    params_ln = SABRParams(F=100.0, α=0.20, β=1.0, ρ=0.0, ν=0.0, τ=1.0)
    σ_atm_ln = sabr_implied_vol(params_ln, 100.0)
    @test abs(σ_atm_ln - 0.20) < 0.01
end


@testset "SABR Smile Shape" begin
    params = SABRParams(F=100.0, α=0.20, β=0.5, ρ=-0.3, ν=0.4, τ=1.0)

    strikes = [80.0, 90.0, 100.0, 110.0, 120.0]
    vols = sabr_smile(params, strikes)

    @test length(vols) == 5
    @test all(vols .> 0)

    # With negative ρ, should have skew (put wing higher than call wing)
    # [T1] Negative ρ creates asymmetry: put wing elevated more than call wing
    @test vols[1] > vols[3]  # 80 strike > ATM
    @test vols[1] > vols[5]  # Put wing (80) > Call wing (120) - skew effect

    # Both wings can be above ATM due to ν (vol-of-vol) creating curvature
    # This is the butterfly effect, separate from skew
end


@testset "SABR Symmetric ρ=0" begin
    # With ρ=0, smile should be symmetric around ATM
    params = SABRParams(F=100.0, α=0.20, β=0.5, ρ=0.0, ν=0.3, τ=1.0)

    σ_80 = sabr_implied_vol(params, 80.0)
    σ_120 = sabr_implied_vol(params, 125.0)  # 100/80 = 1.25, 125/100 = 1.25

    # Should be approximately equal for equidistant strikes
    @test abs(σ_80 - σ_120) < 0.02
end


@testset "SABR Vol of Vol Effect" begin
    # Higher ν should increase smile curvature

    params_low_nu = SABRParams(F=100.0, α=0.20, β=0.5, ρ=-0.3, ν=0.1, τ=1.0)
    params_high_nu = SABRParams(F=100.0, α=0.20, β=0.5, ρ=-0.3, ν=0.6, τ=1.0)

    # Wing vols
    σ_80_low = sabr_implied_vol(params_low_nu, 80.0)
    σ_80_high = sabr_implied_vol(params_high_nu, 80.0)
    σ_atm_low = sabr_implied_vol(params_low_nu, 100.0)
    σ_atm_high = sabr_implied_vol(params_high_nu, 100.0)

    # Higher ν should produce higher wing vols relative to ATM
    wing_spread_low = σ_80_low - σ_atm_low
    wing_spread_high = σ_80_high - σ_atm_high

    @test wing_spread_high > wing_spread_low
end


@testset "SABR Beta Effect" begin
    # β=0: Normal backbone
    # β=1: Lognormal backbone
    # β=0.5: In between (common for rates)

    params_normal = SABRParams(F=100.0, α=2.0, β=0.0, ρ=0.0, ν=0.3, τ=1.0)
    params_lognormal = SABRParams(F=100.0, α=0.20, β=1.0, ρ=0.0, ν=0.3, τ=1.0)

    σ_atm_normal = sabr_implied_vol(params_normal, 100.0)
    σ_atm_lognormal = sabr_implied_vol(params_lognormal, 100.0)

    # Both should give valid positive vols
    @test σ_atm_normal > 0
    @test σ_atm_lognormal > 0
end


@testset "SABR Calibration" begin
    # Generate synthetic market data from known SABR params
    true_params = SABRParams(F=100.0, α=0.20, β=0.5, ρ=-0.3, ν=0.4, τ=1.0)

    strikes = [85.0, 90.0, 95.0, 100.0, 105.0, 110.0, 115.0]
    market_vols = sabr_smile(true_params, strikes)

    # Calibrate with fixed β
    calibrated = calibrate_sabr(100.0, 1.0, strikes, market_vols; β=0.5)

    @test calibrated.F == 100.0
    @test calibrated.τ == 1.0
    @test calibrated.β == 0.5

    # Should recover parameters reasonably well
    @test abs(calibrated.α - 0.20) < 0.05
    @test abs(calibrated.ρ - (-0.3)) < 0.15
    @test abs(calibrated.ν - 0.4) < 0.15

    # Calibrated smile should match market
    fitted_vols = sabr_smile(calibrated, strikes)
    max_error = maximum(abs.(fitted_vols .- market_vols))
    @test max_error < 0.01
end


@testset "SABR Obloj Correction" begin
    params = SABRParams(F=100.0, α=0.20, β=0.5, ρ=-0.3, ν=0.4, τ=1.0)

    σ_hagan = sabr_implied_vol(params, 80.0; method=:hagan)
    σ_obloj = sabr_implied_vol(params, 80.0; method=:obloj)

    # Both methods should give similar results for reasonable parameters
    @test abs(σ_hagan - σ_obloj) < 0.01

    # Both should be positive
    @test σ_hagan > 0
    @test σ_obloj > 0
end


@testset "SABR Delta" begin
    params = SABRParams(F=100.0, α=0.20, β=0.5, ρ=-0.3, ν=0.4, τ=1.0)
    r = 0.05

    # ATM call delta should be around 0.5
    delta_atm = sabr_delta(params, 100.0, r; call=true)
    @test 0.4 < delta_atm < 0.6

    # ATM put delta should be around -0.5
    delta_atm_put = sabr_delta(params, 100.0, r; call=false)
    @test -0.6 < delta_atm_put < -0.4

    # OTM call delta should be lower
    delta_otm = sabr_delta(params, 120.0, r; call=true)
    @test delta_otm < delta_atm

    # ITM call delta should be higher
    delta_itm = sabr_delta(params, 80.0, r; call=true)
    @test delta_itm > delta_atm
end


@testset "SABR Vega" begin
    params = SABRParams(F=100.0, α=0.20, β=0.5, ρ=-0.3, ν=0.4, τ=1.0)
    r = 0.05

    vega = sabr_vega(params, 100.0, r)

    # Vega should be positive (higher α → higher prices)
    @test vega > 0

    # ATM vega should be substantial
    @test vega > 0.1
end


@testset "SABR Extreme Parameters" begin
    # Very high vol of vol
    params_high_nu = SABRParams(F=100.0, α=0.20, β=0.5, ρ=-0.3, ν=1.0, τ=1.0)
    σ = sabr_implied_vol(params_high_nu, 100.0)
    @test σ > 0
    @test isfinite(σ)

    # Near-zero vol of vol
    params_low_nu = SABRParams(F=100.0, α=0.20, β=0.5, ρ=-0.3, ν=0.01, τ=1.0)
    σ_low = sabr_implied_vol(params_low_nu, 100.0)
    @test σ_low > 0

    # Very short expiry
    params_short = SABRParams(F=100.0, α=0.20, β=0.5, ρ=-0.3, ν=0.4, τ=0.01)
    σ_short = sabr_implied_vol(params_short, 100.0)
    @test σ_short > 0
end


@testset "SABR Invalid Inputs" begin
    params = SABRParams(F=100.0, α=0.20, β=0.5, ρ=-0.3, ν=0.4, τ=1.0)

    @test_throws ArgumentError sabr_implied_vol(params, -100.0)
    @test_throws ArgumentError sabr_implied_vol(params, 0.0)
end
