"""
Tests for Behavioral Models (Dynamic Lapse, Withdrawal Utilization, Expenses).

[T2] Validates calibration against SOA 2006 Deferred Annuity Persistency Study
     and SOA 2018 VA GLB Utilization Study.
"""

using Test
using AnnuityCore

@testset "Behavioral Models" begin

    # =========================================================================
    # SOA Data Validation [T2]
    # =========================================================================
    @testset "SOA Data Constants" begin
        @testset "SOA 2006 Surrender by Duration" begin
            # Verify key data points from SOA 2006 Table 6
            @test SOA_2006_SURRENDER_BY_DURATION_7YR_SC[1] == 0.014   # Year 1: 1.4%
            @test SOA_2006_SURRENDER_BY_DURATION_7YR_SC[8] == 0.112   # Year 8 cliff: 11.2%
            @test SOA_2006_SURRENDER_BY_DURATION_7YR_SC[11] == 0.067  # Year 11: 6.7%

            # SC cliff multiplier should be ~2.48
            @test 2.4 < SOA_2006_SC_CLIFF_MULTIPLIER < 2.5
        end

        @testset "SOA 2018 GLWB Utilization" begin
            # Verify key data points from SOA 2018 Table 1-17
            @test SOA_2018_GLWB_UTILIZATION_BY_DURATION[1] == 0.111   # Year 1: 11.1%
            @test SOA_2018_GLWB_UTILIZATION_BY_DURATION[10] == 0.518  # Year 10: 51.8%

            # ITM sensitivity should increase with moneyness
            @test SOA_2018_ITM_SENSITIVITY[:not_itm] == 1.0
            @test SOA_2018_ITM_SENSITIVITY[:itm_100_125] > 1.0
            @test SOA_2018_ITM_SENSITIVITY[:itm_150_plus] > SOA_2018_ITM_SENSITIVITY[:itm_125_150]
        end
    end


    # =========================================================================
    # Interpolation Functions
    # =========================================================================
    @testset "Interpolation Functions" begin
        @testset "linear_interpolate" begin
            points = Dict(1 => 0.1, 5 => 0.5, 10 => 0.8)

            # Exact points
            @test linear_interpolate(1, points) == 0.1
            @test linear_interpolate(5, points) == 0.5

            # Interpolated
            @test linear_interpolate(3, points) ≈ 0.3 atol=1e-10

            # Extrapolation (clamps to boundary)
            @test linear_interpolate(0, points) == 0.1
            @test linear_interpolate(15, points) == 0.8
        end

        @testset "interpolate_surrender_by_duration" begin
            # Exact SOA data points
            @test interpolate_surrender_by_duration(1) == 0.014
            @test interpolate_surrender_by_duration(8) == 0.112  # Cliff

            # Interpolated value between data points
            rate_4_5 = interpolate_surrender_by_duration(4)
            @test 0.028 < rate_4_5 < 0.037  # Between year 3 and year 5

            # Monotonically increasing during SC period (years 1-7)
            for y in 1:6
                @test interpolate_surrender_by_duration(y) < interpolate_surrender_by_duration(y+1)
            end
        end

        @testset "get_sc_cliff_multiplier" begin
            # Base rate (3+ years remaining)
            @test get_sc_cliff_multiplier(5) == 1.0
            @test get_sc_cliff_multiplier(3) == 1.0

            # Cliff multiplier at expiration
            cliff_mult = get_sc_cliff_multiplier(0)
            @test 2.4 < cliff_mult < 2.5  # ~2.48

            # Increasing as SC approaches
            @test get_sc_cliff_multiplier(2) < get_sc_cliff_multiplier(1) ||
                  get_sc_cliff_multiplier(2) > 1.0
        end

        @testset "interpolate_utilization_by_duration" begin
            # SOA 2018 data points
            @test interpolate_utilization_by_duration(1) == 0.111
            @test interpolate_utilization_by_duration(10) == 0.518

            # Monotonically increasing
            for d in 1:10
                @test interpolate_utilization_by_duration(d) <= interpolate_utilization_by_duration(d+1)
            end
        end

        @testset "get_itm_sensitivity_factor" begin
            # OTM/ATM baseline
            @test get_itm_sensitivity_factor(0.9) == 1.0
            @test get_itm_sensitivity_factor(1.0) == 1.0

            # ITM increases factor
            @test get_itm_sensitivity_factor(1.1) > 1.0
            @test get_itm_sensitivity_factor(1.3) > get_itm_sensitivity_factor(1.1)
            @test get_itm_sensitivity_factor(1.6) > get_itm_sensitivity_factor(1.3)

            # Continuous vs discrete
            continuous = get_itm_sensitivity_factor(1.15; continuous=true)
            @test 1.0 < continuous < 1.39  # Smooth between breakpoints
        end
    end


    # =========================================================================
    # Lapse Models
    # =========================================================================
    @testset "Lapse Models" begin
        @testset "LapseConfig - Simple Model" begin
            config = LapseConfig(base_annual_lapse=0.05, moneyness_sensitivity=1.0)

            # ATM case with surrender period complete: moneyness = 1.0, factor = 1.0
            result = calculate_lapse(config, 100_000.0, 100_000.0; surrender_period_complete=true)
            @test result.lapse_rate ≈ 0.05 atol=1e-6

            # ITM guarantee (GWB > AV): lower lapse (moneyness = AV/GWB < 1)
            result_itm = calculate_lapse(config, 110_000.0, 100_000.0; surrender_period_complete=true)
            @test result_itm.lapse_rate < 0.05
            @test result_itm.moneyness ≈ 100_000.0 / 110_000.0

            # OTM guarantee (GWB < AV): higher lapse (moneyness = AV/GWB > 1)
            result_otm = calculate_lapse(config, 90_000.0, 100_000.0; surrender_period_complete=true)
            @test result_otm.lapse_rate > 0.05

            # Surrender period reduces lapse (default is false)
            result_sc = calculate_lapse(config, 100_000.0, 100_000.0; surrender_period_complete=false)
            result_post_sc = calculate_lapse(config, 100_000.0, 100_000.0; surrender_period_complete=true)
            @test result_sc.lapse_rate < result_post_sc.lapse_rate
        end

        @testset "SOALapseConfig - SOA 2006 Calibration" begin
            config = SOALapseConfig(surrender_charge_length=7, use_duration_curve=true)

            # Year 1 should be low
            result_y1 = calculate_lapse(config, 100_000.0, 100_000.0, 1, 6)
            @test result_y1.lapse_rate ≈ 0.014 atol=0.001

            # Year 8 (cliff) should be high
            result_y8 = calculate_lapse(config, 100_000.0, 100_000.0, 8, 0)
            @test result_y8.lapse_rate > 0.10

            # Duration curve should be monotonic during SC
            rates = [calculate_lapse(config, 100_000.0, 100_000.0, y, 8-y).lapse_rate for y in 1:7]
            for i in 1:6
                @test rates[i] <= rates[i+1]
            end
        end

        @testset "Lapse Bounds" begin
            config = LapseConfig(min_lapse=0.01, max_lapse=0.25)

            # Should respect bounds
            result = calculate_lapse(config, 100_000.0, 100_000.0)
            @test 0.01 <= result.lapse_rate <= 0.25

            # Extreme ITM should hit floor
            result_deep_itm = calculate_lapse(config, 200_000.0, 100_000.0)
            @test result_deep_itm.lapse_rate >= 0.01

            # Extreme OTM should hit cap
            config_high_sens = LapseConfig(base_annual_lapse=0.10, moneyness_sensitivity=3.0, max_lapse=0.25)
            result_deep_otm = calculate_lapse(config_high_sens, 50_000.0, 100_000.0)
            @test result_deep_otm.lapse_rate <= 0.25
        end

        @testset "calculate_path_lapses" begin
            config = LapseConfig(base_annual_lapse=0.05)
            gwb_path = [100_000.0, 100_000.0, 100_000.0, 100_000.0, 100_000.0]
            av_path = [100_000.0, 105_000.0, 110_000.0, 90_000.0, 80_000.0]

            # Test without surrender period (all post-SC)
            rates = calculate_path_lapses(config, gwb_path, av_path; surrender_period_ends=0)

            # Should have one rate per time step
            @test length(rates) == 5

            # Rates should vary with moneyness (AV/GWB):
            # Higher AV (OTM guarantee) → higher lapse rate
            # Lower AV (ITM guarantee) → lower lapse rate
            @test rates[2] > rates[1]  # AV increased 100k → 105k (OTM)
            @test rates[3] > rates[2]  # AV increased 105k → 110k (more OTM)
            @test rates[5] < rates[3]  # AV decreased 110k → 80k (now ITM)

            # Test with surrender period (demonstrates SC effect)
            rates_with_sc = calculate_path_lapses(config, gwb_path, av_path; surrender_period_ends=3)
            @test rates_with_sc[1] < rates[1]  # In SC period → lower rate
            @test rates_with_sc[4] == rates[4]  # Post SC period → same rate
        end

        @testset "survival_from_lapses" begin
            lapse_rates = [0.05, 0.05, 0.10, 0.08]
            survival = survival_from_lapses(lapse_rates)

            @test length(survival) == 4
            @test survival[1] ≈ 0.95 atol=1e-10
            @test survival[2] ≈ 0.95 * 0.95 atol=1e-10
            @test all(diff(survival) .<= 0)  # Monotonically decreasing
        end

        @testset "Input Validation" begin
            config = LapseConfig()
            @test_throws ArgumentError calculate_lapse(config, 100_000.0, -1.0)  # Negative AV
            @test_throws ArgumentError calculate_lapse(config, -1.0, 100_000.0)  # Negative GWB
        end
    end


    # =========================================================================
    # Withdrawal Models
    # =========================================================================
    @testset "Withdrawal Models" begin
        @testset "WithdrawalConfig - Simple Model" begin
            config = WithdrawalConfig(base_utilization=0.50, age_sensitivity=0.02)

            # Base case at age 65
            result = calculate_withdrawal(config, 100_000.0, 100_000.0, 0.05, 65)
            @test result.utilization_rate ≈ 0.50 atol=1e-6
            @test result.max_allowed == 5_000.0  # 5% of GWB

            # Older age → higher utilization
            result_75 = calculate_withdrawal(config, 100_000.0, 100_000.0, 0.05, 75)
            @test result_75.utilization_rate > result.utilization_rate
        end

        @testset "SOAWithdrawalConfig - SOA 2018 Calibration" begin
            config = SOAWithdrawalConfig(
                use_duration_curve=true,
                use_age_curve=true,
                use_itm_sensitivity=true
            )

            # Year 1, age 65 should show lower utilization
            result_y1 = calculate_withdrawal(config, 100_000.0, 100_000.0, 0.05, 1, 65)
            @test result_y1.duration_factor < 0.20  # ~11.1% for year 1

            # Year 10, age 70 should show higher utilization
            result_y10 = calculate_withdrawal(config, 100_000.0, 100_000.0, 0.05, 10, 70)
            @test result_y10.duration_factor > 0.45  # ~51.8% for year 10

            # ITM should increase utilization
            result_itm = calculate_withdrawal(config, 120_000.0, 100_000.0, 0.05, 5, 70; moneyness=1.2)
            result_otm = calculate_withdrawal(config, 100_000.0, 120_000.0, 0.05, 5, 70; moneyness=0.83)
            @test result_itm.utilization_rate > result_otm.utilization_rate
        end

        @testset "Withdrawal Bounds" begin
            config = WithdrawalConfig(min_utilization=0.10, max_utilization=1.00)

            result = calculate_withdrawal(config, 100_000.0, 100_000.0, 0.05, 65)
            @test 0.10 <= result.utilization_rate <= 1.00

            # Cannot withdraw more than AV
            result_low_av = calculate_withdrawal(config, 100_000.0, 1_000.0, 0.05, 65)
            @test result_low_av.withdrawal_amount <= 1_000.0
        end

        @testset "calculate_path_withdrawals" begin
            config = SOAWithdrawalConfig()
            gwb_path = fill(100_000.0, 5)
            av_path = [100_000.0, 105_000.0, 90_000.0, 85_000.0, 80_000.0]
            ages = [65, 66, 67, 68, 69]

            results = calculate_path_withdrawals(config, gwb_path, av_path, 0.05, ages)

            @test length(results) == 5
            @test all(r -> 0.0 <= r.utilization_rate <= 1.0, results)
        end

        @testset "Utilization Metrics" begin
            config = SOAWithdrawalConfig()
            gwb_path = fill(100_000.0, 3)
            av_path = fill(100_000.0, 3)
            ages = [65, 66, 67]

            results = calculate_path_withdrawals(config, gwb_path, av_path, 0.05, ages)

            total = total_withdrawals(results)
            @test total > 0.0

            avg_util = average_utilization(results)
            @test 0.0 < avg_util <= 1.0

            amounts = withdrawal_amounts(results)
            @test length(amounts) == 3
        end
    end


    # =========================================================================
    # Expense Models
    # =========================================================================
    @testset "Expense Models" begin
        @testset "ExpenseConfig - Basic" begin
            config = ExpenseConfig(
                per_policy_annual=100.0,
                pct_of_av_annual=0.015,
                acquisition_pct=0.03,
                inflation_rate=0.025
            )

            # Year 0 expense
            result_y0 = calculate_expense(config, 100_000.0, 0)
            @test result_y0.per_policy_component == 100.0
            @test result_y0.av_component == 1_500.0  # 1.5% of 100k
            @test result_y0.total_expense == 1_600.0

            # Inflation adjustment
            result_y5 = calculate_expense(config, 100_000.0, 5)
            @test result_y5.per_policy_component ≈ 100.0 * (1.025)^5 atol=1e-6

            # AV component unchanged by year
            @test result_y5.av_component == result_y0.av_component
        end

        @testset "Acquisition Expense" begin
            config = ExpenseConfig(acquisition_pct=0.05)

            acq = calculate_acquisition_expense(config, 100_000.0)
            @test acq == 5_000.0
        end

        @testset "calculate_path_expenses" begin
            config = ExpenseConfig(per_policy_annual=100.0, pct_of_av_annual=0.01)
            av_path = [100_000.0, 105_000.0, 110_000.0]

            results = calculate_path_expenses(config, av_path; include_acquisition=true)

            @test length(results) == 3
            # First year includes acquisition
            @test results[1].total_expense > results[2].total_expense - 100  # Approximately, accounting for AV growth
        end

        @testset "pv_expenses" begin
            config = ExpenseConfig(per_policy_annual=100.0, pct_of_av_annual=0.01)
            av_path = fill(100_000.0, 10)

            results = calculate_path_expenses(config, av_path; include_acquisition=false)
            pv = pv_expenses(results, 0.05)

            @test pv > 0.0
            @test pv < total_expenses(results)  # PV should be less than nominal sum
        end

        @testset "expense_ratio" begin
            config = ExpenseConfig(per_policy_annual=100.0, pct_of_av_annual=0.015)

            ratio = expense_ratio(config, 100_000.0)
            @test ratio ≈ 0.016 atol=1e-4  # 100/100000 + 0.015 = 0.016
        end

        @testset "breakeven_av" begin
            config = ExpenseConfig(per_policy_annual=100.0, pct_of_av_annual=0.01)

            # Target 2% expense ratio
            av_needed = breakeven_av(config, 0.02)
            @test av_needed ≈ 100.0 / (0.02 - 0.01) atol=1  # 10,000
        end

        @testset "Input Validation" begin
            config = ExpenseConfig()
            @test_throws ArgumentError calculate_expense(config, -1.0, 0)  # Negative AV
            @test_throws ArgumentError calculate_expense(config, 100_000.0, -1)  # Negative year
        end
    end


    # =========================================================================
    # BehavioralConfig Wrapper
    # =========================================================================
    @testset "BehavioralConfig" begin
        # Empty config
        bc_empty = BehavioralConfig()
        @test !has_lapse(bc_empty)
        @test !has_withdrawal(bc_empty)
        @test !has_expenses(bc_empty)
        @test !has_any_behavior(bc_empty)

        # Full config
        bc_full = BehavioralConfig(
            lapse = LapseConfig(),
            withdrawal = WithdrawalConfig(),
            expenses = ExpenseConfig()
        )
        @test has_lapse(bc_full)
        @test has_withdrawal(bc_full)
        @test has_expenses(bc_full)
        @test has_any_behavior(bc_full)

        # Partial config
        bc_partial = BehavioralConfig(lapse = SOALapseConfig())
        @test has_lapse(bc_partial)
        @test !has_withdrawal(bc_partial)
        @test has_any_behavior(bc_partial)
    end


    # =========================================================================
    # GLWB Integration
    # =========================================================================
    @testset "GLWB Integration" begin
        @testset "GLWBSimulator with Behavioral Configs" begin
            # Without behavioral
            sim_base = GLWBSimulator(n_paths=100)
            @test !has_lapse_model(sim_base)
            @test !has_withdrawal_model(sim_base)
            @test !has_expense_model(sim_base)

            # With behavioral
            sim_behavioral = GLWBSimulator(
                n_paths=100,
                lapse_config = SOALapseConfig(),
                withdrawal_config = SOAWithdrawalConfig(),
                expense_config = ExpenseConfig()
            )
            @test has_lapse_model(sim_behavioral)
            @test has_withdrawal_model(sim_behavioral)
            @test has_expense_model(sim_behavioral)
            @test has_behavioral_models(sim_behavioral)
        end

        @testset "glwb_price Backward Compatibility" begin
            # Base simulation without behavioral models
            sim = GLWBSimulator(n_paths=100, seed=42)
            result = glwb_price(sim, 100_000.0, 65)

            # Should still work
            @test result.price >= 0.0
            @test 0.0 <= result.prob_ruin <= 1.0
            @test result.n_paths == 100

            # Behavioral fields should be nothing
            @test result.avg_utilization === nothing
            @test result.total_expenses_pv === nothing
            @test result.lapse_year_histogram === nothing
        end

        @testset "glwb_price with Behavioral Models" begin
            sim = GLWBSimulator(
                n_paths=100,
                seed=42,
                lapse_config = SOALapseConfig(surrender_charge_length=7),
                withdrawal_config = SOAWithdrawalConfig(),
                expense_config = ExpenseConfig(per_policy_annual=100.0)
            )

            result = glwb_price(sim, 100_000.0, 65)

            # Basic results still valid
            @test result.price >= 0.0
            @test 0.0 <= result.prob_ruin <= 1.0

            # Behavioral metrics should be populated
            @test result.avg_utilization !== nothing
            @test 0.0 < result.avg_utilization <= 1.0

            @test result.total_expenses_pv !== nothing
            @test result.total_expenses_pv > 0.0

            @test result.lapse_year_histogram !== nothing
            @test length(result.lapse_year_histogram) > 0
        end

        @testset "Lapse Integration - Prob Lapse" begin
            # With lapse model, should have non-zero lapse probability
            sim_lapse = GLWBSimulator(
                n_paths=500,
                seed=42,
                lapse_config = SOALapseConfig()
            )
            result = glwb_price(sim_lapse, 100_000.0, 65)

            # Should have some lapses over a 35-year horizon
            @test result.prob_lapse > 0.0
        end
    end


    # =========================================================================
    # Anti-Pattern Tests (Bug Prevention)
    # =========================================================================
    @testset "Anti-Patterns" begin
        @testset "Lapse Rate Bounds" begin
            # Lapse rate must always be in [0, 1]
            for moneyness_sens in [0.5, 1.0, 2.0, 3.0]
                config = LapseConfig(moneyness_sensitivity=moneyness_sens)
                for gwb in [50_000.0, 100_000.0, 150_000.0]
                    for av in [50_000.0, 100_000.0, 150_000.0]
                        result = calculate_lapse(config, gwb, av)
                        @test 0.0 <= result.lapse_rate <= 1.0
                    end
                end
            end
        end

        @testset "Utilization Rate Bounds" begin
            # Utilization must always be in [0, 1]
            config = SOAWithdrawalConfig()
            for duration in [1, 5, 10, 15]
                for age in [55, 65, 75, 85]
                    for moneyness in [0.8, 1.0, 1.2, 1.5]
                        result = calculate_withdrawal(config, 100_000.0, 80_000.0, 0.05, duration, age; moneyness=moneyness)
                        @test 0.0 <= result.utilization_rate <= 1.0
                    end
                end
            end
        end

        @testset "ITM Direction - Lapse" begin
            # ITM guarantee (GWB > AV) should reduce lapse (rational behavior)
            config = LapseConfig(moneyness_sensitivity=1.0)

            result_itm = calculate_lapse(config, 120_000.0, 100_000.0)  # ITM
            result_otm = calculate_lapse(config, 80_000.0, 100_000.0)   # OTM

            @test result_itm.lapse_rate < result_otm.lapse_rate
        end

        @testset "Expense Non-Negativity" begin
            config = ExpenseConfig()
            for av in [0.0, 1_000.0, 100_000.0, 1_000_000.0]
                for year in [0, 1, 5, 10, 20]
                    if av >= 0 && year >= 0
                        result = calculate_expense(config, av, year)
                        @test result.total_expense >= 0.0
                        @test result.per_policy_component >= 0.0
                        @test result.av_component >= 0.0
                    end
                end
            end
        end

        @testset "Survival Probability Monotonicity" begin
            # Survival probability must be monotonically decreasing
            lapse_rates = [0.05, 0.05, 0.10, 0.08, 0.06, 0.06]
            survival = survival_from_lapses(lapse_rates)

            for i in 1:(length(survival)-1)
                @test survival[i] >= survival[i+1]
            end
        end
    end


    # =========================================================================
    # SOA Benchmark Validation [T2]
    # =========================================================================
    @testset "SOA Benchmark Validation" begin
        @testset "SOA 2006 Surrender Rates" begin
            # Validate key data points match SOA 2006 Table 6
            @test interpolate_surrender_by_duration(1; sc_length=7) ≈ 0.014 atol=1e-6
            @test interpolate_surrender_by_duration(8; sc_length=7) ≈ 0.112 atol=1e-6
            @test interpolate_surrender_by_duration(11; sc_length=7) ≈ 0.067 atol=1e-6

            # SC cliff multiplier ≈ 2.48 (14.4% / 5.8%)
            @test SOA_2006_SC_CLIFF_MULTIPLIER ≈ 2.48 atol=0.01
        end

        @testset "SOA 2018 Utilization Rates" begin
            # Validate key data points match SOA 2018 Table 1-17
            @test interpolate_utilization_by_duration(1) ≈ 0.111 atol=1e-6
            @test interpolate_utilization_by_duration(10) ≈ 0.518 atol=1e-6
            @test interpolate_utilization_by_duration(11) ≈ 0.536 atol=1e-6

            # Age-based utilization (Table 1-18)
            @test interpolate_utilization_by_age(55) ≈ 0.05 atol=1e-6
            @test interpolate_utilization_by_age(72) ≈ 0.59 atol=1e-6
        end

        @testset "SOA 2018 ITM Sensitivity" begin
            # Validate ITM factors match SOA 2018 Figure 1-44
            @test get_itm_sensitivity_factor(0.9) ≈ 1.00 atol=1e-6   # OTM
            @test get_itm_sensitivity_factor(1.1) ≈ 1.39 atol=1e-6   # Shallow ITM
            @test get_itm_sensitivity_factor(1.3) ≈ 1.79 atol=1e-6   # Moderate ITM
            @test get_itm_sensitivity_factor(1.6) ≈ 2.11 atol=1e-6   # Deep ITM
        end
    end

end  # "Behavioral Models"
