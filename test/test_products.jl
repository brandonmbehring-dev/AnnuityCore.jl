"""
Tests for Product Pricers (MYGA, FIA, RILA).
"""

using Test
using AnnuityCore
using Statistics


# =============================================================================
# Product Types Tests
# =============================================================================

@testset "MarketParams Construction" begin
    # Valid construction
    market = MarketParams(100.0, 0.05, 0.02, 0.20)
    @test market.spot == 100.0
    @test market.risk_free_rate == 0.05
    @test market.dividend_yield == 0.02
    @test market.volatility == 0.20

    # Keyword constructor
    market2 = MarketParams(spot=100.0, risk_free_rate=0.05, volatility=0.20)
    @test market2.dividend_yield == 0.0

    # Invalid: negative spot
    @test_throws ArgumentError MarketParams(0.0, 0.05, 0.02, 0.20)
    @test_throws ArgumentError MarketParams(-100.0, 0.05, 0.02, 0.20)

    # Invalid: negative volatility
    @test_throws ArgumentError MarketParams(100.0, 0.05, 0.02, -0.20)
end


@testset "MYGAProduct Construction" begin
    # Valid construction
    product = MYGAProduct(0.045, 5, "Example Life", "5-Year MYGA")
    @test product.fixed_rate == 0.045
    @test product.guarantee_duration == 5

    # Keyword constructor
    product2 = MYGAProduct(fixed_rate=0.05, guarantee_duration=3)
    @test product2.fixed_rate == 0.05

    # Invalid: negative rate
    @test_throws ArgumentError MYGAProduct(-0.01, 5, "", "")

    # Invalid: zero duration
    @test_throws ArgumentError MYGAProduct(0.045, 0, "", "")
end


@testset "FIAProduct Construction" begin
    # Cap-style FIA
    product = FIAProduct(cap_rate=0.10, term_years=1)
    @test product.cap_rate == 0.10
    @test product.term_years == 1

    # Participation-style FIA
    product2 = FIAProduct(participation_rate=0.80, term_years=1)
    @test product2.participation_rate == 0.80
    @test product2.cap_rate === nothing

    # Spread-style FIA
    product3 = FIAProduct(spread_rate=0.02, term_years=1)
    @test product3.spread_rate == 0.02

    # Invalid: no crediting method
    @test_throws ArgumentError FIAProduct{Float64}(nothing, nothing, nothing, nothing, 1, "", "")

    # Invalid: zero term
    @test_throws ArgumentError FIAProduct(cap_rate=0.10, term_years=0)
end


@testset "RILAProduct Construction" begin
    # Buffer product
    product = RILAProduct(buffer_rate=0.10, cap_rate=0.20, is_buffer=true, term_years=1)
    @test product.buffer_rate == 0.10
    @test product.is_buffer == true

    # Floor product
    product2 = RILAProduct(floor_rate=-0.10, cap_rate=0.25, is_buffer=false, term_years=1)
    @test product2.floor_rate == -0.10
    @test product2.is_buffer == false

    # Invalid: buffer without buffer_rate
    @test_throws ArgumentError RILAProduct(buffer_rate=nothing, cap_rate=0.20, is_buffer=true, term_years=1)

    # Invalid: floor without floor_rate
    @test_throws ArgumentError RILAProduct(floor_rate=nothing, cap_rate=0.20, is_buffer=false, term_years=1)

    # Invalid: positive floor_rate
    @test_throws ArgumentError RILAProduct(floor_rate=0.10, cap_rate=0.20, is_buffer=false, term_years=1)
end


# =============================================================================
# MYGA Pricer Tests
# =============================================================================

@testset "MYGA Pricing - Basic" begin
    product = MYGAProduct(fixed_rate=0.045, guarantee_duration=5)

    # Price at product rate (should equal principal)
    result = price_myga(product, 100_000.0)
    @test result.present_value ≈ 100_000.0 atol=1.0

    # Duration = years for zero-coupon
    @test result.duration == 5.0

    # Convexity for zero-coupon
    @test result.convexity > 0

    # Details populated
    @test result.details[:fixed_rate] == 0.045
    @test result.details[:guarantee_duration] == 5
end


