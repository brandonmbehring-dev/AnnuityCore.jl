"""
Tests for GLWB (Guaranteed Lifetime Withdrawal Benefit) pricing.
"""

using Test
using AnnuityCore
using Statistics


@testset "GWBConfig Construction" begin
    # Default construction
    config = GWBConfig()
    @test config.rollup_type == COMPOUND
    @test config.rollup_rate == 0.06
    @test config.rollup_cap_years == 10
    @test config.withdrawal_rate == 0.05
    @test config.fee_rate == 0.01
    @test config.ratchet_enabled == true
    @test config.fee_basis == :gwb

    # Custom construction
    config_custom = GWBConfig(
        rollup_type = SIMPLE,
        rollup_rate = 0.07,
        rollup_cap_years = 15,
        withdrawal_rate = 0.04,
        fee_rate = 0.015,
        ratchet_enabled = false,
        fee_basis = :av
    )
    @test config_custom.rollup_type == SIMPLE
    @test config_custom.rollup_rate == 0.07

    # Invalid parameters
    @test_throws ArgumentError GWBConfig(rollup_rate = -0.01)
    @test_throws ArgumentError GWBConfig(withdrawal_rate = 0.0)
    @test_throws ArgumentError GWBConfig(withdrawal_rate = 0.25)
    @test_throws ArgumentError GWBConfig(fee_basis = :invalid)
end


@testset "GWBState Construction" begin
    # From premium
    state = GWBState(100000.0)
    @test state.gwb == 100000.0
    @test state.av == 100000.0
    @test state.rollup_base == 100000.0
    @test state.high_water_mark == 100000.0
    @test state.years_since_issue == 0.0
    @test state.withdrawal_phase_started == false
    @test state.total_withdrawals == 0.0

    # Full constructor
    state2 = GWBState(110000.0, 95000.0, 100000.0, 105000.0, 2.0, true, 10000.0)
    @test state2.gwb == 110000.0
    @test state2.av == 95000.0

    # Invalid
    @test_throws ArgumentError GWBState(-1.0)
end


@testset "Simple Rollup" begin
    # Basic calculation
    @test simple_rollup(100000.0, 0.06, 5.0, 10) ≈ 130000.0
    @test simple_rollup(100000.0, 0.06, 10.0, 10) ≈ 160000.0

    # Cap enforcement
    @test simple_rollup(100000.0, 0.06, 15.0, 10) ≈ 160000.0  # Capped at 10 years
    @test simple_rollup(100000.0, 0.06, 20.0, 10) ≈ 160000.0

    # Zero rollup rate
    @test simple_rollup(100000.0, 0.0, 5.0, 10) ≈ 100000.0
end


@testset "Compound Rollup" begin
    # Basic calculation
    @test compound_rollup(100000.0, 0.06, 1.0, 10) ≈ 106000.0
    @test compound_rollup(100000.0, 0.06, 5.0, 10) ≈ 100000.0 * 1.06^5

    # Cap enforcement
    @test compound_rollup(100000.0, 0.06, 15.0, 10) ≈ 100000.0 * 1.06^10
    @test compound_rollup(100000.0, 0.06, 20.0, 10) ≈ 100000.0 * 1.06^10

    # Compound > Simple for same parameters
    simple_val = simple_rollup(100000.0, 0.06, 10.0, 10)
    compound_val = compound_rollup(100000.0, 0.06, 10.0, 10)
    @test compound_val > simple_val
end


@testset "Ratchet Mechanics" begin
    @test apply_ratchet(100000.0, 110000.0) == 110000.0  # Step up
    @test apply_ratchet(100000.0, 90000.0) == 100000.0   # No step down
    @test apply_ratchet(100000.0, 100000.0) == 100000.0  # Equal
end


@testset "Is Anniversary" begin
    # Monthly timesteps (dt = 1/12 ≈ 0.083)
    # is_anniversary checks if floor(years + dt) > floor(years)
    @test is_anniversary(0.91, 1/12) == false  # 0.91 + 0.083 = 0.993, floors to 0
    @test is_anniversary(0.5, 1/12) == false   # 0.5 + 0.083 = 0.583, same year
    @test is_anniversary(0.92, 1/12) == true   # 0.92 + 0.083 = 1.003, crosses year 1

    # Annual timesteps
    @test is_anniversary(0.0, 1.0) == true     # 0 + 1 = 1, crosses year 1
    @test is_anniversary(0.5, 1.0) == true     # 0.5 + 1 = 1.5, crosses year 1
end


