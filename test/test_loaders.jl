"""
Test suite for Data Loaders module.

Tests cover:
- Mortality tables (SOA 2012 IAM, Gompertz, custom)
- Life expectancy and annuity factors
- Yield curves (Nelson-Siegel, flat, custom)
- Discount factors and forward rates
- Risk measures (duration, convexity)
- Interpolation utilities

Cross-validation targets:
- actuarialmath (Python)
- MortalityTables.jl (Julia)
- QuantLib, PyCurve
"""

using Test
using AnnuityCore

# ============================================================================
# Mortality Types Tests
# ============================================================================

@testset "Mortality Types" begin
    @testset "MortalityTable validation" begin
        # Valid table creation
        qx = [0.01, 0.015, 0.02, 0.03, 0.05]
        table = MortalityTable(;
            table_name = "Test",
            min_age = 65,
            max_age = 69,
            qx = qx,
            gender = MALE
        )
        @test table.table_name == "Test"
        @test table.min_age == 65
        @test table.max_age == 69
        @test length(table.qx) == 5
        @test table.gender == MALE

        # Invalid: qx array length mismatch
        @test_throws ErrorException MortalityTable(;
            table_name = "Bad",
            min_age = 65,
            max_age = 69,
            qx = [0.01, 0.02],  # Wrong length
            gender = MALE
        )

        # Invalid: qx out of bounds
        @test_throws ErrorException MortalityTable(;
            table_name = "Bad",
            min_age = 65,
            max_age = 66,
            qx = [0.01, 1.5],  # > 1
            gender = MALE
        )

        # Invalid: qx negative
        @test_throws ErrorException MortalityTable(;
            table_name = "Bad",
            min_age = 65,
            max_age = 66,
            qx = [-0.01, 0.02],  # < 0
            gender = MALE
        )
    end

    @testset "Gender enum" begin
        @test MALE isa Gender
        @test FEMALE isa Gender
        @test UNISEX isa Gender
    end
end

# ============================================================================
# SOA 2012 IAM Data Tests
# ============================================================================

@testset "SOA 2012 IAM Data" begin
    @testset "Data integrity" begin
        # Check male table key points [T1]
        @test SOA_2012_IAM_MALE_QX[0] ≈ 0.00066  # Infant
        @test SOA_2012_IAM_MALE_QX[25] ≈ 0.00088  # Young adult
        @test SOA_2012_IAM_MALE_QX[45] ≈ 0.00235  # Middle age
        @test SOA_2012_IAM_MALE_QX[65] ≈ 0.01680  # Retirement
        @test SOA_2012_IAM_MALE_QX[85] ≈ 0.15249  # Advanced age
        @test SOA_2012_IAM_MALE_QX[100] ≈ 0.66912  # Centenarian
        @test SOA_2012_IAM_MALE_QX[120] ≈ 1.00000  # Terminal

        # Check female table key points [T1]
        @test SOA_2012_IAM_FEMALE_QX[0] ≈ 0.00055
        @test SOA_2012_IAM_FEMALE_QX[65] ≈ 0.01420  # Lower than male
        @test SOA_2012_IAM_FEMALE_QX[120] ≈ 1.00000

        # Female mortality generally lower than male
        @test SOA_2012_IAM_FEMALE_QX[65] < SOA_2012_IAM_MALE_QX[65]
    end

    @testset "Data completeness" begin
        # Full age range 0-120
        @test length(SOA_2012_IAM_MALE_QX) == 121
        @test length(SOA_2012_IAM_FEMALE_QX) == 121

        # All ages present
        for age in 0:120
            @test haskey(SOA_2012_IAM_MALE_QX, age)
            @test haskey(SOA_2012_IAM_FEMALE_QX, age)
        end
    end

    @testset "Key points validation" begin
        # Verify key points dict matches main dict
        for (age, qx) in SOA_2012_IAM_MALE_KEY_POINTS
            @test SOA_2012_IAM_MALE_QX[age] ≈ qx
        end
        for (age, qx) in SOA_2012_IAM_FEMALE_KEY_POINTS
            @test SOA_2012_IAM_FEMALE_QX[age] ≈ qx
        end
    end

    @testset "Table ID mapping" begin
        @test SOA_TABLE_IDS[3302] == "SOA 2012 IAM Basic - Male"
        @test SOA_TABLE_IDS[3303] == "SOA 2012 IAM Basic - Female"
    end

    @testset "Vector conversion" begin
        male_qx = get_soa_2012_iam_qx_vector(MALE)
        female_qx = get_soa_2012_iam_qx_vector(FEMALE)

        @test length(male_qx) == 121
        @test length(female_qx) == 121
        @test male_qx[1] ≈ 0.00066  # Age 0 (1-indexed)
        @test male_qx[66] ≈ 0.01680  # Age 65 (66th element)

        age_range = get_soa_2012_iam_age_range()
        @test age_range.min_age == 0
        @test age_range.max_age == 120
    end