@testset "MYGA Pricing - Discount Rate Effects" begin
    product = MYGAProduct(fixed_rate=0.045, guarantee_duration=5)
    principal = 100_000.0

    # Discount rate < product rate → PV > principal
    result_low = price_myga(product, principal; discount_rate=0.03)
    @test result_low.present_value > principal

    # Discount rate > product rate → PV < principal
    result_high = price_myga(product, principal; discount_rate=0.06)
    @test result_high.present_value < principal

    # Discount rate = product rate → PV = principal
    result_equal = price_myga(product, principal; discount_rate=0.045)
    @test result_equal.present_value ≈ principal atol=1.0
end


@testset "MYGA Pricing - Duration and Convexity" begin
    product = MYGAProduct(fixed_rate=0.04, guarantee_duration=5)
    result = price_myga(product, 100_000.0; discount_rate=0.04)

    # Modified duration < Macaulay duration
    @test result.details[:modified_duration] < result.duration

    # Convexity = T × (T + 1) / (1 + r)^2
    expected_convexity = 5 * 6 / (1.04)^2
    @test result.convexity ≈ expected_convexity atol=0.01
end


@testset "MYGA Total Return" begin
    product = MYGAProduct(fixed_rate=0.045, guarantee_duration=5)

    # Total return = (1 + r)^n - 1
    total_return = myga_total_return(product)
    expected = 1.045^5 - 1
    @test total_return ≈ expected atol=1e-10
end


@testset "MYGA Sensitivity" begin
    product = MYGAProduct(fixed_rate=0.04, guarantee_duration=5)
    sens = myga_sensitivity(product, 100_000.0, 0.04)

    # DV01 should be positive (value decreases when rates increase)
    @test sens.dv01 > 0

    # Convexity effect should be positive
    @test sens.convexity_effect > 0
end


@testset "MYGA Breakeven Rate" begin
    product = MYGAProduct(fixed_rate=0.045, guarantee_duration=5)

    # Breakeven to get PV = 95000 (should be above product rate)
    breakeven = myga_breakeven_rate(product, 100_000.0, 95_000.0)
    @test breakeven > product.fixed_rate

    # Verify
    result = price_myga(product, 100_000.0; discount_rate=breakeven)
    @test result.present_value ≈ 95_000.0 atol=10.0
end


# =============================================================================
# FIA Pricer Tests
# =============================================================================

@testset "FIA Pricing - Cap Style" begin
    market = MarketParams(100.0, 0.05, 0.02, 0.20)
    product = FIAProduct(cap_rate=0.10, term_years=1)

    result = price_fia(product, market; n_paths=5000, seed=42)

    # Present value should be positive
    @test result.present_value > 0

    # Embedded option value should be positive
    @test result.embedded_option_value > 0

    # Expected credit should be non-negative (FIA has 0% floor)
    @test result.expected_credit >= 0

    # Fair cap should be positive
    @test result.fair_cap > 0
end


@testset "FIA Pricing - Participation Style" begin
    market = MarketParams(100.0, 0.05, 0.02, 0.20)
    product = FIAProduct(participation_rate=0.80, term_years=1)

    result = price_fia(product, market; n_paths=5000, seed=42)

    @test result.present_value > 0
    @test result.expected_credit >= 0
    @test result.fair_participation > 0
end


@testset "FIA Fair Terms Relationship" begin
    market = MarketParams(100.0, 0.05, 0.02, 0.20)
    product = FIAProduct(cap_rate=0.10, term_years=1)

    result = price_fia(product, market; n_paths=5000, seed=42)

    # Higher option budget → higher fair cap and participation
    result_high_budget = price_fia(product, market; option_budget_pct=0.05, n_paths=5000, seed=42)
    @test result_high_budget.fair_cap > result.fair_cap
    @test result_high_budget.fair_participation > result.fair_participation
end


@testset "FIA Reproducibility" begin
    market = MarketParams(100.0, 0.05, 0.02, 0.20)
    product = FIAProduct(cap_rate=0.10, term_years=1)

    result1 = price_fia(product, market; n_paths=1000, seed=123)
    result2 = price_fia(product, market; n_paths=1000, seed=123)

    @test result1.expected_credit == result2.expected_credit
end


# =============================================================================
# RILA Pricer Tests
# =============================================================================

@testset "RILA Pricing - Buffer" begin
    market = MarketParams(100.0, 0.05, 0.02, 0.20)
    product = RILAProduct(buffer_rate=0.10, cap_rate=0.20, is_buffer=true, term_years=1)

    result = price_rila(product, market; n_paths=5000, seed=42)

    # Present value should be positive
    @test result.present_value > 0

    # Protection type
    @test result.protection_type == :buffer

    # Protection value should be positive
    @test result.protection_value > 0

    # Breakeven should be -buffer_rate
    @test result.breakeven_return ≈ -0.10

    # Max loss = 1 - buffer_rate
    @test result.max_loss ≈ 0.90
