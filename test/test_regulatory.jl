#=============================================================================
# Test Regulatory Module
#
# Tests for VM-21, VM-22, and scenario generation.
# [PROTOTYPE] Educational use only - not for regulatory filing.
=============================================================================#

using Test
using AnnuityCore
using Statistics

@testset "Regulatory" begin

    #=========================================================================
    # Scenario Types
    =========================================================================#

    @testset "EconomicScenario" begin
        @testset "construction" begin
            scenario = EconomicScenario(
                rates = fill(0.04, 30),
                equity_returns = fill(0.07, 30),
                scenario_id = 1
            )
            @test length(scenario.rates) == 30
            @test length(scenario.equity_returns) == 30
            @test scenario.scenario_id == 1
        end

        @testset "validation" begin
            # Mismatched lengths should error
            @test_throws ErrorException EconomicScenario(
                rates = fill(0.04, 30),
                equity_returns = fill(0.07, 20),
                scenario_id = 1
            )
        end
    end

    @testset "VasicekParams" begin
        @testset "defaults" begin
            params = VasicekParams()
            @test params.kappa == 0.20
            @test params.theta == 0.04
            @test params.sigma == 0.01
        end

        @testset "custom" begin
            params = VasicekParams(kappa=0.30, theta=0.05, sigma=0.02)
            @test params.kappa == 0.30
            @test params.theta == 0.05
            @test params.sigma == 0.02
        end
    end

    @testset "EquityParams" begin
        @testset "defaults" begin
            params = EquityParams()
            @test params.mu == 0.07
            @test params.sigma == 0.18
        end

        @testset "custom" begin
            params = EquityParams(mu=0.10, sigma=0.25)
            @test params.mu == 0.10
            @test params.sigma == 0.25
        end
    end

    @testset "RiskNeutralEquityParams" begin
        @testset "drift calculation" begin
            params = RiskNeutralEquityParams(risk_free_rate=0.04, dividend_yield=0.02)
            @test risk_neutral_drift(params) ≈ 0.02
        end

        @testset "conversion" begin
            params = RiskNeutralEquityParams(risk_free_rate=0.04, dividend_yield=0.02, sigma=0.20)
            eq = to_equity_params(params)
            @test eq.mu ≈ 0.02
            @test eq.sigma == 0.20
        end
    end

    #=========================================================================
    # Scenario Generator
    =========================================================================#

    @testset "ScenarioGenerator" begin
        @testset "construction" begin
            gen = ScenarioGenerator(n_scenarios=100, projection_years=20, seed=42)
            @test gen.n_scenarios == 100
            @test gen.projection_years == 20
            @test gen.seed == 42
        end

        @testset "validation" begin
            @test_throws ErrorException ScenarioGenerator(n_scenarios=0)
            @test_throws ErrorException ScenarioGenerator(projection_years=0)
        end

        @testset "reproducibility" begin
            gen1 = ScenarioGenerator(n_scenarios=10, seed=42)
            gen2 = ScenarioGenerator(n_scenarios=10, seed=42)

            scenarios1 = generate_ag43_scenarios(gen1)
            scenarios2 = generate_ag43_scenarios(gen2)

            # Same seed should produce same scenarios
            @test scenarios1.scenarios[1].rates ≈ scenarios2.scenarios[1].rates
        end
    end

    @testset "generate_ag43_scenarios" begin
        gen = ScenarioGenerator(n_scenarios=50, projection_years=10, seed=42)
        scenarios = generate_ag43_scenarios(gen)

        @test scenarios.n_scenarios == 50
        @test scenarios.projection_years == 10
        @test length(scenarios.scenarios) == 50

        # Check scenario structure
        for s in scenarios.scenarios
            @test length(s.rates) == 10
            @test length(s.equity_returns) == 10
        end

        # Rate matrix
        rate_matrix = get_rate_matrix(scenarios)
        @test size(rate_matrix) == (50, 10)

        # Equity matrix
        equity_matrix = get_equity_matrix(scenarios)
        @test size(equity_matrix) == (50, 10)
    end

    @testset "generate_rate_scenarios" begin
        gen = ScenarioGenerator(n_scenarios=100, projection_years=30, seed=42)
        rates = generate_rate_scenarios(gen, initial_rate=0.04)

        @test size(rates) == (100, 30)

        # Rates should be non-negative (floored at 0)
        @test all(rates .>= 0)

        # Mean should be close to long-run mean over time
        mean_terminal = mean(rates[:, end])
        @test 0.02 < mean_terminal < 0.08  # Reasonable range
    end

    @testset "generate_equity_scenarios" begin
        gen = ScenarioGenerator(n_scenarios=100, projection_years=30, seed=42)
        returns = generate_equity_scenarios(gen, mu=0.07, sigma=0.18)

        @test size(returns) == (100, 30)

        # Expected return should be positive on average
        mean_return = mean(returns)
        @test mean_return > 0
    end

    @testset "generate_deterministic_scenarios" begin
        scenarios = generate_deterministic_scenarios(n_years=30, base_rate=0.04)

        @test length(scenarios) == 3  # base, up, down

        # Base scenario
        @test all(scenarios[1].rates .≈ 0.04)
        @test all(scenarios[1].equity_returns .≈ 0.07)

        # Rate up scenario
        @test all(scenarios[2].rates .≈ 0.06)
        @test all(scenarios[2].equity_returns .≈ 0.05)

        # Rate down scenario
        @test all(scenarios[3].rates .≈ 0.02)
        @test all(scenarios[3].equity_returns .≈ 0.09)
    end

    @testset "correlation" begin
        gen = ScenarioGenerator(n_scenarios=1000, projection_years=30, seed=42)

        # Positive correlation
        scenarios_pos = generate_ag43_scenarios(gen, correlation=0.50)
        rate_matrix = get_rate_matrix(scenarios_pos)
        equity_matrix = get_equity_matrix(scenarios_pos)

        # Check correlation at each time point
        correlations = [cor(rate_matrix[:, t], equity_matrix[:, t]) for t in 1:30]
        mean_corr = mean(correlations)
        # With positive correlation, should be positive (though not exactly 0.50 due to Vasicek dynamics)
        @test mean_corr > 0

        # Negative correlation (default)
        gen2 = ScenarioGenerator(n_scenarios=1000, projection_years=30, seed=43)
        scenarios_neg = generate_ag43_scenarios(gen2, correlation=-0.50)
        rate_matrix_neg = get_rate_matrix(scenarios_neg)
        equity_matrix_neg = get_equity_matrix(scenarios_neg)
        correlations_neg = [cor(rate_matrix_neg[:, t], equity_matrix_neg[:, t]) for t in 1:30]
        mean_corr_neg = mean(correlations_neg)
        @test mean_corr_neg < 0
    end

    @testset "calculate_scenario_statistics" begin
        gen = ScenarioGenerator(n_scenarios=100, seed=42)
        scenarios = generate_ag43_scenarios(gen)
        stats = calculate_scenario_statistics(scenarios)

        @test haskey(stats, "rate_mean")
        @test haskey(stats, "rate_std")
        @test haskey(stats, "equity_return_mean")
        @test haskey(stats, "n_scenarios")

        @test stats["n_scenarios"] == 100
        @test stats["rate_mean"] > 0
        @test stats["rate_std"] > 0
    end

    #=========================================================================
    # VM-21 Types
    =========================================================================#

    @testset "PolicyData" begin
        @testset "construction" begin
            policy = PolicyData(av=100_000, gwb=110_000, age=70)
            @test policy.av == 100_000
            @test policy.gwb == 110_000
            @test policy.age == 70
            @test policy.withdrawal_rate == 0.05
            @test policy.fee_rate == 0.01
        end

        @testset "validation" begin
            @test_throws ErrorException PolicyData(av=-1000, gwb=110_000, age=70)
            @test_throws ErrorException PolicyData(av=100_000, gwb=-1000, age=70)
        end
    end

    #=========================================================================
    # VM-21 Calculator
    =========================================================================#

    @testset "VM21Calculator" begin
        @testset "construction" begin
            calc = VM21Calculator(n_scenarios=100, seed=42)
            @test calc.n_scenarios == 100
            @test calc.seed == 42
        end

        @testset "validation" begin
            @test_throws ErrorException VM21Calculator(n_scenarios=0)
        end
    end

    @testset "calculate_cte" begin
        calc = VM21Calculator()

        # Simple test case
        results = collect(100.0:100.0:1000.0)  # [100, 200, ..., 1000]

        # CTE70 = average of worst 30% = average of [800, 900, 1000] = 900
        cte70 = calculate_cte(calc, results, alpha=0.70)
        @test cte70 ≈ 900.0

        # CTE90 = average of worst 10% = [1000] = 1000
        cte90 = calculate_cte(calc, results, alpha=0.90)
        @test cte90 ≈ 1000.0

        # Validation
        @test_throws ErrorException calculate_cte(calc, Float64[], alpha=0.70)
        @test_throws ErrorException calculate_cte(calc, results, alpha=1.5)
        @test_throws ErrorException calculate_cte(calc, results, alpha=0.0)
    end

    @testset "calculate_cte70" begin
        calc = VM21Calculator()
        results = collect(100.0:100.0:1000.0)

        cte70 = calculate_cte70(calc, results)
        @test cte70 ≈ 900.0
    end

    @testset "calculate_cte_levels" begin
        results = collect(100.0:100.0:1000.0)
        ctes = calculate_cte_levels(results)

        @test haskey(ctes, "CTE70")
        @test haskey(ctes, "CTE90")
        @test ctes["CTE70"] ≈ 900.0
        @test ctes["CTE90"] ≈ 1000.0

        # CTE increases with alpha
        @test ctes["CTE70"] <= ctes["CTE75"]
        @test ctes["CTE75"] <= ctes["CTE80"]
    end

    @testset "calculate_reserve" begin
        calc = VM21Calculator(n_scenarios=50, projection_years=20, seed=42)
        policy = PolicyData(av=100_000, gwb=110_000, age=70)

        result = calculate_reserve(calc, policy)

        @test result isa VM21Result
        @test result.reserve >= 0
        @test result.reserve >= result.csv_floor
        @test result.scenario_count == 50
        @test result.mean_pv >= 0
        @test result.std_pv >= 0
    end

    @testset "vm21_sensitivity_analysis" begin
        policy = PolicyData(av=100_000, gwb=110_000, age=70)
        sens = vm21_sensitivity_analysis(policy, n_scenarios=50, seed=42)

        @test haskey(sens, "base_reserve")
        @test haskey(sens, "gwb_up_10pct")
        @test haskey(sens, "age_plus_5")
        @test haskey(sens, "av_down_20pct")
    end

    #=========================================================================
    # VM-22 Types
    =========================================================================#

    @testset "FixedAnnuityPolicy" begin
        @testset "construction" begin
            policy = FixedAnnuityPolicy(premium=100_000, guaranteed_rate=0.04, term_years=5)
            @test policy.premium == 100_000
            @test policy.guaranteed_rate == 0.04
            @test policy.term_years == 5
            @test policy.current_year == 0
        end

        @testset "get_av" begin
            policy = FixedAnnuityPolicy(premium=100_000, guaranteed_rate=0.04, term_years=5)
            @test get_av(policy) == 100_000

            policy_with_av = FixedAnnuityPolicy(
                premium=100_000, guaranteed_rate=0.04, term_years=5,
                account_value=120_000
            )
            @test get_av(policy_with_av) == 120_000
        end

        @testset "validation" begin
            @test_throws ErrorException FixedAnnuityPolicy(premium=0, guaranteed_rate=0.04, term_years=5)
            @test_throws ErrorException FixedAnnuityPolicy(premium=100_000, guaranteed_rate=-0.01, term_years=5)
        end
    end

    @testset "ReserveType" begin
        @test DETERMINISTIC isa ReserveType
        @test STOCHASTIC isa ReserveType
    end

    #=========================================================================
    # VM-22 Calculator
    =========================================================================#

    @testset "VM22Calculator" begin
        @testset "construction" begin
            calc = VM22Calculator(n_scenarios=100, seed=42)
            @test calc.n_scenarios == 100
            @test calc.seed == 42
        end
    end

    @testset "calculate_net_premium_reserve" begin
        calc = VM22Calculator()
        policy = FixedAnnuityPolicy(premium=100_000, guaranteed_rate=0.04, term_years=5)

        npr = calculate_net_premium_reserve(calc, policy, 0.04)

        # NPR should be approximately premium (discounted GMV at same rate)
        @test npr > 0
        @test npr < 200_000  # Reasonable upper bound
    end

    @testset "calculate_deterministic_reserve" begin
        calc = VM22Calculator()
        policy = FixedAnnuityPolicy(premium=100_000, guaranteed_rate=0.04, term_years=5)

        dr = calculate_deterministic_reserve(calc, policy, 0.04, 0.05)

        @test dr > 0
        @test dr < 200_000
    end

    @testset "stochastic_exclusion_test" begin
        calc = VM22Calculator()

        # Policy with rate = market rate should pass
        policy = FixedAnnuityPolicy(premium=100_000, guaranteed_rate=0.04, term_years=5)
        result = stochastic_exclusion_test(calc, policy, 0.04)
        @test result.passed == true
        @test result.ratio ≈ 1.0

        # Policy with high guaranteed rate vs low market rate may fail
        high_rate_policy = FixedAnnuityPolicy(premium=100_000, guaranteed_rate=0.08, term_years=10)
        result_high = stochastic_exclusion_test(calc, high_rate_policy, 0.02)
        @test result_high.ratio > 1.0  # Guaranteed exceeds market
    end

    @testset "single_scenario_test" begin
        calc = VM22Calculator()
        policy = FixedAnnuityPolicy(premium=100_000, guaranteed_rate=0.04, term_years=5)

        # Most simple policies should pass SST
        passed = single_scenario_test(calc, policy, 0.04, 0.05)
        @test passed isa Bool
    end

    @testset "calculate_reserve" begin
        calc = VM22Calculator(n_scenarios=50, seed=42)
        policy = FixedAnnuityPolicy(premium=100_000, guaranteed_rate=0.04, term_years=5)

        result = calculate_reserve(calc, policy, market_rate=0.04)

        @test result isa VM22Result
        @test result.reserve > 0
        @test result.net_premium_reserve > 0
        @test result.deterministic_reserve > 0
        @test result.reserve_type isa ReserveType
    end

    @testset "compare_reserve_methods" begin
        policy = FixedAnnuityPolicy(premium=100_000, guaranteed_rate=0.04, term_years=5)
        comparison = compare_reserve_methods(policy, n_scenarios=50, seed=42)

        @test haskey(comparison, "npr")
        @test haskey(comparison, "deterministic_reserve")
        @test haskey(comparison, "stochastic_reserve")
        @test haskey(comparison, "set_passed")

        @test comparison["npr"] > 0
        @test comparison["deterministic_reserve"] > 0
    end

    @testset "vm22_sensitivity" begin
        policy = FixedAnnuityPolicy(premium=100_000, guaranteed_rate=0.04, term_years=5)
        sens = vm22_sensitivity(policy, seed=42)

        @test haskey(sens, "base_reserve")
        @test haskey(sens, "rate_up_1pct")
        @test haskey(sens, "rate_down_1pct")
        @test haskey(sens, "lapse_up_2x")
        @test haskey(sens, "rate_sensitivity")

        @test sens["base_reserve"] > 0
    end

    #=========================================================================
    # Anti-Pattern Tests
    =========================================================================#

    @testset "Anti-Patterns" begin
        @testset "CTE bounds" begin
            calc = VM21Calculator()
            results = [100.0, 200.0, 300.0]

            # CTE should always be between min and max
            for alpha in [0.50, 0.70, 0.90]
                cte = calculate_cte(calc, results, alpha=alpha)
                @test cte >= minimum(results)
                @test cte <= maximum(results)
            end
        end

        @testset "reserve non-negativity" begin
            calc = VM22Calculator(n_scenarios=20, seed=42)
            policy = FixedAnnuityPolicy(premium=100_000, guaranteed_rate=0.04, term_years=5)

            result = calculate_reserve(calc, policy, market_rate=0.04)
            @test result.reserve >= 0
            @test result.net_premium_reserve >= 0
            @test result.deterministic_reserve >= 0
        end

        @testset "rates non-negative" begin
            gen = ScenarioGenerator(n_scenarios=100, seed=42)
            rates = generate_rate_scenarios(gen, initial_rate=0.04)

            # All rates should be non-negative (floored)
            @test all(rates .>= 0)
        end

        @testset "monotonic CTE levels" begin
            results = randn(1000) .* 100 .+ 500  # Random results
            ctes = calculate_cte_levels(results)

            # CTE should increase with alpha level
            @test ctes["CTE70"] <= ctes["CTE75"] + 1e-10  # Allow for numerical noise
            @test ctes["CTE75"] <= ctes["CTE80"] + 1e-10
            @test ctes["CTE80"] <= ctes["CTE85"] + 1e-10
        end
    end

    #=========================================================================
    # Integration Tests
    =========================================================================#

    @testset "Integration" begin
        @testset "VM-21 full workflow" begin
            # Create calculator
            calc = VM21Calculator(n_scenarios=100, projection_years=30, seed=42)

            # Create policy
            policy = PolicyData(av=100_000, gwb=120_000, age=65)

            # Generate scenarios
            scenarios = generate_ag43_scenarios(calc.scenario_generator)

            # Calculate reserve with pre-generated scenarios
            result = calculate_reserve(calc, policy, scenarios=scenarios)

            @test result.reserve >= result.csv_floor
            @test result.scenario_count == 100
        end

        @testset "VM-22 full workflow" begin
            # Create calculator
            calc = VM22Calculator(n_scenarios=100, seed=42)

            # Create policy
            policy = FixedAnnuityPolicy(premium=100_000, guaranteed_rate=0.045, term_years=7)

            # Calculate reserve
            result = calculate_reserve(calc, policy, market_rate=0.04)

            @test result.reserve > 0
            @test result.set_passed isa Bool
            @test result.sst_passed isa Bool
        end

        @testset "risk neutral vs real world" begin
            gen = ScenarioGenerator(n_scenarios=100, seed=42)

            # Real-world scenarios (higher drift)
            rw = generate_ag43_scenarios(gen, equity_params=EquityParams(mu=0.07))

            # Risk-neutral scenarios (lower drift)
            gen2 = ScenarioGenerator(n_scenarios=100, seed=42)
            rn = generate_risk_neutral_scenarios(gen2, dividend_yield=0.02)

            # Both should produce valid scenarios
            @test rw.n_scenarios == rn.n_scenarios
            @test length(rw.scenarios) == length(rn.scenarios)

            # Real-world should have higher average equity returns
            rw_mean = mean(get_equity_matrix(rw))
            rn_mean = mean(get_equity_matrix(rn))
            @test rw_mean > rn_mean
        end
    end

end  # @testset "Regulatory"