end

# ============================================================================
# Mortality Table Loading Tests
# ============================================================================

@testset "Mortality Table Loading" begin
    @testset "soa_2012_iam" begin
        # Default (male)
        table = soa_2012_iam()
        @test table.gender == MALE
        @test table.min_age == 0
        @test table.max_age == 120

        # Female
        table_f = soa_2012_iam(gender = FEMALE)
        @test table_f.gender == FEMALE

        # Verify loaded values match raw data
        @test get_qx(table, 65) ≈ 0.01680
        @test get_qx(table_f, 65) ≈ 0.01420
    end

    @testset "soa_table by ID" begin
        @test soa_table(3302).gender == MALE
        @test soa_table(3303).gender == FEMALE
        @test_throws ErrorException soa_table(9999)  # Invalid ID
    end

    @testset "gompertz_table" begin
        table = gompertz_table(a = 0.0001, b = 0.08)

        # Gompertz: qx = a * exp(b * age)
        @test get_qx(table, 0) ≈ 0.0001 atol = 1e-6
        @test get_qx(table, 65) ≈ 0.0001 * exp(0.08 * 65) atol = 1e-4

        # Should be capped at 1
        @test get_qx(table, 120) <= 1.0

        # Parameters validation
        @test_throws ErrorException gompertz_table(a = -0.01, b = 0.08)  # Negative a
        @test_throws ErrorException gompertz_table(a = 0.01, b = -0.08)  # Negative b
    end

    @testset "from_dict" begin
        qx_dict = Dict(65 => 0.02, 66 => 0.022, 67 => 0.025, 68 => 0.028, 69 => 0.032)
        table = from_dict(qx_dict; table_name = "Custom")

        @test table.min_age == 65
        @test table.max_age == 69
        @test get_qx(table, 65) ≈ 0.02
        @test get_qx(table, 69) ≈ 0.032
    end
end

# ============================================================================
# Mortality Functions Tests
# ============================================================================

