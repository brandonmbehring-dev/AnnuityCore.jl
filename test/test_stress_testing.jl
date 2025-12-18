@testset "Stress Testing" begin
    # ============================================================================
    # Types and Enums
    # ============================================================================

    @testset "Enums" begin
        @testset "ScenarioType" begin
            @test HISTORICAL isa ScenarioType
            @test ORSA isa ScenarioType
            @test REGULATORY isa ScenarioType
            @test CUSTOM isa ScenarioType
        end

        @testset "RecoveryType" begin
            @test V_SHAPED isa RecoveryType
            @test U_SHAPED isa RecoveryType
            @test L_SHAPED isa RecoveryType
            @test W_SHAPED isa RecoveryType
        end
    end

    @testset "StressScenario Construction" begin
        @testset "Valid scenarios" begin
            scenario = StressScenario(
                name = "test",
                display_name = "Test Scenario",
                equity_shock = -0.30,
                rate_shock = -0.0100
            )
            @test scenario.name == "test"
            @test scenario.equity_shock == -0.30
            @test scenario.rate_shock == -0.0100
            @test scenario.vol_shock == 1.0  # default
            @test scenario.scenario_type == CUSTOM  # default
        end

        @testset "Full specification" begin
            scenario = StressScenario(
                name = "full",
                display_name = "Full Scenario",
                equity_shock = -0.50,
                rate_shock = -0.0200,
                vol_shock = 2.5,
                lapse_multiplier = 1.3,
                withdrawal_multiplier = 1.5,
                scenario_type = ORSA
            )
            @test scenario.vol_shock == 2.5
            @test scenario.lapse_multiplier == 1.3
            @test scenario.withdrawal_multiplier == 1.5
            @test scenario.scenario_type == ORSA
        end

        @testset "Anti-patterns: Invalid bounds" begin
            # Equity shock > 100% gain
            @test_throws ErrorException StressScenario(
                name = "bad",
                display_name = "Bad",
                equity_shock = 1.5,  # 150% gain - unrealistic
                rate_shock = 0.0
            )

            # Equity shock < -100%
            @test_throws ErrorException StressScenario(
                name = "bad",
                display_name = "Bad",
                equity_shock = -1.5,  # -150% - impossible
                rate_shock = 0.0
            )

            # Negative vol shock
            @test_throws ErrorException StressScenario(
                name = "bad",
                display_name = "Bad",
                equity_shock = -0.20,
                rate_shock = 0.0,
                vol_shock = -0.5
            )

            # Negative lapse multiplier
            @test_throws ErrorException StressScenario(
                name = "bad",
                display_name = "Bad",
                equity_shock = -0.20,
                rate_shock = 0.0,
                lapse_multiplier = -0.5
            )
        end
    end

    @testset "SensitivityParameter" begin
        param = SensitivityParameter(
            name = "equity",
            display_name = "Equity Shock",
            base_value = -0.30,
            range_low = -0.60,
            range_high = -0.10,
            unit = "%"
        )
        @test param.name == "equity"
        @test param.base_value == -0.30
        @test param.range_low < param.range_high

        # Invalid: low > high
        @test_throws ErrorException SensitivityParameter(
            name = "bad",
            display_name = "Bad",
            base_value = 0.0,
            range_low = 1.0,
            range_high = 0.0
        )
    end

    @testset "ReverseStressTarget" begin
        target = ReverseStressTarget(
            name = "test",
            display_name = "Test Target",
            threshold = 0.5,
            direction = :below,
            metric = :reserve_ratio
        )
        @test target.threshold == 0.5
        @test target.direction == :below

        # Test triggers_target
        @test triggers_target(target, 0.3)  # 0.3 < 0.5
        @test !triggers_target(target, 0.6)  # 0.6 > 0.5

        # Above direction
        target_above = ReverseStressTarget(
            name = "above",
            display_name = "Above",
            threshold = 1.0,
            direction = :above
        )
        @test triggers_target(target_above, 1.5)  # 1.5 > 1.0
        @test !triggers_target(target_above, 0.5)  # 0.5 < 1.0

        # Invalid direction
        @test_throws ErrorException ReverseStressTarget(
            name = "bad",
            display_name = "Bad",
            threshold = 0.0,
            direction = :invalid
        )
    end

    # ============================================================================
    # ORSA Scenarios
    # ============================================================================

    @testset "ORSA Scenarios" begin
        @testset "Predefined scenarios exist" begin
            @test ORSA_MODERATE_ADVERSE isa StressScenario
            @test ORSA_SEVERELY_ADVERSE isa StressScenario
            @test ORSA_EXTREMELY_ADVERSE isa StressScenario
        end

        @testset "ORSA severity ordering" begin
            # Moderate < Severe < Extreme
            @test abs(ORSA_MODERATE_ADVERSE.equity_shock) < abs(ORSA_SEVERELY_ADVERSE.equity_shock)
            @test abs(ORSA_SEVERELY_ADVERSE.equity_shock) < abs(ORSA_EXTREMELY_ADVERSE.equity_shock)
            @test abs(ORSA_MODERATE_ADVERSE.rate_shock) < abs(ORSA_SEVERELY_ADVERSE.rate_shock)
            @test abs(ORSA_SEVERELY_ADVERSE.rate_shock) < abs(ORSA_EXTREMELY_ADVERSE.rate_shock)
        end

        @testset "ORSA scenario values [T2]" begin
            # Moderate: -15% equity, -50 bps
            @test ORSA_MODERATE_ADVERSE.equity_shock == -0.15
            @test ORSA_MODERATE_ADVERSE.rate_shock == -0.0050

            # Severely: -30% equity, -100 bps
            @test ORSA_SEVERELY_ADVERSE.equity_shock == -0.30
            @test ORSA_SEVERELY_ADVERSE.rate_shock == -0.0100

            # Extremely: -50% equity, -200 bps
            @test ORSA_EXTREMELY_ADVERSE.equity_shock == -0.50
            @test ORSA_EXTREMELY_ADVERSE.rate_shock == -0.0200
        end

        @testset "ORSA_SCENARIOS collection" begin
            @test length(ORSA_SCENARIOS) == 3
            @test ORSA_MODERATE_ADVERSE in ORSA_SCENARIOS
            @test ORSA_SEVERELY_ADVERSE in ORSA_SCENARIOS
            @test ORSA_EXTREMELY_ADVERSE in ORSA_SCENARIOS
        end
    end

    # ============================================================================
    # Historical Crises
    # ============================================================================

    @testset "Historical Crises" begin
        @testset "All crises defined" begin
            @test CRISIS_2008_GFC isa HistoricalCrisis
            @test CRISIS_2020_COVID isa HistoricalCrisis
            @test CRISIS_2000_DOTCOM isa HistoricalCrisis
            @test CRISIS_2011_EURO_DEBT isa HistoricalCrisis
            @test CRISIS_2015_CHINA isa HistoricalCrisis
            @test CRISIS_2018_Q4 isa HistoricalCrisis
            @test CRISIS_2022_RATES isa HistoricalCrisis
        end

        @testset "2008 GFC calibration [T2]" begin
            @test CRISIS_2008_GFC.equity_shock ≈ -0.568 atol=0.01
            @test CRISIS_2008_GFC.rate_shock ≈ -0.0254 atol=0.001
            @test CRISIS_2008_GFC.vix_peak ≈ 80.9 atol=1.0
            @test CRISIS_2008_GFC.duration_months == 17
            @test CRISIS_2008_GFC.recovery_type == U_SHAPED
        end

        @testset "2020 COVID calibration [T2]" begin
            @test CRISIS_2020_COVID.equity_shock ≈ -0.313 atol=0.01
            @test CRISIS_2020_COVID.vix_peak ≈ 82.69 atol=1.0
            @test CRISIS_2020_COVID.duration_months == 1  # Fastest crash
            @test CRISIS_2020_COVID.recovery_type == V_SHAPED
        end

        @testset "2022 rates - rising rate scenario [T2]" begin
            @test CRISIS_2022_RATES.rate_shock > 0  # Unique: positive rate shock
            @test CRISIS_2022_RATES.rate_shock ≈ 0.0282 atol=0.005  # +282 bps
            @test CRISIS_2022_RATES.equity_shock < 0  # Still negative equity
        end

        @testset "Crisis collections" begin
            @test length(ALL_HISTORICAL_CRISES) == 7
            @test length(FALLING_RATE_CRISES) == 6
            @test length(RISING_RATE_CRISES) == 1
            @test CRISIS_2022_RATES in RISING_RATE_CRISES
        end

        @testset "get_crisis lookup" begin
            crisis = get_crisis("2008_gfc")
            @test !isnothing(crisis)
            @test crisis.name == "2008_gfc"

            @test isnothing(get_crisis("nonexistent"))
        end

        @testset "crisis_to_scenario conversion" begin
            scenario = crisis_to_scenario(CRISIS_2008_GFC)
            @test scenario isa StressScenario
            @test scenario.equity_shock == CRISIS_2008_GFC.equity_shock
            @test scenario.rate_shock == CRISIS_2008_GFC.rate_shock
            @test scenario.scenario_type == HISTORICAL
            # Vol shock derived from VIX peak (~80.9 / 20 = 4.045)
            @test scenario.vol_shock ≈ 4.0 atol=0.5
        end

        @testset "Sorting functions" begin
            by_severity = crises_by_severity()
            @test length(by_severity) == 7
            # 2008 GFC should be most severe (most negative equity)
            @test by_severity[1].equity_shock <= by_severity[end].equity_shock

            by_duration = crises_by_duration()
            @test by_duration[1].duration_months >= by_duration[end].duration_months
        end
    end

    @testset "Crisis Profiles" begin
        @testset "Profile interpolation" begin
            # 2008 GFC has profile data
            profile_at_10 = interpolate_crisis_profile(CRISIS_2008_GFC, 10.0)
            @test profile_at_10.month == 10.0
            @test profile_at_10.equity_cumulative < 0  # Should be negative
            @test profile_at_10.vix_level > 20  # Elevated VIX
        end

        @testset "crisis_scenario_at_month" begin
            scenario = crisis_scenario_at_month(CRISIS_2008_GFC, 12.0)
            @test scenario isa StressScenario
            @test scenario.scenario_type == HISTORICAL
            @test scenario.equity_shock < 0
        end

        @testset "generate_crisis_path" begin
            path = generate_crisis_path(CRISIS_2020_COVID, step_months=0.5)
            @test length(path) > 1
            @test all(s isa StressScenario for s in path)
        end
    end

    # ============================================================================
    # Scenario Builders
    # ============================================================================

    @testset "Scenario Builders" begin
        @testset "create_equity_shock" begin
            scenario = create_equity_shock(-0.25)
            @test scenario.equity_shock == -0.25
            @test scenario.rate_shock == 0.0
            @test scenario.scenario_type == CUSTOM
        end

        @testset "create_rate_shock" begin
            scenario = create_rate_shock(-100.0)  # -100 bps
            @test scenario.rate_shock == -0.0100
            @test scenario.equity_shock == 0.0
        end

        @testset "create_vol_shock" begin
            scenario = create_vol_shock(2.0)
            @test scenario.vol_shock == 2.0
            @test scenario.equity_shock == 0.0
            @test scenario.rate_shock == 0.0
        end

        @testset "create_behavioral_shock" begin
            scenario = create_behavioral_shock(1.5, 2.0)
            @test scenario.lapse_multiplier == 1.5
            @test scenario.withdrawal_multiplier == 2.0
        end

        @testset "create_combined_scenario" begin
            scenario = create_combined_scenario(
                name = "combined",
                display_name = "Combined",
                equity_shock = -0.20,
                rate_shock = -0.0050,
                vol_shock = 1.5
            )
            @test scenario.equity_shock == -0.20
            @test scenario.rate_shock == -0.0050
            @test scenario.vol_shock == 1.5
        end

        @testset "combine_scenarios" begin
            s1 = create_equity_shock(-0.20)
            s2 = create_rate_shock(-100.0)
            combined = combine_scenarios(s1, s2)
            @test combined.equity_shock == -0.20
            @test combined.rate_shock == -0.0100
        end

        @testset "scale_scenario" begin
            base = ORSA_SEVERELY_ADVERSE
            scaled = scale_scenario(base, 0.5)
            @test scaled.equity_shock == base.equity_shock * 0.5
            @test scaled.rate_shock == base.rate_shock * 0.5
        end
    end

    @testset "Scenario Grids" begin
        @testset "generate_equity_grid" begin
            grid = generate_equity_grid([-0.10, -0.20, -0.30])
            @test length(grid) == 3
            @test grid[1].equity_shock == -0.10
            @test grid[3].equity_shock == -0.30
        end

        @testset "generate_2d_grid" begin
            grid = generate_2d_grid([-0.20, -0.30], [-50.0, -100.0])
            @test size(grid) == (2, 2)
            @test grid[1, 1].equity_shock == -0.20
            @test grid[1, 1].rate_shock == -0.0050
            @test grid[2, 2].equity_shock == -0.30
            @test grid[2, 2].rate_shock == -0.0100
        end
    end

    @testset "Scenario Utilities" begin
        @testset "severity_score" begin
            # More severe = higher score
            mild = create_equity_shock(-0.10)
            severe = create_equity_shock(-0.40)
            @test severity_score(severe) > severity_score(mild)

            # 2008 GFC should be very severe
            gfc_scenario = crisis_to_scenario(CRISIS_2008_GFC)
            @test severity_score(gfc_scenario) > 0.8  # Near max
        end

        @testset "is_adverse" begin
            @test is_adverse(ORSA_SEVERELY_ADVERSE)
            @test is_adverse(create_equity_shock(-0.10))
            @test is_adverse(create_vol_shock(2.0))

            neutral = StressScenario(
                name = "neutral",
                display_name = "Neutral",
                equity_shock = 0.0,
                rate_shock = 0.0
            )
            @test !is_adverse(neutral)
        end

        @testset "sort_by_severity" begin
            scenarios = [
                create_equity_shock(-0.10),
                create_equity_shock(-0.40),
                create_equity_shock(-0.20)
            ]
            sorted = sort_by_severity(scenarios)
            @test sorted[1].equity_shock == -0.40  # Most severe first
            @test sorted[3].equity_shock == -0.10
        end
    end

    # ============================================================================
    # Impact Model
    # ============================================================================

    @testset "Reserve Impact Model" begin
        base_reserve = 1_000_000.0

        @testset "Equity shock impact" begin
            scenario = create_equity_shock(-0.30)
            result = calculate_reserve_impact(scenario, base_reserve)

            # -30% equity × 0.80 sensitivity = +24% reserve impact
            @test result.total_impact ≈ 0.24 atol=0.01
            @test result.stressed_reserve ≈ 1_240_000.0 atol=10000
            @test result.components["equity"] ≈ 0.24 atol=0.01
        end

        @testset "Rate shock impact" begin
            scenario = create_rate_shock(-100.0)  # -100 bps
            result = calculate_reserve_impact(scenario, base_reserve)

            # -100 bps × 10 duration = +10% reserve impact
            @test result.total_impact ≈ 0.10 atol=0.01
            @test result.components["rate"] ≈ 0.10 atol=0.01
        end

        @testset "Vol shock impact" begin
            scenario = create_vol_shock(2.0)  # 2x vol
            result = calculate_reserve_impact(scenario, base_reserve)

            # (2.0 - 1.0) × 0.15 = +15% impact
            @test result.total_impact ≈ 0.15 atol=0.01
            @test result.components["vol"] ≈ 0.15 atol=0.01
        end

        @testset "Combined impact" begin
            scenario = ORSA_SEVERELY_ADVERSE
            result = calculate_reserve_impact(scenario, base_reserve)

            # Should have contributions from all components
            @test result.components["equity"] > 0
            @test result.components["rate"] > 0
            @test result.components["vol"] > 0
            @test result.total_impact > 0
        end

        @testset "Reserve floor at zero" begin
            # Extreme scenario that would drive negative
            extreme = StressScenario(
                name = "extreme",
                display_name = "Extreme",
                equity_shock = 0.90,  # +90% gain (reduces liability)
                rate_shock = 0.10,    # +1000 bps (reduces PV)
                vol_shock = 0.1       # Very low vol
            )
            result = calculate_reserve_impact(extreme, base_reserve)
            @test result.stressed_reserve >= 0.0  # Floored at zero
        end
    end

    @testset "RBC Ratio Calculation" begin
        base_reserve = 1_000_000.0
        required_capital = 500_000.0  # 200% starting RBC

        scenario = create_equity_shock(-0.30)
        rbc = calculate_rbc_ratio(scenario, base_reserve, required_capital)

        # Reserve increases with negative equity shock (liability perspective)
        @test rbc > 2.0  # RBC should increase
    end

    # ============================================================================
    # Sensitivity Analysis
    # ============================================================================

    @testset "Sensitivity Analysis" begin
        @testset "Default parameters exist" begin
            @test DEFAULT_EQUITY_PARAM isa SensitivityParameter
            @test DEFAULT_RATE_PARAM isa SensitivityParameter
            @test DEFAULT_VOL_PARAM isa SensitivityParameter
            @test length(DEFAULT_SENSITIVITY_PARAMS) == 5
        end

        @testset "run_sensitivity_sweep" begin
            param = DEFAULT_EQUITY_PARAM
            impact_fn = shock -> 1_000_000.0 * (1.0 - shock * 0.8)

            result = run_sensitivity_sweep(param, impact_fn, n_points=11)

            @test result isa SensitivityResult
            @test length(result.values) == 11
            @test length(result.impacts) == 11
            @test result.values[1] == param.range_low
            @test result.values[end] == param.range_high
        end

        @testset "TornadoData construction" begin
            params = ["Equity", "Rate", "Vol"]
            low_impacts = [800_000.0, 900_000.0, 950_000.0]
            high_impacts = [1_200_000.0, 1_100_000.0, 1_050_000.0]

            tornado = TornadoData(;
                parameters = params,
                low_impacts = low_impacts,
                high_impacts = high_impacts,
                base_value = 1_000_000.0
            )

            @test length(tornado.parameters) == 3
            @test impact_range(tornado, 1) == 400_000.0  # 1.2M - 0.8M
        end

        @testset "sort_tornado" begin
            tornado = TornadoData(;
                parameters = ["Small", "Large", "Medium"],
                low_impacts = [950_000.0, 800_000.0, 900_000.0],
                high_impacts = [1_050_000.0, 1_200_000.0, 1_100_000.0],
                base_value = 1_000_000.0
            )

            sorted = sort_tornado(tornado)
            @test sorted.parameters[1] == "Large"  # Largest range first
            @test sorted.parameters[3] == "Small"  # Smallest range last
        end

        @testset "monotonicity check" begin
            # Increasing
            result_inc = SensitivityResult(
                DEFAULT_EQUITY_PARAM,
                [-0.5, -0.4, -0.3, -0.2, -0.1],
                [1.0, 2.0, 3.0, 4.0, 5.0],
                3.0
            )
            @test monotonicity(result_inc) == :increasing

            # Decreasing
            result_dec = SensitivityResult(
                DEFAULT_EQUITY_PARAM,
                [-0.5, -0.4, -0.3, -0.2, -0.1],
                [5.0, 4.0, 3.0, 2.0, 1.0],
                3.0
            )
            @test monotonicity(result_dec) == :decreasing

            # Non-monotonic
            result_nm = SensitivityResult(
                DEFAULT_EQUITY_PARAM,
                [-0.5, -0.4, -0.3, -0.2, -0.1],
                [1.0, 3.0, 2.0, 4.0, 5.0],
                3.0
            )
            @test monotonicity(result_nm) == :non_monotonic
        end
    end

    # ============================================================================
    # Reverse Stress Testing
    # ============================================================================

    @testset "Reverse Stress Testing" begin
        @testset "Predefined targets" begin
            @test RESERVE_EXHAUSTION isa ReverseStressTarget
            @test RBC_BREACH_200 isa ReverseStressTarget
            @test RBC_BREACH_300 isa ReverseStressTarget
            @test RESERVE_RATIO_50 isa ReverseStressTarget

            @test RESERVE_EXHAUSTION.threshold == 0.0
            @test RBC_BREACH_200.threshold == 2.0
        end

        @testset "find_breaking_point - found" begin
            # Simple test: find where linear function crosses threshold
            param = SensitivityParameter(
                name = "test",
                display_name = "Test",
                base_value = 0.0,
                range_low = -1.0,
                range_high = 1.0
            )
            target = ReverseStressTarget(
                name = "test",
                display_name = "Test",
                threshold = 0.5,
                direction = :below
            )

            # Linear function: f(x) = 1 - x
            # Crosses 0.5 at x = 0.5
            metric_fn = x -> 1.0 - x

            result = find_breaking_point(target, param, metric_fn)

            @test result.converged
            @test !isnothing(result.breaking_point)
            @test result.breaking_point ≈ 0.5 atol=0.01
        end

        @testset "find_breaking_point - not found" begin
            param = SensitivityParameter(
                name = "test",
                display_name = "Test",
                base_value = 0.0,
                range_low = -1.0,
                range_high = 1.0
            )
            target = ReverseStressTarget(
                name = "test",
                display_name = "Test",
                threshold = -10.0,  # Never triggered in range
                direction = :below
            )

            metric_fn = x -> x  # Always > -10 in range

            result = find_breaking_point(target, param, metric_fn)

            @test isnothing(result.breaking_point)
        end

        @testset "breaking_point_severity" begin
            param = SensitivityParameter(
                name = "test",
                display_name = "Test",
                base_value = 0.5,
                range_low = 0.0,
                range_high = 1.0
            )

            # Critical: < 20% of range from base
            critical_result = ReverseStressResult(
                RESERVE_RATIO_50,
                "test",
                0.55,  # Only 5% of range from base (0.5)
                10,
                true
            )
            @test breaking_point_severity(critical_result, param) == :critical

            # Low: > 60% of range from base
            low_result = ReverseStressResult(
                RESERVE_RATIO_50,
                "test",
                0.95,  # 45% of range from base
                10,
                true
            )
            @test breaking_point_severity(low_result, param) in [:moderate, :low]
        end
    end

    # ============================================================================
    # Stress Test Runner
    # ============================================================================

    @testset "Stress Test Runner" begin
        config = StressTestConfig(
            base_reserve = 1_000_000.0,
            minimum_reserve_ratio = 0.0,
            rbc_threshold = 2.0,
            run_sensitivity = false,  # Speed up tests
            run_reverse = false
        )

        @testset "StressTestConfig validation" begin
            @test_throws ErrorException StressTestConfig(
                base_reserve = -1000.0  # Invalid
            )
            @test_throws ErrorException StressTestConfig(
                base_reserve = 1000.0,
                n_sensitivity_points = 2  # Too few
            )
        end

        @testset "orsa_runner" begin
            runner = orsa_runner(config)
            @test length(runner.scenarios) == 3
        end

        @testset "historical_runner" begin
            runner = historical_runner(config)
            @test length(runner.scenarios) == 7
        end

        @testset "standard_runner" begin
            runner = standard_runner(config)
            @test length(runner.scenarios) == 10  # 3 ORSA + 7 historical
        end

        @testset "run_scenario" begin
            runner = orsa_runner(config)
            result = run_scenario(runner, ORSA_SEVERELY_ADVERSE)

            @test result isa StressTestResult
            @test result.base_reserve == 1_000_000.0
            @test result.stressed_reserve > 0
            @test result.reserve_impact != 0
        end

        @testset "run_all_scenarios" begin
            runner = orsa_runner(config)
            results = run_all_scenarios(runner)

            @test length(results) == 3
            @test all(r isa StressTestResult for r in results)
        end

        @testset "run_stress_test full" begin
            full_config = StressTestConfig(
                base_reserve = 1_000_000.0,
                run_sensitivity = true,
                run_reverse = true,
                n_sensitivity_points = 5  # Small for speed
            )
            runner = orsa_runner(full_config)
            summary = run_stress_test(runner)

            @test summary isa StressTestSummary
            @test length(summary.scenario_results) == 3
            @test !isnothing(summary.worst_case)
            @test !isnothing(summary.sensitivity)  # Ran sensitivity
            @test !isnothing(summary.reverse_report)  # Ran reverse
        end
    end

    @testset "Quick Analysis Functions" begin
        @testset "quick_stress_test" begin
            summary = quick_stress_test(1_000_000.0, scenarios=:orsa)
            @test summary isa StressTestSummary
            @test length(summary.scenario_results) == 3
        end

        @testset "compare_scenarios" begin
            scenarios = [
                create_equity_shock(-0.10),
                create_equity_shock(-0.30),
                create_equity_shock(-0.50)
            ]
            comparison = compare_scenarios(1_000_000.0, scenarios)

            @test length(comparison.results) == 3
            # Worst should be -50%
            @test comparison.worst.scenario.equity_shock == -0.50
        end

        @testset "stress_test_grid" begin
            grid = stress_test_grid(
                1_000_000.0,
                [-0.20, -0.30],
                [-50.0, -100.0]
            )
            @test size(grid) == (2, 2)
            @test all(r.stressed > 0 for r in grid)
        end
    end

    @testset "Export Functions" begin
        summary = quick_stress_test(1_000_000.0, scenarios=:orsa)

        @testset "export_results dict format" begin
            exported = export_results(summary, format=:dict)
            @test exported isa Dict
            @test haskey(exported, "all_passed")
            @test haskey(exported, "scenario_results")
            @test length(exported["scenario_results"]) == 3
        end

        @testset "export_results array format" begin
            exported = export_results(summary, format=:array)
            @test exported isa Vector
            @test length(exported) == 3
        end
    end

    # ============================================================================
    # Anti-Patterns
    # ============================================================================

    @testset "Anti-Patterns" begin
        @testset "Equity shock direction consistency" begin
            # Negative equity shock should INCREASE reserves (liability perspective)
            scenario = create_equity_shock(-0.30)
            result = calculate_reserve_impact(scenario, 1_000_000.0)
            @test result.stressed_reserve > result.stressed_reserve - result.total_impact * 1_000_000.0 || result.total_impact > 0

            # Positive equity shock should DECREASE reserves
            positive = StressScenario(
                name = "positive",
                display_name = "Positive",
                equity_shock = 0.30,
                rate_shock = 0.0
            )
            result_pos = calculate_reserve_impact(positive, 1_000_000.0)
            @test result_pos.total_impact < 0
        end

        @testset "Rate shock direction consistency" begin
            # Negative rate shock should INCREASE reserves (duration effect)
            scenario = create_rate_shock(-100.0)
            result = calculate_reserve_impact(scenario, 1_000_000.0)
            @test result.total_impact > 0

            # Positive rate shock should DECREASE reserves
            positive_rate = create_rate_shock(100.0)
            result_pos = calculate_reserve_impact(positive_rate, 1_000_000.0)
            @test result_pos.total_impact < 0
        end

        @testset "Severity ordering preserved" begin
            mild = create_equity_shock(-0.10)
            moderate = create_equity_shock(-0.30)
            severe = create_equity_shock(-0.50)

            base = 1_000_000.0
            impact_mild = calculate_reserve_impact(mild, base).total_impact
            impact_moderate = calculate_reserve_impact(moderate, base).total_impact
            impact_severe = calculate_reserve_impact(severe, base).total_impact

            # More severe shock = larger impact
            @test impact_moderate > impact_mild
            @test impact_severe > impact_moderate
        end

        @testset "Historical crisis severity ranking" begin
            # 2008 GFC should be more severe than 2015 China
            gfc = crisis_to_scenario(CRISIS_2008_GFC)
            china = crisis_to_scenario(CRISIS_2015_CHINA)

            @test severity_score(gfc) > severity_score(china)
        end
    end

    # ============================================================================
    # Integration Tests
    # ============================================================================

    @testset "Integration" begin
        @testset "End-to-end ORSA stress test" begin
            # Full workflow: ORSA scenarios with all analyses
            config = StressTestConfig(
                base_reserve = 10_000_000.0,
                minimum_reserve_ratio = 0.5,
                rbc_threshold = 2.0,
                run_sensitivity = true,
                run_reverse = true,
                n_sensitivity_points = 11
            )

            runner = orsa_runner(config)
            summary = run_stress_test(runner)

            # All scenarios should run
            @test length(summary.scenario_results) == 3

            # Extreme adverse should be worst
            @test summary.worst_case.scenario.name == "orsa_extremely_adverse"

            # Check sensitivity ran
            @test !isnothing(summary.sensitivity)
            @test length(summary.sensitivity.parameters) > 0

            # Check reverse ran
            @test !isnothing(summary.reverse_report)
        end

        @testset "End-to-end historical stress test" begin
            summary = quick_stress_test(5_000_000.0, scenarios=:historical)

            # All 7 historical crises should run
            @test length(summary.scenario_results) == 7

            # Worst case should be 2008 GFC (most severe equity)
            worst_name = summary.worst_case.scenario.name
            @test worst_name == "2008_gfc"
        end

        @testset "Crisis path simulation" begin
            # Generate path through 2008 crisis
            path = generate_crisis_path(CRISIS_2008_GFC, step_months=3.0)

            # Simulate impact at each point
            base = 1_000_000.0
            impacts = [calculate_reserve_impact(s, base).total_impact for s in path]

            # Impact should peak somewhere in the middle/end
            @test maximum(impacts) > 0
            @test length(impacts) > 1
        end
    end
end
