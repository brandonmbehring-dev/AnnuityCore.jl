"""
Comprehensive test suite for Credit Risk module.

Tests cover:
- AM Best rating types and parsing
- Probability of default data and interpolation
- State guaranty fund coverage
- CVA calculations
- Anti-patterns (fail-fast on invalid inputs)
"""

using Test
using Statistics

@testset "Credit Risk" begin

    #=========================================================================
    # AM Best Rating Tests
    =========================================================================#

    @testset "AMBestRating Enum" begin
        @testset "All 16 ratings exist" begin
            @test length(instances(AMBestRating)) == 16
        end

        @testset "Rating strings" begin
            @test rating_to_string(A_PLUS_PLUS) == "A++"
            @test rating_to_string(A_PLUS) == "A+"
            @test rating_to_string(A) == "A"
            @test rating_to_string(A_MINUS) == "A-"
            @test rating_to_string(B_PLUS_PLUS) == "B++"
            @test rating_to_string(B_PLUS) == "B+"
            @test rating_to_string(B) == "B"
            @test rating_to_string(B_MINUS) == "B-"
        end

        @testset "Secure vs Vulnerable" begin
            # Secure ratings
            @test is_secure(A_PLUS_PLUS)
            @test is_secure(A_PLUS)
            @test is_secure(A)
            @test is_secure(A_MINUS)
            @test is_secure(B_PLUS_PLUS)
            @test is_secure(B_PLUS)

            # Vulnerable ratings
            @test is_vulnerable(B)
            @test is_vulnerable(B_MINUS)
            @test is_vulnerable(C)
            @test is_vulnerable(D)
            @test is_vulnerable(F)
        end
    end

    @testset "rating_from_string" begin
        @testset "Valid ratings" begin
            @test rating_from_string("A++") == A_PLUS_PLUS
            @test rating_from_string("A+") == A_PLUS
            @test rating_from_string("A") == A
            @test rating_from_string("A-") == A_MINUS
            @test rating_from_string("B++") == B_PLUS_PLUS
            @test rating_from_string("b+") == B_PLUS  # Case insensitive
            @test rating_from_string(" A ") == A  # Whitespace handling
        end

        @testset "Invalid rating throws" begin
            @test_throws ErrorException rating_from_string("AA")
            @test_throws ErrorException rating_from_string("A+++++")
            @test_throws ErrorException rating_from_string("invalid")
        end
    end

    #=========================================================================
    # Probability of Default Tests
    =========================================================================#

    @testset "RatingPD Type" begin
        @testset "Valid construction" begin
            pd = RatingPD(
                rating = A,
                annual_pd = 0.0002,
                pd_5yr = 0.008,
                pd_10yr = 0.022,
                pd_15yr = 0.040
            )
            @test pd.rating == A
            @test pd.annual_pd == 0.0002
        end

        @testset "PD bounds validation" begin
            @test_throws ErrorException RatingPD(
                rating = A, annual_pd = -0.01,
                pd_5yr = 0.01, pd_10yr = 0.02, pd_15yr = 0.03
            )
            @test_throws ErrorException RatingPD(
                rating = A, annual_pd = 1.5,
                pd_5yr = 0.01, pd_10yr = 0.02, pd_15yr = 0.03
            )
        end
    end

    @testset "AM_BEST_IMPAIRMENT_RATES" begin
        @testset "All ratings have data" begin
            for rating in instances(AMBestRating)
                @test haskey(AM_BEST_IMPAIRMENT_RATES, rating)
            end
        end

        @testset "PD ordering" begin
            # Higher ratings should have lower PD
            @test get_annual_pd(A_PLUS_PLUS) < get_annual_pd(A)
            @test get_annual_pd(A) < get_annual_pd(B)
            @test get_annual_pd(B) < get_annual_pd(C)
            @test get_annual_pd(C) < get_annual_pd(D)
        end

        @testset "F rating has 100% PD" begin
            @test get_annual_pd(F) == 1.0
        end
    end

    @testset "get_annual_pd" begin
        @testset "Key ratings" begin
            @test get_annual_pd(A_PLUS_PLUS) == 0.0001
            @test get_annual_pd(A) == 0.0002
            @test get_annual_pd(B_MINUS) == 0.0135
        end
    end

    @testset "get_cumulative_pd" begin
        @testset "Exact years" begin
            @test get_cumulative_pd(A, 1) == get_annual_pd(A)
            @test get_cumulative_pd(A, 5) == AM_BEST_IMPAIRMENT_RATES[A].pd_5yr
            @test get_cumulative_pd(A, 10) == AM_BEST_IMPAIRMENT_RATES[A].pd_10yr
        end

        @testset "Interpolation" begin
            # 3 years should be between 1 and 5
            pd_3yr = get_cumulative_pd(A, 3)
            @test get_annual_pd(A) < pd_3yr < AM_BEST_IMPAIRMENT_RATES[A].pd_5yr

            # 7 years should be between 5 and 10
            pd_7yr = get_cumulative_pd(A, 7)
            @test AM_BEST_IMPAIRMENT_RATES[A].pd_5yr < pd_7yr < AM_BEST_IMPAIRMENT_RATES[A].pd_10yr
        end

        @testset "Extrapolation" begin
            # 20 years should be > 15 years
            pd_20yr = get_cumulative_pd(A, 20)
            @test pd_20yr > AM_BEST_IMPAIRMENT_RATES[A].pd_15yr
            @test pd_20yr <= 1.0  # Capped at 100%
        end

        @testset "Invalid years" begin
            @test_throws ErrorException get_cumulative_pd(A, 0)
            @test_throws ErrorException get_cumulative_pd(A, -1)
        end
    end

    @testset "get_hazard_rate" begin
        @testset "Calculation" begin
            # h = -ln(1 - PD)
            hr = get_hazard_rate(A)
            pd = get_annual_pd(A)
            @test hr ≈ -log(1 - pd)
        end

        @testset "F rating has infinite hazard" begin
            @test isinf(get_hazard_rate(F))
        end

        @testset "Hazard rate ordering" begin
            @test get_hazard_rate(A_PLUS_PLUS) < get_hazard_rate(A)
            @test get_hazard_rate(A) < get_hazard_rate(B)
        end
    end

    @testset "get_pd_term_structure" begin
        @testset "Length" begin
            ts = get_pd_term_structure(A, max_years = 10)
            @test length(ts) == 10
        end

        @testset "Monotonically increasing" begin
            ts = get_pd_term_structure(A, max_years = 15)
            for i in 2:length(ts)
                @test ts[i] >= ts[i-1]
            end
        end
    end

    @testset "get_survival_probability" begin
        @testset "Calculation" begin
            # Survival = 1 - cumulative PD
            @test get_survival_probability(A, 5) ≈ 1 - get_cumulative_pd(A, 5)
        end

        @testset "F rating has 0% survival" begin
            @test get_survival_probability(F, 1) == 0.0
        end
    end

    #=========================================================================
    # Guaranty Fund Tests
    =========================================================================#

    @testset "CoverageType Enum" begin
        @test length(instances(CoverageType)) == 7
    end

    @testset "GuarantyFundCoverage Type" begin
        @testset "Valid construction" begin
            cov = GuarantyFundCoverage(
                state = "TX",
                life_death_benefit = 300_000.0,
                life_cash_value = 100_000.0,
                annuity_deferred = 250_000.0,
                annuity_payout = 300_000.0,
                annuity_ssa = 250_000.0,
                group_annuity = 5_000_000.0,
                health = 500_000.0
            )
            @test cov.state == "TX"
            @test cov.coverage_percentage == 1.0  # Default
        end

        @testset "Invalid state code" begin
            @test_throws ErrorException GuarantyFundCoverage(
                state = "TEXAS",
                life_death_benefit = 300_000.0,
                life_cash_value = 100_000.0,
                annuity_deferred = 250_000.0,
                annuity_payout = 300_000.0,
                annuity_ssa = 250_000.0,
                group_annuity = 5_000_000.0,
                health = 500_000.0
            )
        end

        @testset "Invalid coverage percentage" begin
            @test_throws ErrorException GuarantyFundCoverage(
                state = "TX",
                life_death_benefit = 300_000.0,
                life_cash_value = 100_000.0,
                annuity_deferred = 250_000.0,
                annuity_payout = 300_000.0,
                annuity_ssa = 250_000.0,
                group_annuity = 5_000_000.0,
                health = 500_000.0,
                coverage_percentage = 1.5  # > 100%
            )
        end
    end

    @testset "get_state_coverage" begin
        @testset "Known states" begin
            ca = get_state_coverage("CA")
            @test ca.state == "CA"
            @test ca.coverage_percentage == 0.80  # California is 80%

            ny = get_state_coverage("NY")
            @test ny.annuity_deferred == 500_000.0  # NY has higher limits
        end

        @testset "Unknown state returns standard" begin
            ak = get_state_coverage("AK")
            @test ak.annuity_deferred == STANDARD_LIMITS.annuity_deferred
            @test ak.coverage_percentage == 1.0
        end

        @testset "Case insensitive" begin
            tx1 = get_state_coverage("TX")
            tx2 = get_state_coverage("tx")
            @test tx1.annuity_deferred == tx2.annuity_deferred
        end
    end

    @testset "calculate_covered_amount" begin
        @testset "Under limit - full coverage" begin
            covered = calculate_covered_amount(100_000.0, "TX", ANNUITY_DEFERRED)
            @test covered == 100_000.0
        end

        @testset "Over limit - capped" begin
            covered = calculate_covered_amount(500_000.0, "TX", ANNUITY_DEFERRED)
            @test covered == 250_000.0  # TX limit is 250k
        end

        @testset "California 80% coverage" begin
            covered = calculate_covered_amount(250_000.0, "CA", ANNUITY_DEFERRED)
            @test covered == 200_000.0  # 80% of 250k
        end

        @testset "Zero benefit" begin
            @test calculate_covered_amount(0.0, "TX", ANNUITY_DEFERRED) == 0.0
            @test calculate_covered_amount(-100.0, "TX", ANNUITY_DEFERRED) == 0.0
        end
    end

    @testset "calculate_uncovered_amount" begin
        @testset "Fully covered" begin
            uncovered = calculate_uncovered_amount(100_000.0, "TX", ANNUITY_DEFERRED)
            @test uncovered == 0.0
        end

        @testset "Partially covered" begin
            uncovered = calculate_uncovered_amount(500_000.0, "TX", ANNUITY_DEFERRED)
            @test uncovered == 250_000.0  # 500k - 250k
        end

        @testset "California 80% rule" begin
            # 300k benefit, 250k limit, 80% coverage = 200k covered
            # Uncovered = 300k - 200k = 100k
            uncovered = calculate_uncovered_amount(300_000.0, "CA", ANNUITY_DEFERRED)
            @test uncovered == 100_000.0
        end
    end

    @testset "get_coverage_ratio" begin
        @testset "Full coverage" begin
            ratio = get_coverage_ratio(100_000.0, "TX", ANNUITY_DEFERRED)
            @test ratio == 1.0
        end

        @testset "Partial coverage" begin
            ratio = get_coverage_ratio(500_000.0, "TX", ANNUITY_DEFERRED)
            @test ratio == 0.5  # 250k / 500k
        end

        @testset "Zero benefit" begin
            @test get_coverage_ratio(0.0, "TX", ANNUITY_DEFERRED) == 0.0
        end
    end

    #=========================================================================
    # CVA Tests
    =========================================================================#

    @testset "CVAResult Type" begin
        @testset "Valid construction" begin
            result = CVAResult(
                cva_gross = 1000.0,
                cva_net = 500.0,
                guaranty_adjustment = 500.0,
                expected_exposure = 100_000.0,
                covered_exposure = 50_000.0,
                uncovered_exposure = 50_000.0,
                coverage_ratio = 0.5,
                lgd = 0.70,
                rating = A,
                annual_pd = 0.0002
            )
            @test result.cva_gross == 1000.0
            @test result.cva_net == 500.0
        end

        @testset "Negative CVA not allowed" begin
            @test_throws ErrorException CVAResult(
                cva_gross = -100.0,
                cva_net = 0.0,
                guaranty_adjustment = 0.0,
                expected_exposure = 100_000.0,
                covered_exposure = 0.0,
                uncovered_exposure = 100_000.0,
                coverage_ratio = 0.0,
                lgd = 0.70,
                rating = A,
                annual_pd = 0.0002
            )
        end

        @testset "Invalid LGD" begin
            @test_throws ErrorException CVAResult(
                cva_gross = 1000.0,
                cva_net = 1000.0,
                guaranty_adjustment = 0.0,
                expected_exposure = 100_000.0,
                covered_exposure = 0.0,
                uncovered_exposure = 100_000.0,
                coverage_ratio = 0.0,
                lgd = 1.5,  # > 1
                rating = A,
                annual_pd = 0.0002
            )
        end
    end

    @testset "calculate_exposure_profile" begin
        @testset "Basic profile" begin
            profile = calculate_exposure_profile(100_000.0, 0.05, 5)
            @test length(profile) == 5
            @test all(profile .> 0)
        end

        @testset "Validation" begin
            @test_throws ErrorException calculate_exposure_profile(0.0, 0.05, 5)
            @test_throws ErrorException calculate_exposure_profile(100_000.0, 0.05, 0)
        end
    end

    @testset "calculate_cva" begin
        @testset "Basic CVA" begin
            result = calculate_cva(250_000.0, A, term_years = 5)
            @test result.cva_gross > 0
            @test result.expected_exposure == 250_000.0
            @test result.rating == A
        end

        @testset "CVA with guaranty fund" begin
            result = calculate_cva(
                250_000.0, A,
                term_years = 5,
                state = "TX"
            )
            # With full coverage, net CVA should be 0
            @test result.coverage_ratio == 1.0
            @test result.cva_net == 0.0
            @test result.guaranty_adjustment == result.cva_gross
        end

        @testset "CVA partially covered" begin
            result = calculate_cva(
                500_000.0, A,
                term_years = 5,
                state = "TX"  # 250k limit
            )
            @test result.coverage_ratio == 0.5
            @test result.cva_net ≈ result.cva_gross * 0.5
        end

        @testset "Higher rating has lower CVA" begin
            cva_a = calculate_cva(100_000.0, A, term_years = 5)
            cva_b = calculate_cva(100_000.0, B, term_years = 5)
            @test cva_a.cva_gross < cva_b.cva_gross
        end

        @testset "Longer term has higher CVA" begin
            cva_5 = calculate_cva(100_000.0, A, term_years = 5)
            cva_10 = calculate_cva(100_000.0, A, term_years = 10)
            @test cva_5.cva_gross < cva_10.cva_gross
        end

        @testset "Validation" begin
            @test_throws ErrorException calculate_cva(0.0, A)
            @test_throws ErrorException calculate_cva(100_000.0, A, term_years = 0)
            @test_throws ErrorException calculate_cva(100_000.0, A, lgd = 0.0)
        end
    end

    @testset "calculate_cva_term_structure" begin
        @testset "Basic calculation" begin
            profile = calculate_exposure_profile(100_000.0, 0.05, 5)
            cva = calculate_cva_term_structure(profile, A)
            @test cva > 0
        end

        @testset "Empty profile throws" begin
            @test_throws ErrorException calculate_cva_term_structure(Float64[], A)
        end
    end

    @testset "calculate_credit_adjusted_price" begin
        @testset "Price reduction" begin
            base_price = 100_000.0
            adj_price = calculate_credit_adjusted_price(base_price, A, term_years = 5)
            @test adj_price < base_price
        end

        @testset "With full guaranty coverage" begin
            base_price = 100_000.0
            adj_price = calculate_credit_adjusted_price(
                base_price, A,
                term_years = 5,
                state = "TX"  # Full coverage
            )
            @test adj_price == base_price  # No adjustment when fully covered
        end
    end

    @testset "calculate_credit_spread" begin
        @testset "Calculation" begin
            spread = calculate_credit_spread(A)
            @test spread > 0
            @test spread < 0.01  # Should be small for A rating
        end

        @testset "Higher rating has lower spread" begin
            spread_a = calculate_credit_spread(A)
            spread_b = calculate_credit_spread(B)
            @test spread_a < spread_b
        end

        @testset "F rating has high spread" begin
            spread_f = calculate_credit_spread(F)
            # F rating has infinite hazard rate (in liquidation), returns 1.0
            @test spread_f == 1.0
        end
    end

    #=========================================================================
    # Sensitivity Analysis Tests
    =========================================================================#

    @testset "cva_sensitivity_to_rating" begin
        ratings = [A, B, C]
        results = cva_sensitivity_to_rating(100_000.0, ratings, term_years = 5)

        @test length(results) == 3
        @test haskey(results, A)
        @test haskey(results, B)
        @test haskey(results, C)

        # CVA should increase with lower ratings
        @test results[A].cva_gross < results[B].cva_gross < results[C].cva_gross
    end

    @testset "cva_sensitivity_to_term" begin
        terms = [1, 5, 10]
        results = cva_sensitivity_to_term(100_000.0, A, terms)

        @test length(results) == 3
        @test haskey(results, 1)
        @test haskey(results, 5)
        @test haskey(results, 10)

        # CVA should increase with longer terms
        @test results[1].cva_gross < results[5].cva_gross < results[10].cva_gross
    end

    #=========================================================================
    # Integration Tests
    =========================================================================#

    @testset "Integration" begin
        @testset "Full workflow" begin
            # Parse rating
            rating = rating_from_string("A")
            @test is_secure(rating)

            # Check PD
            pd = get_annual_pd(rating)
            @test pd > 0 && pd < 0.01

            # Get guaranty coverage
            benefit = 300_000.0
            covered = calculate_covered_amount(benefit, "TX", ANNUITY_DEFERRED)
            @test covered == 250_000.0  # Limited to 250k

            # Calculate CVA
            result = calculate_cva(benefit, rating, term_years = 5, state = "TX")
            @test result.coverage_ratio ≈ 250_000 / 300_000
            @test result.cva_net > 0  # Some exposure not covered

            # Credit-adjusted price
            adj_price = calculate_credit_adjusted_price(
                benefit, rating,
                term_years = 5,
                state = "TX"
            )
            @test adj_price < benefit
            @test adj_price == benefit - result.cva_net
        end
    end

    #=========================================================================
    # Anti-Pattern Tests
    =========================================================================#

    @testset "Anti-Patterns" begin
        @testset "No silent failures" begin
            # All these should throw, not return silently
            @test_throws ErrorException rating_from_string("INVALID")
            @test_throws ErrorException get_cumulative_pd(A, 0)
            @test_throws ErrorException calculate_cva(0.0, A)
            @test_throws ErrorException calculate_cva(100_000.0, A, lgd = 0.0)
            @test_throws ErrorException calculate_exposure_profile(0.0, 0.05, 5)
        end

        @testset "Type validation" begin
            # RatingPD bounds
            @test_throws ErrorException RatingPD(
                rating = A, annual_pd = -0.01,
                pd_5yr = 0.01, pd_10yr = 0.02, pd_15yr = 0.03
            )

            # CVAResult bounds
            @test_throws ErrorException CVAResult(
                cva_gross = -1.0, cva_net = 0.0, guaranty_adjustment = 0.0,
                expected_exposure = 100_000.0, covered_exposure = 0.0,
                uncovered_exposure = 100_000.0, coverage_ratio = 0.0,
                lgd = 0.7, rating = A, annual_pd = 0.0002
            )
        end
    end

    #=========================================================================
    # Display Function Tests
    =========================================================================#

    @testset "Display Functions" begin
        @testset "pd_summary" begin
            summary = pd_summary(A)
            @test occursin("A", summary)
            @test occursin("Secure", summary)
            @test occursin("%", summary)
        end

        @testset "print_pd_table" begin
            io = IOBuffer()
            print_pd_table(io = io)
            output = String(take!(io))
            @test occursin("AM Best", output)
            @test occursin("A++", output)
        end

        @testset "print_state_coverage" begin
            io = IOBuffer()
            print_state_coverage("TX", io = io)
            output = String(take!(io))
            @test occursin("TX", output)
            @test occursin("Annuity", output)
        end

        @testset "print_cva_result" begin
            result = calculate_cva(100_000.0, A, term_years = 5)
            io = IOBuffer()
            print_cva_result(result, io = io)
            output = String(take!(io))
            @test occursin("CVA", output)
            @test occursin("Exposure", output)
        end
    end

end  # Main testset