@testset "Mortality Functions" begin
    table = soa_2012_iam()

    @testset "get_qx bounds" begin
        # Valid ages
        @test 0.0 <= get_qx(table, 0) <= 1.0
        @test 0.0 <= get_qx(table, 65) <= 1.0
        @test get_qx(table, 120) == 1.0

        # Beyond max age
        @test get_qx(table, 130) == 1.0

        # Below min age
        @test_throws ErrorException get_qx(table, -1)
    end

    @testset "get_px" begin
        @test get_px(table, 65) ≈ 1.0 - get_qx(table, 65)
        @test get_px(table, 65) > 0.98  # High survival at 65
        @test get_px(table, 100) < 0.5  # Lower at advanced age
    end

    @testset "npx" begin
        # 0-year survival is 1
        @test npx(table, 65, 0) ≈ 1.0

        # 1-year survival equals px
        @test npx(table, 65, 1) ≈ get_px(table, 65)

        # Multi-year survival decreases
        @test npx(table, 65, 10) < npx(table, 65, 5)
        @test npx(table, 65, 20) < npx(table, 65, 10)

        # Very long survival approaches 0
        @test npx(table, 65, 60) < 0.01
    end

    @testset "nqx" begin
        # nqx = 1 - npx
        @test nqx(table, 65, 10) ≈ 1.0 - npx(table, 65, 10)
        @test nqx(table, 65, 0) ≈ 0.0
    end

    @testset "life_expectancy" begin
        # Curtate life expectancy at 65 for male (SOA 2012 IAM)
        # Note: Curtate LE is typically ~15 years, complete LE adds ~0.5
        ex_65 = life_expectancy(table, 65)
        @test 13.0 < ex_65 < 20.0  # Reasonable range for curtate LE

        # Life expectancy decreases with age
        @test life_expectancy(table, 75) < life_expectancy(table, 65)
        @test life_expectancy(table, 85) < life_expectancy(table, 75)

        # At terminal age
        @test life_expectancy(table, 120) ≈ 0.0 atol = 0.1

        # Female has higher life expectancy
        table_f = soa_2012_iam(gender = FEMALE)
        @test life_expectancy(table_f, 65) > life_expectancy(table, 65)
    end

    @testset "complete_life_expectancy" begin
        # Complete ≈ curtate + 0.5
        @test complete_life_expectancy(table, 65) ≈ life_expectancy(table, 65) + 0.5
    end

    @testset "lx and dx" begin
        # lx at min_age equals radix
        @test lx(table, 0) ≈ 100_000

        # lx decreases with age
        @test lx(table, 65) < lx(table, 0)
        @test lx(table, 85) < lx(table, 65)

        # dx = lx * qx
        @test dx(table, 65) ≈ lx(table, 65) * get_qx(table, 65)

        # Custom radix
        @test lx(table, 0; radix = 1_000_000) ≈ 1_000_000
    end

    @testset "annuity_factor" begin
        # At high interest rate, factor is lower
        af_4pct = annuity_factor(table, 65, 0.04)
        af_8pct = annuity_factor(table, 65, 0.08)
        @test af_4pct > af_8pct

        # Reasonable range for life annuity at 65 with 4%
        # Factor is discounted life expectancy
        @test 10.0 < af_4pct < 15.0

        # Term annuity is less than life annuity
        af_10yr = annuity_factor(table, 65, 0.04; n = 10)
        @test af_10yr < af_4pct

        # Immediate factor is less than due by ~1
        af_imm = annuity_immediate_factor(table, 65, 0.04)
        @test af_imm ≈ af_4pct - 1.0 atol = 0.01
    end

    @testset "calculate_annuity_pv" begin
        # PV = payment × factor
        pv = calculate_annuity_pv(table, 65, 10_000.0, 0.04)
        af = annuity_factor(table, 65, 0.04)
        @test pv ≈ 10_000.0 * af

        # Annuity immediate has lower PV
        pv_imm = calculate_annuity_pv(table, 65, 10_000.0, 0.04; timing = :end)
        @test pv_imm < pv
    end
end

# ============================================================================
# Mortality Table Transformations Tests
# ============================================================================

@testset "Mortality Transformations" begin
    table = soa_2012_iam()

    @testset "with_improvement" begin
        improved = with_improvement(table, 0.01, 10)

        # Improved mortality is lower
        @test get_qx(improved, 65) < get_qx(table, 65)

        # Improvement factor: (1 - 0.01)^10
        factor = (1 - 0.01)^10
        @test get_qx(improved, 65) ≈ get_qx(table, 65) * factor atol = 1e-6

        # Zero improvement returns same table
        no_improvement = with_improvement(table, 0.01, 0)
        @test get_qx(no_improvement, 65) ≈ get_qx(table, 65)
    end

    @testset "blend_tables" begin
        male = soa_2012_iam(gender = MALE)
        female = soa_2012_iam(gender = FEMALE)

        # 50/50 blend
        blended = blend_tables(male, female, 0.5)
        @test blended.gender == UNISEX

        # Blended mortality is average
        expected = 0.5 * get_qx(male, 65) + 0.5 * get_qx(female, 65)
        @test get_qx(blended, 65) ≈ expected

        # Full weight to male
        male_only = blend_tables(male, female, 1.0)
        @test get_qx(male_only, 65) ≈ get_qx(male, 65)
    end

    @testset "validate_mortality_table" begin
        result = validate_mortality_table(table)
        @test result.valid
        @test isempty(result.issues)
        @test 13.0 < result.life_exp_65 < 20.0  # Curtate LE
    end
