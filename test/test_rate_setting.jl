"""
Tests for the Rate Setting module.

Covers:
- Core types (RateRecommendation, MarginAnalysis, SensitivityPoint)
- Percentile-based recommendations
- Spread-based recommendations
- Margin analysis
- Sensitivity analysis
- Edge cases and anti-patterns
"""

@testset "Rate Setting" begin

    # Sample market data for testing
    function create_test_products()
        [
            WINKProduct("Company A", "MYGA 5", 0.040, 5, "MYGA", :current),
            WINKProduct("Company B", "MYGA 5", 0.045, 5, "MYGA", :current),
            WINKProduct("Company C", "MYGA 5", 0.048, 5, "MYGA", :current),
            WINKProduct("Company D", "MYGA 5", 0.050, 5, "MYGA", :current),
            WINKProduct("Company E", "MYGA 5", 0.052, 5, "MYGA", :current),
            WINKProduct("Company F", "MYGA 5", 0.055, 5, "MYGA", :current),
        ]
    end

    function create_large_test_products()
        # Create 50+ products for high-confidence testing
        rates = [0.040 + i * 0.001 for i in 0:59]
        [
            WINKProduct("Company $i", "MYGA 5", r, 5, "MYGA", :current)
            for (i, r) in enumerate(rates)
        ]
    end

    #=========================================================================
    # Core Types Tests
    =========================================================================#

    @testset "RateRecommendation" begin
        @testset "Construction" begin
            rec = RateRecommendation(
                recommended_rate = 0.048,
                target_percentile = 75.0,
                spread_over_treasury = 80.0,
                margin_estimate = 30.0,
                confidence = HIGH,
                rationale = "Test rationale",
                comparable_count = 50
            )
            @test rec.recommended_rate == 0.048
            @test rec.target_percentile == 75.0
            @test rec.spread_over_treasury == 80.0
            @test rec.margin_estimate == 30.0
            @test rec.confidence == HIGH
            @test rec.comparable_count == 50
        end

        @testset "Defaults" begin
            rec = RateRecommendation(
                recommended_rate = 0.05,
                target_percentile = 50.0
            )
            @test rec.spread_over_treasury === nothing
            @test rec.margin_estimate === nothing
            @test rec.confidence == MEDIUM
            @test rec.rationale == ""
            @test rec.comparable_count == 0
        end

        @testset "Validation - negative rate" begin
            @test_throws ErrorException RateRecommendation(
                recommended_rate = -0.01,
                target_percentile = 50.0
            )
        end

        @testset "Validation - percentile out of range" begin
            @test_throws ErrorException RateRecommendation(
                recommended_rate = 0.05,
                target_percentile = 150.0
            )
            @test_throws ErrorException RateRecommendation(
                recommended_rate = 0.05,
                target_percentile = -10.0
            )
        end
    end

    @testset "MarginAnalysis" begin
        @testset "Construction" begin
            margin = MarginAnalysis(
                gross_spread = 80.0,
                option_cost = 0.0,
                expense_load = 50.0,
                net_margin = 30.0
            )
            @test margin.gross_spread == 80.0
            @test margin.option_cost == 0.0
            @test margin.expense_load == 50.0
            @test margin.net_margin == 30.0
        end

        @testset "Positional constructor" begin
            margin = MarginAnalysis(100.0, 0.0, 50.0, 50.0)
            @test margin.gross_spread == 100.0
            @test margin.net_margin == 50.0
        end
    end

    @testset "SensitivityPoint" begin
        @testset "Successful point" begin
            pt = SensitivityPoint(
                percentile = 75.0,
                rate = 0.048,
                spread_bps = 80.0,
                margin_bps = 30.0,
                comparable_count = 50
            )
            @test pt.percentile == 75.0
            @test pt.rate == 0.048
            @test pt.error === nothing
        end

        @testset "Error point" begin
            pt = SensitivityPoint(
                percentile = 99.0,
                error = "No comparables found"
            )
            @test pt.rate === nothing
            @test pt.error !== nothing
        end
    end

    @testset "ConfidenceLevel" begin
        @test confidence_string(HIGH) == "high"
        @test confidence_string(MEDIUM) == "medium"
        @test confidence_string(LOW) == "low"
    end

    #=========================================================================
    # RateRecommenderConfig Tests
    =========================================================================#

    @testset "RateRecommenderConfig" begin
        @testset "Default config" begin
            config = RateRecommenderConfig()
            @test config.default_expense_load == 0.0050
            @test config.duration_tolerance == 1
            @test config.min_comparables == 5
        end

        @testset "Custom config" begin
            config = RateRecommenderConfig(
                default_expense_load = 0.0075,
                duration_tolerance = 2,
                min_comparables = 10
            )
            @test config.default_expense_load == 0.0075
            @test config.duration_tolerance == 2
            @test config.min_comparables == 10
        end

        @testset "Validation" begin
            @test_throws ErrorException RateRecommenderConfig(default_expense_load = -0.01)
            @test_throws ErrorException RateRecommenderConfig(duration_tolerance = -1)
            @test_throws ErrorException RateRecommenderConfig(min_comparables = 0)
        end

        @testset "DEFAULT_RECOMMENDER_CONFIG" begin
            @test DEFAULT_RECOMMENDER_CONFIG isa RateRecommenderConfig
            @test DEFAULT_RECOMMENDER_CONFIG.default_expense_load == 0.0050
        end
    end

    #=========================================================================
    # recommend_rate Tests
    =========================================================================#

    @testset "recommend_rate" begin
        products = create_test_products()

        @testset "Basic recommendation" begin
            rec = recommend_rate(5, 50.0, products)
            @test rec.recommended_rate > 0
            @test rec.target_percentile == 50.0
            @test rec.comparable_count == length(products)
        end

        @testset "With treasury rate" begin
            rec = recommend_rate(5, 75.0, products, treasury_rate = 0.04)
            @test rec.spread_over_treasury !== nothing
            @test rec.margin_estimate !== nothing
            @test rec.spread_over_treasury > 0  # Rate should exceed treasury
        end

        @testset "Percentile ordering" begin
            rec25 = recommend_rate(5, 25.0, products)
            rec50 = recommend_rate(5, 50.0, products)
            rec75 = recommend_rate(5, 75.0, products)

            @test rec25.recommended_rate < rec50.recommended_rate
            @test rec50.recommended_rate < rec75.recommended_rate
        end

        @testset "Edge percentiles" begin
            rec0 = recommend_rate(5, 0.0, products)
            rec100 = recommend_rate(5, 100.0, products)

            @test rec0.recommended_rate ≈ 0.040 atol=0.001  # Min rate
            @test rec100.recommended_rate ≈ 0.055 atol=0.001  # Max rate
        end

        @testset "Validation - invalid percentile" begin
            @test_throws ErrorException recommend_rate(5, 150.0, products)
            @test_throws ErrorException recommend_rate(5, -10.0, products)
        end

        @testset "Validation - invalid duration" begin
            @test_throws ErrorException recommend_rate(0, 50.0, products)
            @test_throws ErrorException recommend_rate(-5, 50.0, products)
        end

        @testset "No matching products" begin
            # Duration 10 with tolerance 1 won't match duration 5 products
            @test_throws ErrorException recommend_rate(10, 50.0, products)
        end
    end

    #=========================================================================
    # recommend_for_spread Tests
    =========================================================================#

    @testset "recommend_for_spread" begin
        products = create_test_products()

        @testset "Basic spread recommendation" begin
            rec = recommend_for_spread(5, 0.04, 100.0, products)
            @test rec.recommended_rate ≈ 0.05 atol=1e-10  # 4% + 100bps
            @test rec.spread_over_treasury == 100.0
        end

        @testset "Spread affects percentile" begin
            rec_low = recommend_for_spread(5, 0.04, 50.0, products)
            rec_high = recommend_for_spread(5, 0.04, 150.0, products)

            @test rec_low.target_percentile < rec_high.target_percentile
        end

        @testset "Margin calculation" begin
            rec = recommend_for_spread(5, 0.04, 100.0, products)
            # 100 bps spread - 50 bps expense = 50 bps margin
            @test rec.margin_estimate ≈ 50.0 atol=1e-10
        end

        @testset "Validation - negative treasury" begin
            @test_throws ErrorException recommend_for_spread(5, -0.01, 100.0, products)
        end

        @testset "No matching products" begin
            @test_throws ErrorException recommend_for_spread(10, 0.04, 100.0, products)
        end
    end

    #=========================================================================
    # analyze_margin Tests
    =========================================================================#

    @testset "analyze_margin" begin
        @testset "Basic margin analysis" begin
            margin = analyze_margin(0.048, 0.040)

            @test margin.gross_spread ≈ 80.0 atol=1e-10  # (4.8% - 4%) * 10000
            @test margin.option_cost == 0.0  # MYGA has no option cost
            @test margin.expense_load ≈ 50.0 atol=1e-10  # Default 50 bps
            @test margin.net_margin ≈ 30.0 atol=1e-10  # 80 - 0 - 50
        end

        @testset "Custom expense load" begin
            margin = analyze_margin(0.048, 0.040, expense_load = 0.0075)

            @test margin.expense_load ≈ 75.0 atol=1e-10
            @test margin.net_margin ≈ 5.0 atol=1e-10  # 80 - 0 - 75
        end

        @testset "Negative margin" begin
            margin = analyze_margin(0.041, 0.040)

            @test margin.gross_spread ≈ 10.0 atol=1e-10
            @test margin.net_margin ≈ -40.0 atol=1e-10  # 10 - 50 = -40
        end

        @testset "Zero spread" begin
            margin = analyze_margin(0.040, 0.040)

            @test margin.gross_spread ≈ 0.0 atol=1e-10
            @test margin.net_margin ≈ -50.0 atol=1e-10
        end
    end

    #=========================================================================
    # sensitivity_analysis Tests
    =========================================================================#

    @testset "sensitivity_analysis" begin
        products = create_test_products()

        @testset "Default percentiles" begin
            results = sensitivity_analysis(5, products, 0.04)

            @test length(results) == 4  # Default: [25, 50, 75, 90]
            @test all(pt -> pt.percentile in [25.0, 50.0, 75.0, 90.0], results)
        end

        @testset "Custom percentiles" begin
            results = sensitivity_analysis(5, products, 0.04,
                percentile_range = [10.0, 50.0, 90.0])

            @test length(results) == 3
        end

        @testset "Results have required fields" begin
            results = sensitivity_analysis(5, products, 0.04)

            for pt in results
                @test pt.rate !== nothing
                @test pt.spread_bps !== nothing
                @test pt.margin_bps !== nothing
                @test pt.comparable_count > 0
                @test pt.error === nothing
            end
        end

        @testset "Rates increase with percentile" begin
            results = sensitivity_analysis(5, products, 0.04)

            rates = [pt.rate for pt in results]
            @test issorted(rates)
        end
    end

    #=========================================================================
    # get_comparables Tests
    =========================================================================#

    @testset "get_comparables" begin
        products = [
            WINKProduct("A", "MYGA 5", 0.045, 5, "MYGA", :current),
            WINKProduct("B", "MYGA 3", 0.040, 3, "MYGA", :current),
            WINKProduct("C", "MYGA 7", 0.050, 7, "MYGA", :current),
            WINKProduct("D", "MYGA 5", 0.048, 5, "MYGA", :discontinued),
            WINKProduct("E", "FIA 5", 0.055, 5, "FIA", :current),
        ]

        config = RateRecommenderConfig(duration_tolerance = 1)

        @testset "Filters by duration" begin
            comparables = get_comparables(products, 5, config)
            @test all(p -> abs(p.duration - 5) <= 1, comparables)
        end

        @testset "Filters by status" begin
            comparables = get_comparables(products, 5, config)
            @test all(p -> p.status == :current, comparables)
        end

        @testset "Filters by product group" begin
            comparables = get_comparables(products, 5, config)
            @test all(p -> p.product_group == "MYGA", comparables)
        end

        @testset "Duration tolerance" begin
            # Duration 5 with tolerance 1 should include 4, 5, 6
            config_wide = RateRecommenderConfig(duration_tolerance = 2)
            comparables = get_comparables(products, 5, config_wide)
            # Should include duration 3 (5-2=3) and duration 7 (5+2=7)
            durations = Set(p.duration for p in comparables)
            @test 3 in durations
            @test 7 in durations
        end
    end

    #=========================================================================
    # assess_confidence Tests
    =========================================================================#

    @testset "assess_confidence" begin
        @testset "High confidence - large sample, good margin" begin
            @test assess_confidence(100, 50.0, 150.0) == HIGH
        end

        @testset "Medium confidence - default" begin
            @test assess_confidence(25, 50.0, 50.0) == MEDIUM
        end

        @testset "Low confidence - small sample" begin
            @test assess_confidence(5, 50.0, 50.0) == LOW
        end

        @testset "Low confidence - extreme percentile" begin
            @test assess_confidence(25, 99.0, 50.0) == LOW
        end

        @testset "Low confidence - negative margin" begin
            @test assess_confidence(25, 50.0, -20.0) == LOW
        end

        @testset "Nothing margin handled" begin
            conf = assess_confidence(50, 50.0, nothing)
            @test conf isa ConfidenceLevel
        end
    end

    #=========================================================================
    # Convenience Functions Tests
    =========================================================================#

    @testset "quick_rate_recommendation" begin
        rates = [0.040, 0.045, 0.048, 0.050, 0.052, 0.055]

        @testset "Basic usage" begin
            rec = quick_rate_recommendation(5, 50.0, rates)
            @test rec.recommended_rate > 0
            @test rec.target_percentile == 50.0
        end

        @testset "With treasury" begin
            rec = quick_rate_recommendation(5, 75.0, rates, treasury_rate = 0.04)
            @test rec.spread_over_treasury !== nothing
        end
    end

    @testset "rate_grid" begin
        @testset "Basic grid" begin
            grid = rate_grid(0.04, (50, 100), step_bps = 25)

            @test length(grid) == 3  # 50, 75, 100
            @test grid[1] == (0.045, 50.0)
            @test grid[2] == (0.0475, 75.0)
            @test grid[3] == (0.05, 100.0)
        end

        @testset "Fine grid" begin
            grid = rate_grid(0.04, (50, 70), step_bps = 10)

            @test length(grid) == 3  # 50, 60, 70
        end
    end

    #=========================================================================
    # Integration Tests
    =========================================================================#

    @testset "Integration" begin
        products = create_large_test_products()

        @testset "Full workflow" begin
            # 1. Get percentile-based recommendation
            rec = recommend_rate(5, 75.0, products, treasury_rate = 0.04)
            @test rec.confidence == HIGH  # Large sample

            # 2. Analyze margin
            margin = analyze_margin(rec.recommended_rate, 0.04)
            @test margin.net_margin > 0  # Should have positive margin

            # 3. Compare with spread-based recommendation
            rec2 = recommend_for_spread(5, 0.04, margin.gross_spread, products)
            @test rec2.recommended_rate ≈ rec.recommended_rate atol=0.001
        end

        @testset "Sensitivity matches individual recommendations" begin
            results = sensitivity_analysis(5, products, 0.04)

            for pt in results
                individual_rec = recommend_rate(5, pt.percentile, products, treasury_rate = 0.04)
                @test pt.rate ≈ individual_rec.recommended_rate atol=1e-10
            end
        end
    end

    #=========================================================================
    # Anti-Pattern Tests
    =========================================================================#

    @testset "Anti-Patterns" begin
        products = create_test_products()

        @testset "Empty products fails" begin
            @test_throws ErrorException recommend_rate(5, 50.0, WINKProduct[])
        end

        @testset "All discontinued fails" begin
            discontinued = [
                WINKProduct("A", "MYGA 5", 0.045, 5, "MYGA", :discontinued),
                WINKProduct("B", "MYGA 5", 0.048, 5, "MYGA", :discontinued),
            ]
            @test_throws ErrorException recommend_rate(5, 50.0, discontinued)
        end

        @testset "Negative rate not allowed" begin
            @test_throws ErrorException RateRecommendation(
                recommended_rate = -0.01,
                target_percentile = 50.0
            )
        end

        @testset "Percentile bounds enforced" begin
            @test_throws ErrorException recommend_rate(5, 101.0, products)
        end
    end

    #=========================================================================
    # Display Tests
    =========================================================================#

    @testset "Display" begin
        @testset "RateRecommendation show" begin
            rec = RateRecommendation(
                recommended_rate = 0.048,
                target_percentile = 75.0,
                confidence = HIGH,
                comparable_count = 50
            )
            io = IOBuffer()
            show(io, rec)
            str = String(take!(io))
            @test occursin("4.8", str)
            @test occursin("75", str)
            @test occursin("high", str)
        end

        @testset "MarginAnalysis show" begin
            margin = MarginAnalysis(80.0, 0.0, 50.0, 30.0)
            io = IOBuffer()
            show(io, margin)
            str = String(take!(io))
            @test occursin("80", str)
            @test occursin("30", str)
        end

        @testset "print_recommendation" begin
            rec = RateRecommendation(
                recommended_rate = 0.048,
                target_percentile = 75.0,
                spread_over_treasury = 80.0,
                margin_estimate = 30.0,
                confidence = HIGH,
                rationale = "Test",
                comparable_count = 50
            )
            io = IOBuffer()
            print_recommendation(rec, io = io)
            str = String(take!(io))
            @test occursin("Rate Recommendation", str)
            @test occursin("Spread", str)
        end

        @testset "print_margin_analysis" begin
            margin = MarginAnalysis(80.0, 0.0, 50.0, 30.0)
            io = IOBuffer()
            print_margin_analysis(margin, io = io)
            str = String(take!(io))
            @test occursin("Margin Analysis", str)
            @test occursin("Net Margin", str)
        end

        @testset "print_sensitivity_analysis" begin
            results = [
                SensitivityPoint(percentile = 50.0, rate = 0.048, spread_bps = 80.0,
                                 margin_bps = 30.0, comparable_count = 50),
                SensitivityPoint(percentile = 75.0, rate = 0.052, spread_bps = 120.0,
                                 margin_bps = 70.0, comparable_count = 50),
            ]
            io = IOBuffer()
            print_sensitivity_analysis(results, io = io)
            str = String(take!(io))
            @test occursin("Sensitivity", str)
            @test occursin("50th", str)
            @test occursin("75th", str)
        end

        @testset "compare_recommendations" begin
            recs = [
                RateRecommendation(recommended_rate = 0.045, target_percentile = 25.0,
                                   confidence = MEDIUM, comparable_count = 50),
                RateRecommendation(recommended_rate = 0.050, target_percentile = 75.0,
                                   confidence = HIGH, comparable_count = 50),
            ]
            io = IOBuffer()
            compare_recommendations(recs, io = io)
            str = String(take!(io))
            @test occursin("Comparison", str)
            @test occursin("25th", str)
            @test occursin("75th", str)
        end
    end

end