end


@testset "RILA Pricing - Floor" begin
    market = MarketParams(100.0, 0.05, 0.02, 0.20)
    product = RILAProduct(floor_rate=-0.10, cap_rate=0.25, is_buffer=false, term_years=1)

    result = price_rila(product, market; n_paths=5000, seed=42)

    @test result.present_value > 0
    @test result.protection_type == :floor
    @test result.protection_value > 0

    # Breakeven should be 0 for floor
    @test result.breakeven_return ≈ 0.0

    # Max loss = abs(floor_rate)
    @test result.max_loss ≈ 0.10
end


@testset "RILA Buffer vs Floor Protection Value" begin
    market = MarketParams(100.0, 0.05, 0.02, 0.20)

    # Same protection level
    buffer_product = RILAProduct(buffer_rate=0.10, cap_rate=0.20, is_buffer=true, term_years=1)
    floor_product = RILAProduct(floor_rate=-0.10, cap_rate=0.20, is_buffer=false, term_years=1)

    buffer_result = price_rila(buffer_product, market; n_paths=5000, seed=42)
    floor_result = price_rila(floor_product, market; n_paths=5000, seed=42)

    # Buffer protection (put spread) should be worth more than floor (single put)
    @test buffer_result.protection_value > floor_result.protection_value
end


@testset "RILA Compare Buffer vs Floor" begin
    market = MarketParams(100.0, 0.05, 0.02, 0.20)

    comparison = compare_buffer_vs_floor(market, 0.10, -0.10, 0.20, 1; n_paths=5000, seed=42)

    # Both should have valid results
    @test comparison.buffer.present_value > 0
    @test comparison.floor.present_value > 0

    # Buffer max loss > floor max loss
    @test comparison.buffer.max_loss > comparison.floor.max_loss
end


@testset "RILA Greeks" begin
    market = MarketParams(100.0, 0.05, 0.02, 0.20)
    product = RILAProduct(buffer_rate=0.10, cap_rate=0.20, is_buffer=true, term_years=1)

    greeks = rila_greeks(product, market)

    @test greeks.protection_type == :buffer

    # Buffer (put spread) has negative delta (short exposure to spot)
    @test greeks.delta < 0

    # Gamma should be positive
    @test greeks.gamma > 0

    # Vega should be positive (long vol exposure)
    @test greeks.vega > 0
end


@testset "RILA Reproducibility" begin
    market = MarketParams(100.0, 0.05, 0.02, 0.20)
    product = RILAProduct(buffer_rate=0.10, cap_rate=0.20, is_buffer=true, term_years=1)

    result1 = price_rila(product, market; n_paths=1000, seed=123)
    result2 = price_rila(product, market; n_paths=1000, seed=123)

    @test result1.expected_return == result2.expected_return
end


# =============================================================================
# Cross-Product Validation
# =============================================================================

@testset "RILA Expected Return Bounds" begin
    market = MarketParams(100.0, 0.05, 0.02, 0.20)

    # 10% buffer, 20% cap
    product = RILAProduct(buffer_rate=0.10, cap_rate=0.20, is_buffer=true, term_years=1)
    result = price_rila(product, market; n_paths=10000, seed=42)

    # Expected return should be bounded by [-max_loss, cap]
    @test result.expected_return >= -result.max_loss - 0.01  # Small tolerance
    @test result.expected_return <= 0.20 + 0.01  # Cap + tolerance
end


@testset "FIA Expected Credit Bounds" begin
    market = MarketParams(100.0, 0.05, 0.02, 0.20)

    # 10% cap FIA
    product = FIAProduct(cap_rate=0.10, term_years=1)
    result = price_fia(product, market; n_paths=10000, seed=42)

    # Expected credit should be bounded by [0, cap]
    @test result.expected_credit >= -0.01  # FIA floor is 0%
    @test result.expected_credit <= 0.10 + 0.01  # Cap + tolerance
end


@testset "Protection Value vs No-Arbitrage" begin
    market = MarketParams(100.0, 0.05, 0.02, 0.20)

    # 10% buffer RILA
    product = RILAProduct(buffer_rate=0.10, cap_rate=0.20, is_buffer=true, term_years=1)
    result = price_rila(product, market)

    # Protection value should be less than premium
    # (Protection can't be worth more than what you're protecting)
    @test result.protection_value < 100.0
end