end

# ============================================================================
# Yield Curve Types Tests
# ============================================================================

@testset "Yield Curve Types" begin
    @testset "YieldCurve validation" begin
        # Valid curve
        curve = YieldCurve(;
            maturities = [1.0, 2.0, 5.0, 10.0],
            rates = [0.03, 0.035, 0.04, 0.045],
            as_of_date = "2024-01-15",
            curve_type = "test"
        )
        @test length(curve.maturities) == 4
        @test curve.interpolation == LINEAR

        # Invalid: length mismatch
        @test_throws ErrorException YieldCurve(;
            maturities = [1.0, 2.0],
            rates = [0.03, 0.035, 0.04]
        )

        # Invalid: empty
        @test_throws ErrorException YieldCurve(;
            maturities = Float64[],
            rates = Float64[]
        )

        # Invalid: non-increasing maturities
        @test_throws ErrorException YieldCurve(;
            maturities = [2.0, 1.0, 3.0],
            rates = [0.03, 0.035, 0.04]
        )
    end

    @testset "NelsonSiegelParams" begin
        params = NelsonSiegelParams(;
            beta0 = 0.04,
            beta1 = -0.02,
            beta2 = 0.01,
            tau = 2.0
        )
        @test params.beta0 == 0.04
        @test params.tau == 2.0

        # Invalid: non-positive tau
        @test_throws ErrorException NelsonSiegelParams(;
            beta0 = 0.04, beta1 = -0.02, beta2 = 0.01, tau = 0.0
        )
    end

    @testset "InterpolationMethod" begin
        @test LINEAR isa InterpolationMethod
        @test LOG_LINEAR isa InterpolationMethod
        @test CUBIC isa InterpolationMethod
    end
end

# ============================================================================
# Yield Curve Loading Tests
# ============================================================================

@testset "Yield Curve Loading" begin
    @testset "flat_curve" begin
        curve = flat_curve(0.04)
        @test curve.curve_type == "flat"

        # All rates should be the same
        @test get_rate(curve, 1.0) ≈ 0.04
        @test get_rate(curve, 10.0) ≈ 0.04
        @test get_rate(curve, 30.0) ≈ 0.04
    end

    @testset "from_points" begin
        mats = [1.0, 2.0, 5.0, 10.0]
        rates = [0.03, 0.035, 0.04, 0.045]
        curve = from_points(mats, rates)

        @test get_rate(curve, 1.0) ≈ 0.03
        @test get_rate(curve, 10.0) ≈ 0.045

        # Interpolated points
        r_3y = get_rate(curve, 3.0)
        @test 0.035 < r_3y < 0.04
    end

    @testset "from_nelson_siegel" begin
        curve = from_nelson_siegel(0.04, -0.02, 0.01, 2.0)
        @test curve.curve_type == "nelson_siegel"

        # Short rate: β0 + β1 = 0.04 - 0.02 = 0.02
        short_r = get_rate(curve, 0.01)  # Very short term
        @test short_r < 0.04  # Below long rate (upward sloping)

        # Long rate approaches β0 = 0.04
        long_r = get_rate(curve, 30.0)
        @test long_r > short_r
        @test abs(long_r - 0.04) < 0.01  # Close to β0
    end

    @testset "upward_sloping_curve" begin
        curve = upward_sloping_curve(0.02, 0.05)

        @test get_rate(curve, 1.0) > get_rate(curve, 0.25)
        @test get_rate(curve, 30.0) > get_rate(curve, 10.0)
    end

    @testset "inverted_curve" begin
        curve = inverted_curve(0.05, 0.02)

        # Short rate higher than long rate
        @test get_rate(curve, 1.0) > get_rate(curve, 30.0)
    end