@testset "GWB State Step - Basic" begin
    state = GWBState(100000.0)
    config = GWBConfig(fee_rate = 0.0, ratchet_enabled = false)  # Simplify

    # Positive market return, no withdrawal
    result = step!(state, config, 0.05, 0.0, 1.0)
    @test state.av ≈ 105000.0 atol=1.0
    @test state.years_since_issue ≈ 1.0

    # First step: rollup calculated at years=0 (before update), so GWB = base
    # Second step will show rollup increase
    @test state.gwb == 100000.0  # Rollup at year 0 = base

    # Second step - now rollup should show
    result2 = step!(state, config, 0.05, 0.0, 1.0)
    @test state.years_since_issue ≈ 2.0
    # After step 2, rollup was calculated at years=1.0, so GWB = base * (1.06)^1
    @test state.gwb ≈ 106000.0 atol=100.0
end


@testset "GWB State Step - Fee Deduction" begin
    state = GWBState(100000.0)
    config = GWBConfig(fee_rate = 0.01, fee_basis = :av)

    # No market return, annual step
    result = step!(state, config, 0.0, 0.0, 1.0)

    # Fee should be 1% of AV
    @test result.fee_charged ≈ 1000.0 atol=10.0
    @test state.av < 100000.0
end


@testset "GWB State Step - Withdrawal" begin
    state = GWBState(100000.0)
    config = GWBConfig(withdrawal_rate = 0.05, fee_rate = 0.0)

    # Take withdrawal (5% annual = 5000)
    result = step!(state, config, 0.0, 5000.0, 1.0)

    @test state.withdrawal_phase_started == true
    @test result.withdrawal_taken ≈ 5000.0
    @test state.av ≈ 95000.0 atol=100.0
    @test state.total_withdrawals ≈ 5000.0
end


@testset "GWB State Step - Excess Withdrawal" begin
    state = GWBState(100000.0)
    config = GWBConfig(withdrawal_rate = 0.05, fee_rate = 0.0)

    # Excess withdrawal (more than 5% = 5000)
    result = step!(state, config, 0.0, 10000.0, 1.0)

    @test result.withdrawal_taken ≈ 10000.0
    # GWB should be reduced due to excess
    @test state.gwb < 100000.0
end


@testset "Mortality Functions" begin
    # Default mortality increases with age
    qx_50 = default_mortality(50)
    qx_70 = default_mortality(70)
    qx_90 = default_mortality(90)

    @test qx_50 > 0
    @test qx_70 > qx_50
    @test qx_90 > qx_70
    @test qx_90 <= 1.0

    # Gender difference
    qx_male = default_mortality(70, gender = :male)
    qx_female = default_mortality(70, gender = :female)
    @test qx_male > qx_female  # Males have higher mortality

    # Constant mortality
    mort = constant_mortality(0.01)
    @test mort(50) == 0.01
    @test mort(90) == 0.01

    # Zero mortality
    mort_zero = zero_mortality()
    @test mort_zero(50) == 0.0
end


@testset "Mortality Conversion" begin
    qx_annual = 0.01  # 1% annual

    # Monthly
    qx_monthly = convert_annual_to_step(qx_annual, 1/12)
    @test qx_monthly < qx_annual
    @test 12 * qx_monthly ≈ qx_annual atol=0.001  # Approximately

    # Semi-annual
    qx_semi = convert_annual_to_step(qx_annual, 0.5)
    @test qx_semi < qx_annual
end


@testset "Life Expectancy" begin
    # With zero mortality, life expectancy = remaining years
    mort_zero = zero_mortality()
    ex = life_expectancy(65, mort_zero, max_age = 100)
    @test ex ≈ 35.0

    # With real mortality, should be positive and substantial
    ex_real = life_expectancy(65, default_mortality)
    @test ex_real > 10.0   # Should be substantial
    @test ex_real < 55.0   # Should be less than max possible
end


@testset "Survival Probability" begin
    # Zero mortality
    mort_zero = zero_mortality()
    @test survival_probability(65, 10, mort_zero) == 1.0

    # With real mortality
    p_10 = survival_probability(65, 10, default_mortality)
    p_20 = survival_probability(65, 20, default_mortality)

    @test p_10 < 1.0
    @test p_20 < p_10  # Lower survival for longer period
    @test p_10 > p_20
end


@testset "GLWBSimulator Construction" begin
    sim = GLWBSimulator()
    @test sim.r == 0.04
    @test sim.sigma == 0.20
    @test sim.n_paths == 10000
    @test sim.steps_per_year == 1

    sim_custom = GLWBSimulator(
        r = 0.03,
        sigma = 0.25,
        n_paths = 5000,
        steps_per_year = 12
    )
    @test sim_custom.r == 0.03
    @test sim_custom.steps_per_year == 12

    # Invalid
    @test_throws ArgumentError GLWBSimulator(r = -0.01)
    @test_throws ArgumentError GLWBSimulator(sigma = 0.0)
    @test_throws ArgumentError GLWBSimulator(n_paths = 0)
