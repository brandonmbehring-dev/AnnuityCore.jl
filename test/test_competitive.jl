"""
Comprehensive test suite for Competitive Analysis module.

Tests cover:
- Type validation and construction
- Positioning algorithms (percentile, rank, quartile)
- Filter functionality
- Company/product rankings
- Treasury spread analysis
- Anti-patterns (fail-fast on invalid inputs)
"""

using Test
using Dates
using Statistics

@testset "Competitive Analysis" begin

    #=========================================================================
    # Test Data Fixtures
    =========================================================================#

    # Standard test dataset
    function create_test_data()
        [
            WINKProduct("Athene", "Protector 5", 0.055, 5, "MYGA", :current),
            WINKProduct("Global Atlantic", "SecureGain 5", 0.054, 5, "MYGA", :current),
            WINKProduct("Oceanview", "Harbourview 5", 0.052, 5, "MYGA", :current),
            WINKProduct("American Equity", "Guarantee 5", 0.051, 5, "MYGA", :current),
            WINKProduct("Athene", "Protector 7", 0.058, 7, "MYGA", :current),
            WINKProduct("Athene", "Protector 3", 0.048, 3, "MYGA", :current),
            WINKProduct("Lincoln", "OptiChoice 5", 0.050, 5, "FIA", :current),
            WINKProduct("Allianz", "Elite 5", 0.045, 5, "RILA", :current),
            WINKProduct("Prudential", "FlexGuard 5", 0.040, 5, "RILA", :current),
            WINKProduct("Old Line", "Legacy 5", 0.049, 5, "MYGA", :discontinued),
        ]
    end

    # Standard treasury curve
    function create_test_curve()
        build_treasury_curve([(1, 0.040), (2, 0.042), (3, 0.044), (5, 0.045), (7, 0.047), (10, 0.050)])
    end

    #=========================================================================
    # Type Tests
    =========================================================================#

    @testset "WINKProduct Type" begin
        @testset "Valid construction" begin
            p = WINKProduct("Athene", "Protector 5", 0.055, 5, "MYGA", :current)
            @test p.company == "Athene"
            @test p.product == "Protector 5"
            @test p.rate == 0.055
            @test p.duration == 5
            @test p.product_group == "MYGA"
            @test p.status == :current
        end

        @testset "Keyword constructor" begin
            p = WINKProduct(
                company = "GA",
                product = "Test",
                rate = 0.05,
                duration = 3,
                product_group = "FIA"
            )
            @test p.status == :current  # Default
        end

        @testset "Validation - empty company" begin
            @test_throws ErrorException WINKProduct("", "Product", 0.05, 5, "MYGA", :current)
        end

        @testset "Validation - empty product" begin
            @test_throws ErrorException WINKProduct("Company", "", 0.05, 5, "MYGA", :current)
        end

        @testset "Validation - invalid duration" begin
            @test_throws ErrorException WINKProduct("Co", "Prod", 0.05, 0, "MYGA", :current)
            @test_throws ErrorException WINKProduct("Co", "Prod", 0.05, -1, "MYGA", :current)
        end

        @testset "Validation - invalid status" begin
            @test_throws ErrorException WINKProduct("Co", "Prod", 0.05, 5, "MYGA", :unknown)
        end
    end

    @testset "PositionResult Type" begin
        @testset "Valid construction" begin
            r = PositionResult(
                rate = 0.05,
                percentile = 75.0,
                rank = 3,
                total_products = 10,
                quartile = 1,
                position_label = "Top Quartile"
            )
            @test r.rate == 0.05
            @test r.percentile == 75.0
            @test r.rank == 3
        end

        @testset "Validation - percentile bounds" begin
            @test_throws ErrorException PositionResult(
                rate = 0.05, percentile = -1.0, rank = 1,
                total_products = 10, quartile = 1, position_label = "Test"
            )
            @test_throws ErrorException PositionResult(
                rate = 0.05, percentile = 101.0, rank = 1,
                total_products = 10, quartile = 1, position_label = "Test"
            )
        end

        @testset "Validation - rank bounds" begin
            @test_throws ErrorException PositionResult(
                rate = 0.05, percentile = 50.0, rank = 0,
                total_products = 10, quartile = 2, position_label = "Test"
            )
        end

        @testset "Validation - quartile bounds" begin
            @test_throws ErrorException PositionResult(
                rate = 0.05, percentile = 50.0, rank = 1,
                total_products = 10, quartile = 0, position_label = "Test"
            )
            @test_throws ErrorException PositionResult(
                rate = 0.05, percentile = 50.0, rank = 1,
                total_products = 10, quartile = 5, position_label = "Test"
            )
        end

        @testset "Validation - rank exceeds total" begin
            @test_throws ErrorException PositionResult(
                rate = 0.05, percentile = 50.0, rank = 11,
                total_products = 10, quartile = 2, position_label = "Test"
            )
        end
    end

    @testset "DistributionStats Type" begin
        @testset "From vector construction" begin
            rates = [0.03, 0.04, 0.05, 0.06]
            stats = DistributionStats(rates)
            @test stats.min == 0.03
            @test stats.max == 0.06
            @test stats.mean ≈ 0.045
            @test stats.median ≈ 0.045
            @test stats.count == 4
        end

        @testset "Validation - empty data" begin
            @test_throws ErrorException DistributionStats(Float64[])
        end

        @testset "Single value" begin
            stats = DistributionStats([0.05])
            @test stats.min == 0.05
            @test stats.max == 0.05
            @test stats.std == 0.0  # No variance with single value
        end
    end

    @testset "CompanyRanking Type" begin
        @testset "Valid construction" begin
            r = CompanyRanking(
                company = "Athene",
                rank = 1,
                best_rate = 0.058,
                avg_rate = 0.054,
                product_count = 3,
                duration_coverage = (3, 5, 7)
            )
            @test r.company == "Athene"
            @test r.duration_coverage == (3, 5, 7)
        end

        @testset "Validation - empty company" begin
            @test_throws ErrorException CompanyRanking(
                company = "", rank = 1, best_rate = 0.05,
                avg_rate = 0.05, product_count = 1, duration_coverage = (5,)
            )
        end
    end

    @testset "SpreadResult Type" begin
        @testset "Valid construction" begin
            r = SpreadResult(
                product_rate = 0.055,
                treasury_rate = 0.045,
                spread_bps = 100.0,
                spread_pct = 1.0,
                duration = 5,
                as_of_date = Date(2024, 1, 1)
            )
            @test r.spread_bps == 100.0
        end

        @testset "Negative spread allowed" begin
            r = SpreadResult(
                product_rate = 0.040,
                treasury_rate = 0.045,
                spread_bps = -50.0,
                spread_pct = -0.5,
                duration = 5,
                as_of_date = today()
            )
            @test r.spread_bps < 0  # Negative is allowed
        end
    end

    #=========================================================================
    # Positioning Tests
    =========================================================================#

    @testset "calculate_percentile" begin
        @testset "Basic percentile calculation" begin
            rates = [0.03, 0.04, 0.05, 0.06]
            # Count-based: count(x <= value) / total * 100
            @test calculate_percentile(0.03, rates) == 25.0   # 1/4
            @test calculate_percentile(0.04, rates) == 50.0   # 2/4
            @test calculate_percentile(0.05, rates) == 75.0   # 3/4
            @test calculate_percentile(0.06, rates) == 100.0  # 4/4
        end

        @testset "Percentile for value below minimum" begin
            rates = [0.03, 0.04, 0.05]
            @test calculate_percentile(0.02, rates) == 0.0  # None <= 0.02
        end

        @testset "Percentile for value above maximum" begin
            rates = [0.03, 0.04, 0.05]
            @test calculate_percentile(0.10, rates) == 100.0  # All <= 0.10
        end

        @testset "Empty distribution error" begin
            @test_throws ErrorException calculate_percentile(0.05, Float64[])
        end
    end

    @testset "calculate_rank" begin
        @testset "Basic rank calculation" begin
            rates = [0.03, 0.04, 0.05, 0.06]
            # Rank = count(x > value) + 1 (1 = highest)
            @test calculate_rank(0.06, rates) == 1  # None higher
            @test calculate_rank(0.05, rates) == 2  # One higher
            @test calculate_rank(0.04, rates) == 3  # Two higher
            @test calculate_rank(0.03, rates) == 4  # Three higher
        end

        @testset "Rank for value above maximum" begin
            rates = [0.03, 0.04, 0.05]
            @test calculate_rank(0.10, rates) == 1  # Best
        end

        @testset "Empty distribution error" begin
            @test_throws ErrorException calculate_rank(0.05, Float64[])
        end
    end

    @testset "calculate_quartile" begin
        @test calculate_quartile(100.0) == 1
        @test calculate_quartile(90.0) == 1
        @test calculate_quartile(75.0) == 1
        @test calculate_quartile(74.9) == 2
        @test calculate_quartile(50.0) == 2
        @test calculate_quartile(49.9) == 3
        @test calculate_quartile(25.0) == 3
        @test calculate_quartile(24.9) == 4
        @test calculate_quartile(0.0) == 4

        @testset "Invalid percentile" begin
            @test_throws ErrorException calculate_quartile(-1.0)
            @test_throws ErrorException calculate_quartile(101.0)
        end
    end

    @testset "get_position_label" begin
        @test get_position_label(95.0) == "Top 10%"
        @test get_position_label(90.0) == "Top 10%"
        @test get_position_label(89.0) == "Top Quartile"
        @test get_position_label(75.0) == "Top Quartile"
        @test get_position_label(60.0) == "Above Median"
        @test get_position_label(50.0) == "Above Median"
        @test get_position_label(30.0) == "Below Median"
        @test get_position_label(25.0) == "Below Median"
        @test get_position_label(10.0) == "Bottom Quartile"
    end

    @testset "filter_products" begin
        data = create_test_data()

        @testset "Filter by product_group" begin
            myga = filter_products(data, product_group = "MYGA")
            @test length(myga) == 6  # All current MYGA (3, 5, 7 year terms)
            @test all(p -> p.product_group == "MYGA", myga)
            @test all(p -> p.status == :current, myga)
        end

        @testset "Filter by duration" begin
            five_year = filter_products(data, duration = 5)
            @test all(p -> abs(p.duration - 5) <= 1, five_year)
        end

        @testset "Filter by status" begin
            discontinued = filter_products(data, status = :discontinued)
            @test length(discontinued) == 1
            @test discontinued[1].product == "Legacy 5"
        end

        @testset "Exclude company" begin
            no_athene = filter_products(data, exclude_company = "Athene")
            @test !any(p -> p.company == "Athene", no_athene)
        end

        @testset "Combined filters" begin
            result = filter_products(
                data,
                product_group = "MYGA",
                duration = 5,
                status = :current
            )
            @test all(p -> p.product_group == "MYGA", result)
            @test all(p -> p.status == :current, result)
            @test all(p -> abs(p.duration - 5) <= 1, result)
        end
    end

    @testset "analyze_position" begin
        data = create_test_data()

        @testset "Position analysis" begin
            # 0.053 is between 0.052 and 0.054 in MYGA 5-year
            result = analyze_position(0.053, data, product_group = "MYGA", duration = 5)
            @test 0.0 <= result.percentile <= 100.0
            @test result.rank >= 1
            @test 1 <= result.quartile <= 4
        end

        @testset "Top rate position" begin
            result = analyze_position(0.060, data, product_group = "MYGA", duration = 5)
            @test result.rank == 1
            @test result.percentile == 100.0
            @test result.position_label == "Top 10%"
        end

        @testset "Empty filter error" begin
            @test_throws ErrorException analyze_position(
                0.05, data, product_group = "NONEXISTENT"
            )
        end
    end

    @testset "get_distribution_stats" begin
        data = create_test_data()

        @testset "MYGA distribution" begin
            stats = get_distribution_stats(data, product_group = "MYGA")
            @test stats.min > 0
            @test stats.max > stats.min
            @test stats.min <= stats.median <= stats.max
            @test stats.count > 0
        end
    end

    @testset "compare_to_peers" begin
        data = create_test_data()

        @testset "Peer comparison" begin
            result = compare_to_peers(
                0.053, "TestCompany", data,
                product_group = "MYGA",
                duration = 5,
                top_n = 3
            )
            @test haskey(result, :position)
            @test haskey(result, :top_competitors)
            @test haskey(result, :gap_to_leader)
            @test haskey(result, :gap_to_median)
            @test length(result.top_competitors) <= 3
        end
    end

    #=========================================================================
    # Ranking Tests
    =========================================================================#

    @testset "calculate_tier" begin
        @test calculate_tier(80.0) == "Leader"
        @test calculate_tier(75.0) == "Leader"
        @test calculate_tier(60.0) == "Competitive"
        @test calculate_tier(50.0) == "Competitive"
        @test calculate_tier(40.0) == "Follower"
        @test calculate_tier(0.0) == "Follower"
    end

    @testset "group_by_company" begin
        data = create_test_data()
        by_company = group_by_company(data)

        @test haskey(by_company, "Athene")
        @test length(by_company["Athene"]) == 3  # Three Athene products
    end

    @testset "group_by_duration" begin
        data = create_test_data()
        by_duration = group_by_duration(data)

        @test haskey(by_duration, 5)
        @test haskey(by_duration, 7)
        @test haskey(by_duration, 3)
    end

    @testset "rank_companies" begin
        data = create_test_data()

        @testset "Rank by best rate" begin
            rankings = rank_companies(data, rank_by = BEST_RATE, product_group = "MYGA")
            @test rankings[1].rank == 1
            @test rankings[1].best_rate >= rankings[2].best_rate
            # Athene should be #1 (0.058 best rate)
            @test rankings[1].company == "Athene"
        end

        @testset "Rank by average rate" begin
            rankings = rank_companies(data, rank_by = AVG_RATE, product_group = "MYGA")
            @test rankings[1].rank == 1
            @test rankings[1].avg_rate >= rankings[2].avg_rate
        end

        @testset "Rank by product count" begin
            rankings = rank_companies(data, rank_by = PRODUCT_COUNT, product_group = "MYGA")
            @test rankings[1].product_count >= rankings[2].product_count
        end

        @testset "Top N limit" begin
            rankings = rank_companies(data, top_n = 2)
            @test length(rankings) == 2
        end
    end

    @testset "rank_products" begin
        data = create_test_data()

        @testset "Product rankings by rate" begin
            rankings = rank_products(data, product_group = "MYGA")
            @test rankings[1].rank == 1
            @test rankings[1].rate >= rankings[2].rate
        end

        @testset "Top N limit" begin
            rankings = rank_products(data, top_n = 3)
            @test length(rankings) == 3
        end
    end

    @testset "get_company_rank" begin
        data = create_test_data()

        @testset "Find existing company" begin
            ranking = get_company_rank("Athene", data, product_group = "MYGA")
            @test !isnothing(ranking)
            @test ranking.company == "Athene"
        end

        @testset "Case insensitive" begin
            ranking = get_company_rank("athene", data, product_group = "MYGA")
            @test !isnothing(ranking)
        end

        @testset "Non-existent company" begin
            ranking = get_company_rank("Nonexistent", data)
            @test isnothing(ranking)
        end
    end

    @testset "market_summary" begin
        data = create_test_data()

        @testset "Full market summary" begin
            summary = market_summary(data, product_group = "MYGA")
            @test summary.total_products > 0
            @test summary.total_companies > 0
            @test !isempty(summary.product_groups)
        end
    end

    @testset "rate_leaders_by_duration" begin
        data = create_test_data()

        @testset "Leaders per duration" begin
            leaders = rate_leaders_by_duration(data, product_group = "MYGA", top_n = 2)
            @test haskey(leaders, 5)
            @test haskey(leaders, 7)
            @test length(leaders[5]) <= 2
        end
    end

    @testset "competitive_landscape" begin
        data = create_test_data()

        @testset "Full landscape analysis" begin
            landscape = competitive_landscape(data, product_group = "MYGA")
            @test landscape.market.total_products > 0
            @test length(landscape.company_rankings) > 0
            @test length(landscape.product_rankings) > 0
            @test haskey(landscape.tier_distribution, "Leader")
            @test haskey(landscape.tier_distribution, "Competitive")
            @test haskey(landscape.tier_distribution, "Follower")
        end
    end

    #=========================================================================
    # Spread Tests
    =========================================================================#

    @testset "interpolate_treasury" begin
        curve = create_test_curve()

        @testset "Exact match" begin
            @test interpolate_treasury(5, curve) == 0.045
            @test interpolate_treasury(7, curve) == 0.047
        end

        @testset "Linear interpolation" begin
            # Between 5 (0.045) and 7 (0.047)
            rate_6 = interpolate_treasury(6, curve)
            @test 0.045 < rate_6 < 0.047
            @test rate_6 ≈ 0.046  # Linear midpoint
        end

        @testset "Flat extrapolation - below minimum" begin
            @test_throws ErrorException interpolate_treasury(0, curve)  # Invalid duration
            # Duration 1 exists, so no extrapolation needed for valid durations
        end

        @testset "Flat extrapolation - above maximum" begin
            @test interpolate_treasury(15, curve) == 0.050  # Max is 10 -> 0.050
            @test interpolate_treasury(20, curve) == 0.050
        end

        @testset "Empty curve error" begin
            @test_throws ErrorException interpolate_treasury(5, Dict{Int, Float64}())
        end
    end

    @testset "build_treasury_curve" begin
        @testset "From tuples" begin
            curve = build_treasury_curve([(1, 0.04), (5, 0.045)])
            @test curve[1] == 0.04
            @test curve[5] == 0.045
        end

        @testset "From parallel vectors" begin
            curve = build_treasury_curve([1, 5, 10], [0.04, 0.045, 0.05])
            @test length(curve) == 3
        end

        @testset "From FRED series" begin
            fred_rates = Dict("DGS1" => 0.04, "DGS5" => 0.045, "DGS10" => 0.05)
            curve = build_treasury_curve(fred_rates)
            @test curve[1] == 0.04
            @test curve[5] == 0.045
            @test curve[10] == 0.05
        end
    end

    @testset "calculate_spread" begin
        @testset "Positive spread" begin
            result = calculate_spread(0.055, 0.045, 5)
            @test result.product_rate ≈ 0.055
            @test result.treasury_rate ≈ 0.045
            @test result.spread_bps ≈ 100.0  # (0.055 - 0.045) * 10000
            @test result.spread_pct ≈ 1.0
            @test result.duration == 5
        end

        @testset "Negative spread" begin
            result = calculate_spread(0.040, 0.045, 5)
            @test result.spread_bps ≈ -50.0
        end

        @testset "Zero spread" begin
            result = calculate_spread(0.045, 0.045, 5)
            @test result.spread_bps ≈ 0.0
        end
    end

    @testset "calculate_market_spreads" begin
        data = create_test_data()
        curve = create_test_curve()

        @testset "All products" begin
            spreads = calculate_market_spreads(data, curve, product_group = "MYGA")
            @test length(spreads) > 0
            @test all(ps -> isa(ps.spread, SpreadResult), spreads)
        end
    end

    @testset "get_spread_distribution" begin
        data = create_test_data()
        curve = create_test_curve()

        @testset "Distribution stats" begin
            dist = get_spread_distribution(data, curve, product_group = "MYGA")
            @test dist.count > 0
            @test dist.min_bps <= dist.median_bps <= dist.max_bps
        end
    end

    @testset "analyze_spread_position" begin
        data = create_test_data()
        curve = create_test_curve()

        @testset "Position by spread" begin
            position = analyze_spread_position(100.0, data, curve, product_group = "MYGA")
            @test 0.0 <= position.percentile <= 100.0
            @test position.rank >= 1
        end
    end

    @testset "spread_by_duration" begin
        data = create_test_data()
        curve = create_test_curve()

        @testset "Grouped by duration" begin
            by_duration = spread_by_duration(data, curve, product_group = "MYGA")
            @test haskey(by_duration, 5)
            @test by_duration[5].product_count > 0
            @test by_duration[5].treasury_rate > 0
        end
    end

    #=========================================================================
    # Anti-Pattern Tests (Fail-Fast Behavior)
    =========================================================================#

    @testset "Anti-Patterns" begin
        @testset "Empty data errors" begin
            empty_data = WINKProduct[]
            curve = create_test_curve()

            # filter_products returns empty vector (doesn't throw - it's just a filter)
            @test isempty(filter_products(empty_data))

            # Functions that analyze/process data MUST throw on empty
            @test_throws ErrorException analyze_position(0.05, empty_data)
            @test_throws ErrorException rank_companies(empty_data)
            @test_throws ErrorException rank_products(empty_data)
            @test_throws ErrorException market_summary(empty_data)
            @test_throws ErrorException calculate_market_spreads(empty_data, curve)
        end

        @testset "Invalid type construction" begin
            # All these should fail loudly
            @test_throws ErrorException WINKProduct("", "p", 0.05, 5, "M", :current)
            @test_throws ErrorException PositionResult(
                rate=0.05, percentile=150.0, rank=1,
                total_products=10, quartile=1, position_label="x"
            )
            @test_throws ErrorException CompanyRanking(
                company="", rank=1, best_rate=0.05,
                avg_rate=0.05, product_count=1, duration_coverage=(5,)
            )
        end

        @testset "No silent failures" begin
            data = create_test_data()

            # Filter to empty should error, not return empty
            @test_throws ErrorException analyze_position(
                0.05, data, product_group = "NONEXISTENT"
            )

            # Distribution on empty should error
            @test_throws ErrorException DistributionStats(Float64[])
            @test_throws ErrorException SpreadDistribution(Float64[])
        end
    end

    #=========================================================================
    # Utility Function Tests
    =========================================================================#

    @testset "Utility Functions" begin
        data = create_test_data()

        @testset "rates()" begin
            r = rates(data)
            @test length(r) == length(data)
            @test all(x -> x > 0, r)
        end

        @testset "durations()" begin
            d = durations(data)
            @test length(d) == length(data)
            @test all(x -> x >= 1, d)
        end

        @testset "companies()" begin
            c = companies(data)
            @test "Athene" in c
            @test length(c) < length(data)  # Unique
        end
    end

    #=========================================================================
    # Display Function Tests
    =========================================================================#

    @testset "Display Functions" begin
        data = create_test_data()
        curve = create_test_curve()

        @testset "position_summary" begin
            result = analyze_position(0.05, data, product_group = "MYGA")
            summary = position_summary(result)
            @test occursin("Rate", summary)
            @test occursin("ranks", summary)
        end

        @testset "print_company_rankings" begin
            rankings = rank_companies(data, product_group = "MYGA", top_n = 3)
            io = IOBuffer()
            print_company_rankings(rankings, io = io)
            output = String(take!(io))
            @test occursin("Company Rankings", output)
        end

        @testset "print_product_rankings" begin
            rankings = rank_products(data, product_group = "MYGA", top_n = 3)
            io = IOBuffer()
            print_product_rankings(rankings, io = io)
            output = String(take!(io))
            @test occursin("Product Rankings", output)
        end

        @testset "print_spread_distribution" begin
            dist = get_spread_distribution(data, curve, product_group = "MYGA")
            io = IOBuffer()
            print_spread_distribution(dist, io = io)
            output = String(take!(io))
            @test occursin("Spread Distribution", output)
            @test occursin("bps", output)
        end

        @testset "print_spread_by_duration" begin
            by_duration = spread_by_duration(data, curve, product_group = "MYGA")
            io = IOBuffer()
            print_spread_by_duration(by_duration, io = io)
            output = String(take!(io))
            @test occursin("Spreads by Duration", output)
        end
    end

    #=========================================================================
    # Integration Tests
    =========================================================================#

    @testset "Integration" begin
        data = create_test_data()
        curve = create_test_curve()

        @testset "Full workflow - Positioning" begin
            # Filter → Position → Summary
            filtered = filter_products(data, product_group = "MYGA", duration = 5)
            position = analyze_position(0.053, filtered)
            summary = position_summary(position)

            @test length(filtered) > 0
            @test position.total_products == length(filtered)
            @test length(summary) > 0
        end

        @testset "Full workflow - Ranking" begin
            # Rank → Get single → Compare
            rankings = rank_companies(data, product_group = "MYGA")
            single = get_company_rank("Athene", data, product_group = "MYGA")

            @test !isnothing(single)
            @test single.rank <= length(rankings)
        end

        @testset "Full workflow - Spreads" begin
            # Curve → Spreads → Distribution → Position
            spreads = calculate_market_spreads(data, curve, product_group = "MYGA")
            dist = get_spread_distribution(data, curve, product_group = "MYGA")
            position = analyze_spread_position(100.0, data, curve, product_group = "MYGA")

            @test length(spreads) == dist.count
            @test position.total_products == dist.count
        end
    end

end  # Main testset