end

# ============================================================================
# Yield Curve Functions Tests
# ============================================================================

@testset "Yield Curve Functions" begin
    curve = from_points([1.0, 2.0, 5.0, 10.0], [0.03, 0.035, 0.04, 0.045])

    @testset "get_rate" begin
        # Exact points
        @test get_rate(curve, 1.0) ≈ 0.03
        @test get_rate(curve, 10.0) ≈ 0.045

        # Interpolated
        r_3y = get_rate(curve, 3.0)
        @test 0.035 < r_3y < 0.04

        # Extrapolation (flat)
        @test get_rate(curve, 0.5) ≈ 0.03  # Below min
        @test get_rate(curve, 20.0) ≈ 0.045  # Above max

        # Invalid: non-positive maturity
        @test_throws ErrorException get_rate(curve, 0.0)
        @test_throws ErrorException get_rate(curve, -1.0)
    end

    @testset "discount_factor" begin
        # P(t) = exp(-r(t) × t)
        df_5 = discount_factor(curve, 5.0)
        r_5 = get_rate(curve, 5.0)
        @test df_5 ≈ exp(-r_5 * 5.0)

        # Discount factor at t=0 is 1
        @test discount_factor(curve, 0.0) ≈ 1.0

        # Discount factors decrease with maturity
        @test discount_factor(curve, 10.0) < discount_factor(curve, 5.0)
        @test discount_factor(curve, 5.0) < discount_factor(curve, 1.0)
    end

    @testset "discount_factors (vector)" begin
        mats = [1.0, 2.0, 5.0]
        dfs = discount_factors(curve, mats)

        @test length(dfs) == 3
        @test dfs[1] ≈ discount_factor(curve, 1.0)
        @test dfs[3] ≈ discount_factor(curve, 5.0)
    end

    @testset "forward_rate" begin
        # f(t1,t2) = (r2*t2 - r1*t1) / (t2-t1)
        fwd_1_2 = forward_rate(curve, 1.0, 2.0)
        r1 = get_rate(curve, 1.0)
        r2 = get_rate(curve, 2.0)
        expected = (r2 * 2.0 - r1 * 1.0) / (2.0 - 1.0)
        @test fwd_1_2 ≈ expected

        # Forward from spot
        fwd_0_5 = forward_rate(curve, 0.0, 5.0)
        @test fwd_0_5 ≈ get_rate(curve, 5.0)

        # Invalid: t2 <= t1
        @test_throws ErrorException forward_rate(curve, 5.0, 5.0)
        @test_throws ErrorException forward_rate(curve, 5.0, 2.0)
    end

    @testset "par_rate" begin
        # For flat curve, par rate ≈ zero rate
        flat = flat_curve(0.04)
        pr = par_rate(flat, 10.0)
        @test abs(pr - 0.04) < 0.005  # Close to 4%

        # Par rate exists for upward sloping curve
        @test par_rate(curve, 5.0) > 0.0
    end
end

# ============================================================================
# Nelson-Siegel Rate Tests
# ============================================================================