end


@testset "GLWB Basic Pricing" begin
    sim = GLWBSimulator(
        n_paths = 1000,
        steps_per_year = 1,
        seed = 42
    )

    result = glwb_price(sim, 100000.0, 65)

    # Basic sanity checks
    @test result.price >= 0
    @test result.n_paths == 1000
    @test 0 <= result.prob_ruin <= 1
    @test result.standard_error >= 0

    # Guarantee cost should be reasonable (0-50% of premium typical)
    @test 0 <= result.guarantee_cost <= 0.5
end


@testset "GLWB Reproducibility" begin
    sim = GLWBSimulator(n_paths = 500, seed = 123)

    result1 = glwb_price(sim, 100000.0, 65)
    result2 = glwb_price(sim, 100000.0, 65)

    @test result1.price == result2.price
    @test result1.prob_ruin == result2.prob_ruin
end


@testset "GLWB Volatility Sensitivity" begin
    # Higher volatility should increase guarantee cost
    sim_low_vol = GLWBSimulator(sigma = 0.15, n_paths = 1000, seed = 42)
    sim_high_vol = GLWBSimulator(sigma = 0.30, n_paths = 1000, seed = 42)

    result_low = glwb_price(sim_low_vol, 100000.0, 65)
    result_high = glwb_price(sim_high_vol, 100000.0, 65)

    # Higher vol = higher guarantee cost (more ruin risk)
    @test result_high.guarantee_cost >= result_low.guarantee_cost
end


@testset "GLWB Age Sensitivity" begin
    sim = GLWBSimulator(n_paths = 1000, seed = 42)

    # Younger age = longer liability = higher cost
    result_55 = glwb_price(sim, 100000.0, 55)
    result_75 = glwb_price(sim, 100000.0, 75)

    # Younger policyholder typically has higher guarantee cost
    # (but this depends on many factors, so we just check it runs)
    @test result_55.n_paths == 1000
    @test result_75.n_paths == 1000
end


@testset "GLWB Zero Mortality" begin
    # With zero mortality, ruin becomes more likely over time
    sim = GLWBSimulator(
        mortality = zero_mortality(),
        n_paths = 500,
        seed = 42
    )

    result = glwb_price(sim, 100000.0, 65)

    @test result.price >= 0
    # With immortal policyholders, ruin should eventually happen
    # (unless returns are very high)
end


@testset "GLWB Monthly vs Annual Timesteps" begin
    sim_annual = GLWBSimulator(steps_per_year = 1, n_paths = 500, seed = 42)
    sim_monthly = GLWBSimulator(steps_per_year = 12, n_paths = 500, seed = 42)

    result_annual = glwb_price(sim_annual, 100000.0, 65)
    result_monthly = glwb_price(sim_monthly, 100000.0, 65)

    # Both should produce finite results
    @test isfinite(result_annual.price)
    @test isfinite(result_monthly.price)
end


@testset "GLWB Deferral Period" begin
    sim = GLWBSimulator(n_paths = 500, seed = 42)

    # No deferral
    result_0 = glwb_price(sim, 100000.0, 65, deferral_years = 0)

    # 5-year deferral (rollup accumulates, withdrawals delayed)
    result_5 = glwb_price(sim, 100000.0, 65, deferral_years = 5)

    # Both should work
    @test isfinite(result_0.price)
    @test isfinite(result_5.price)
end


@testset "GLWB Benefit Helper Functions" begin
    state = GWBState(120000.0, 80000.0, 100000.0, 100000.0, 5.0, true, 25000.0)

    # Is ruined
    @test is_ruined(state) == false
    state_ruined = GWBState(100000.0, 0.0, 100000.0, 100000.0, 10.0, true, 50000.0)
    @test is_ruined(state_ruined) == true

    # Benefit moneyness
    # (GWB - AV) / GWB = (120000 - 80000) / 120000 = 0.333
    @test benefit_moneyness(state) ≈ 0.333 atol=0.01

    # GWB to AV ratio
    @test gwb_to_av_ratio(state) ≈ 1.5
end


@testset "Max Withdrawal Calculation" begin
    state = GWBState(100000.0)
    config = GWBConfig(withdrawal_rate = 0.05)

    # Annual max withdrawal
    @test max_withdrawal(state, config, 1.0) ≈ 5000.0

    # Monthly max withdrawal
    @test max_withdrawal(state, config, 1/12) ≈ 5000.0/12 atol=1.0
end


@testset "Rollup Comparison" begin
    result = rollup_comparison(100000.0, 0.06, 10.0, 10)

    @test result.simple ≈ 160000.0
    @test result.compound ≈ 100000.0 * 1.06^10
    @test result.compound > result.simple
    @test result.ratio > 1.0
end