@testset "Nelson-Siegel Model" begin
    params = NelsonSiegelParams(beta0 = 0.04, beta1 = -0.02, beta2 = 0.01, tau = 2.0)

    @testset "Rate calculation" begin
        # Short rate (t→0): β0 + β1 = 0.02
        short_rate = nelson_siegel_rate(params, 0.001)
        @test abs(short_rate - 0.02) < 0.01

        # Long rate (t→∞): β0 = 0.04
        long_rate = nelson_siegel_rate(params, 100.0)
        @test abs(long_rate - 0.04) < 0.001

        # At t=0 exactly
        @test nelson_siegel_rate(params, 0.0) ≈ 0.02  # β0 + β1
    end

    @testset "Curve shapes" begin
        # Upward sloping: β1 < 0
        upward = NelsonSiegelParams(beta0 = 0.04, beta1 = -0.02, beta2 = 0.0, tau = 2.0)
        @test nelson_siegel_rate(upward, 10.0) > nelson_siegel_rate(upward, 1.0)

        # Flat: β1 = β2 = 0
        flat_ns = NelsonSiegelParams(beta0 = 0.04, beta1 = 0.0, beta2 = 0.0, tau = 2.0)
        @test nelson_siegel_rate(flat_ns, 1.0) ≈ 0.04
        @test nelson_siegel_rate(flat_ns, 10.0) ≈ 0.04

        # Inverted: β1 > 0
        inverted_ns = NelsonSiegelParams(beta0 = 0.04, beta1 = 0.02, beta2 = 0.0, tau = 2.0)
        @test nelson_siegel_rate(inverted_ns, 10.0) < nelson_siegel_rate(inverted_ns, 1.0)

        # Humped: β2 ≠ 0
        humped = NelsonSiegelParams(beta0 = 0.04, beta1 = -0.02, beta2 = 0.03, tau = 2.0)
        mid_rate = nelson_siegel_rate(humped, 2.0)  # Near hump
        short_rate_h = nelson_siegel_rate(humped, 0.5)
        long_rate_h = nelson_siegel_rate(humped, 10.0)
        # Hump should create local maximum
        @test mid_rate >= min(short_rate_h, long_rate_h)
    end
end

# ============================================================================
# Curve Transformations Tests
# ============================================================================

@testset "Curve Transformations" begin
    base = from_points([1.0, 5.0, 10.0], [0.03, 0.04, 0.045])

    @testset "shift_curve" begin
        shifted = shift_curve(base, 0.01)  # +100bps

        @test get_rate(shifted, 1.0) ≈ get_rate(base, 1.0) + 0.01
        @test get_rate(shifted, 10.0) ≈ get_rate(base, 10.0) + 0.01
    end

    @testset "steepen_curve" begin
        # Short end down, long end up
        steepened = steepen_curve(base, -0.01, 0.01)

        @test get_rate(steepened, 1.0) < get_rate(base, 1.0)
        @test get_rate(steepened, 10.0) > get_rate(base, 10.0)
    end

    @testset "scale_curve" begin
        scaled = scale_curve(base, 1.5)  # +50%

        @test get_rate(scaled, 5.0) ≈ get_rate(base, 5.0) * 1.5

        # Invalid: non-positive factor
        @test_throws ErrorException scale_curve(base, 0.0)
    end
end

# ============================================================================
# Risk Measures Tests
# ============================================================================

@testset "Risk Measures" begin
    curve = flat_curve(0.04)

    # 5% coupon bond, 5-year maturity
    cash_flows = [5.0, 5.0, 5.0, 5.0, 105.0]
    times = [1.0, 2.0, 3.0, 4.0, 5.0]

    @testset "present_value" begin
        pv = present_value(curve, cash_flows, times)

        # Manual calculation
        manual_pv = sum(cf * exp(-0.04 * t) for (cf, t) in zip(cash_flows, times))
        @test pv ≈ manual_pv
    end

    @testset "macaulay_duration" begin
        mac_dur = macaulay_duration(curve, cash_flows, times)

        # Duration < maturity for coupon bond
        @test mac_dur < 5.0
        # Duration > 0
        @test mac_dur > 0.0
        # For 5% coupon, 5yr bond at 4%, duration ~4.5 years
        @test 4.0 < mac_dur < 5.0
    end

    @testset "modified_duration" begin
        mod_dur = modified_duration(curve, cash_flows, times)
        mac_dur = macaulay_duration(curve, cash_flows, times)

        # Modified < Macaulay
        @test mod_dur < mac_dur
    end

    @testset "dv01" begin
        dv01_val = dv01(curve, cash_flows, times)

        # DV01 > 0
        @test dv01_val > 0

        # DV01 ≈ PV × Mod_Dur × 0.0001
        pv = present_value(curve, cash_flows, times)
        mod_dur = modified_duration(curve, cash_flows, times)
        @test dv01_val ≈ pv * mod_dur * 0.0001 atol = 0.1
    end

    @testset "convexity" begin
        conv = convexity(curve, cash_flows, times)

        # Convexity > 0
        @test conv > 0

        # Convexity provides second-order correction
        @test conv > macaulay_duration(curve, cash_flows, times)
    end

    @testset "annuity_pv" begin
        # Level annuity: $100/year, 10 years, quarterly
        ann_pv = annuity_pv(curve, 25.0, 40, 4)  # $25/quarter, 40 quarters

        # Should be less than undiscounted sum
        @test ann_pv < 25.0 * 40
        @test ann_pv > 0
    end
end

# ============================================================================
# Validation Tests
# ============================================================================

@testset "Validation" begin
    @testset "validate_yield_curve" begin
        # Valid upward-sloping curve
        valid_curve = from_points([1.0, 5.0, 10.0], [0.03, 0.04, 0.045])
        result = validate_yield_curve(valid_curve)
        @test result.valid

        # Curve summary
        summary = curve_summary(valid_curve)
        @test summary.slope == :upward
        @test summary.n_points == 3
    end
end

# ============================================================================
# Interpolation Utilities Tests
# ============================================================================

@testset "Interpolation Utilities" begin
    xs = [1.0, 2.0, 3.0, 4.0, 5.0]
    ys = [10.0, 20.0, 30.0, 40.0, 50.0]

    @testset "linear_interp" begin
        # Exact points
        @test linear_interp(1.0, xs, ys) ≈ 10.0
        @test linear_interp(3.0, xs, ys) ≈ 30.0

        # Midpoint
        @test linear_interp(1.5, xs, ys) ≈ 15.0
        @test linear_interp(2.5, xs, ys) ≈ 25.0

        # Extrapolation (flat)
        @test linear_interp(0.5, xs, ys) ≈ 10.0  # Below
        @test linear_interp(6.0, xs, ys) ≈ 50.0  # Above
    end

    @testset "log_linear_interp" begin
        # Discount factors (positive)
        dfs = [0.98, 0.95, 0.90, 0.85, 0.80]

        # Log-linear preserves arbitrage-free property
        result = log_linear_interp(2.5, xs, dfs)
        @test 0.90 < result < 0.95
    end

    @testset "cubic_interp" begin
        # Should match linear for simple cases
        result = cubic_interp(2.5, xs, ys)
        @test 20.0 < result < 30.0
    end

    @testset "interpolate dispatcher" begin
        @test interpolate(2.5, xs, ys, LINEAR) ≈ linear_interp(2.5, xs, ys)
    end

    @testset "interpolate_vector" begin
        new_xs = [1.5, 2.5, 3.5]
        results = interpolate_vector(new_xs, xs, ys)
        @test length(results) == 3
        @test results[1] ≈ 15.0
        @test results[2] ≈ 25.0
        @test results[3] ≈ 35.0
    end

    @testset "extrapolation" begin
        # Flat extrapolation
        @test extrapolate_flat(0.0, xs, ys) ≈ 10.0
        @test extrapolate_flat(10.0, xs, ys) ≈ 50.0

        # Linear extrapolation
        lin_below = extrapolate_linear(0.0, xs, ys)
        @test lin_below < 10.0  # Extrapolates below

        lin_above = extrapolate_linear(6.0, xs, ys)
        @test lin_above > 50.0  # Extrapolates above
    end
end

# ============================================================================
# Treasury Data Tests
# ============================================================================

@testset "Treasury Data" begin
    @testset "Standard maturities" begin
        @test length(TREASURY_MATURITIES) == 12

        # Contains key maturities
        @test 1/12 in TREASURY_MATURITIES  # 1 month
        @test 1.0 in TREASURY_MATURITIES   # 1 year
        @test 10.0 in TREASURY_MATURITIES  # 10 year
        @test 30.0 in TREASURY_MATURITIES  # 30 year
    end

    @testset "FRED series mapping" begin
        @test FRED_TREASURY_SERIES[1/12] == "DGS1MO"
        @test FRED_TREASURY_SERIES[1.0] == "DGS1"
        @test FRED_TREASURY_SERIES[10.0] == "DGS10"
        @test FRED_TREASURY_SERIES[30.0] == "DGS30"
    end
end

# ============================================================================
# Integration Tests
# ============================================================================

@testset "Integration Tests" begin
    @testset "Mortality + Yield Curve: Annuity pricing" begin
        table = soa_2012_iam()
        curve = flat_curve(0.04)

        # Life annuity pricing using both mortality and curve
        age = 65
        payment = 10_000.0

        # Method 1: Using mortality annuity_factor (single rate)
        af = annuity_factor(table, age, 0.04)
        pv_method1 = payment * af

        # Method 2: Year-by-year using curve
        max_years = 121 - age  # to omega
        pv_method2 = 0.0
        for k in 0:(max_years - 1)
            survival = npx(table, age, k)
            df = discount_factor(curve, Float64(k))
            pv_method2 += payment * survival * df
        end

        # Both methods should give similar results
        @test abs(pv_method1 - pv_method2) / pv_method1 < 0.05  # Within 5%
    end

    @testset "Cross-module consistency" begin
        # Verify Loaders module provides accurate SOA 2012 IAM data
        # Note: GLWB module uses Gompertz approximation, not full SOA tables
        table = soa_2012_iam()
        loader_qx = get_qx(table, 65)

        # Should match embedded SOA data exactly
        @test loader_qx ≈ SOA_2012_IAM_MALE_QX[65]
        @test loader_qx ≈ 0.0168 atol = 0.0001
    end
end

# ============================================================================
# Anti-Pattern Tests
# ============================================================================

@testset "Anti-Pattern Tests" begin
    @testset "Mortality bounds" begin
        table = soa_2012_iam()

        # qx must be in [0, 1]
        for age in 0:120
            qx = get_qx(table, age)
            @test 0.0 <= qx <= 1.0
        end
    end

    @testset "Life expectancy positive" begin
        table = soa_2012_iam()

        for age in 0:119
            ex = life_expectancy(table, age)
            @test ex >= 0.0
        end
    end

    @testset "Discount factor bounds" begin
        curve = flat_curve(0.04)

        # Discount factor at t=0 is 1
        @test discount_factor(curve, 0.0) ≈ 1.0

        # Discount factors are positive and ≤ 1
        for t in [0.1, 1.0, 5.0, 10.0, 30.0]
            df = discount_factor(curve, t)
            @test 0.0 < df <= 1.0
        end

        # Discount factors decrease with maturity (for positive rates)
        for t in 1.0:5.0:25.0
            @test discount_factor(curve, t + 5.0) < discount_factor(curve, t)
        end
    end

    @testset "Forward rate arbitrage-free" begin
        curve = from_points([1.0, 2.0, 5.0, 10.0], [0.03, 0.035, 0.04, 0.045])

        # Forward rates should be consistent with spot rates
        # P(t2) = P(t1) × exp(-f(t1,t2) × (t2-t1))
        for (t1, t2) in [(1.0, 2.0), (2.0, 5.0), (5.0, 10.0)]
            df1 = discount_factor(curve, t1)
            df2 = discount_factor(curve, t2)
            fwd = forward_rate(curve, t1, t2)

            implied_df2 = df1 * exp(-fwd * (t2 - t1))
            @test df2 ≈ implied_df2 atol = 1e-10
        end
    end
end
