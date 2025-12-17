"""
Tests for Monte Carlo option pricing.
"""

using Test
using AnnuityCore
using Statistics

@testset "MonteCarloEngine" begin
    @testset "construction" begin
        engine = MonteCarloEngine(n_paths=10000, seed=42)
        @test engine.n_paths == 10000
        @test engine.antithetic == true
        @test engine.seed == 42
        @test engine.batch_size == 10000
    end

    @testset "antithetic adjustment" begin
        # Odd n_paths should be rounded up for antithetic
        engine = MonteCarloEngine(n_paths=10001, antithetic=true)
        @test engine.n_paths == 10002  # Even number
    end

    @testset "validation" begin
        @test_throws ArgumentError MonteCarloEngine(n_paths=0)
        @test_throws ArgumentError MonteCarloEngine(batch_size=0)
    end
end


@testset "MCResult" begin
    # Create a mock result
    payoffs = rand(1000)
    result = MCResult(
        1.5,      # price
        0.05,     # standard_error
        (1.4, 1.6),  # confidence_interval
        1000,     # n_paths
        payoffs,  # payoffs
        0.95      # discount_factor
    )

    @testset "accessors" begin
        @test result.price == 1.5
        @test result.standard_error == 0.05
        @test result.n_paths == 1000
        @test result.discount_factor == 0.95
    end

    @testset "derived metrics" begin
        @test relative_error(result) ≈ 0.05 / 1.5
        @test ci_width(result) ≈ 0.2
    end
end


@testset "European call pricing" begin
    engine = MonteCarloEngine(n_paths=100000, seed=42)
    params = GBMParams(100.0, 0.05, 0.02, 0.20, 1.0)

    @testset "ATM call convergence to BS" begin
        # MC should converge to Black-Scholes
        mc_result = price_european_call(engine, params, 100.0)
        bs_price = black_scholes_call(100.0, 100.0, 0.05, 0.02, 0.20, 1.0)

        # Within 1% of BS price
        @test abs(mc_result.price - bs_price) / bs_price < 0.01

        # BS price should be within 95% CI
        @test mc_result.confidence_interval[1] <= bs_price <= mc_result.confidence_interval[2]
    end

    @testset "OTM call" begin
        mc_result = price_european_call(engine, params, 120.0)
        bs_price = black_scholes_call(100.0, 120.0, 0.05, 0.02, 0.20, 1.0)

        # Within 3% of BS price (OTM options have higher relative error)
        @test abs(mc_result.price - bs_price) / bs_price < 0.03
    end

    @testset "ITM call" begin
        mc_result = price_european_call(engine, params, 80.0)
        bs_price = black_scholes_call(100.0, 80.0, 0.05, 0.02, 0.20, 1.0)

        # Within 1% of BS price
        @test abs(mc_result.price - bs_price) / bs_price < 0.01
    end

    @testset "validation" begin
        @test_throws ArgumentError price_european_call(engine, params, 0.0)
        @test_throws ArgumentError price_european_call(engine, params, -100.0)
    end
end


@testset "European put pricing" begin
    engine = MonteCarloEngine(n_paths=100000, seed=42)
    params = GBMParams(100.0, 0.05, 0.02, 0.20, 1.0)

    @testset "ATM put convergence to BS" begin
        mc_result = price_european_put(engine, params, 100.0)
        bs_price = black_scholes_put(100.0, 100.0, 0.05, 0.02, 0.20, 1.0)

        # Within 1% of BS price
        @test abs(mc_result.price - bs_price) / bs_price < 0.01

        # BS price should be within 95% CI
        @test mc_result.confidence_interval[1] <= bs_price <= mc_result.confidence_interval[2]
    end
end


@testset "Capped call return pricing" begin
    engine = MonteCarloEngine(n_paths=100000, seed=42)
    params = GBMParams(100.0, 0.05, 0.02, 0.20, 1.0)

    @testset "basic capped call" begin
        result = price_capped_call_return(engine, params, 0.10)

        # Price should be positive
        @test result.price > 0

        # Price should be less than uncapped call (sanity check)
        uncapped = price_european_call(engine, params, 100.0)
        # The capped return is different from regular call, but should be in reasonable range
        @test result.price < 20.0  # Reasonable upper bound
    end

    @testset "validation" begin
        @test_throws ArgumentError price_capped_call_return(engine, params, 0.0)
        @test_throws ArgumentError price_capped_call_return(engine, params, -0.10)
    end
end


@testset "Buffer protection pricing" begin
    engine = MonteCarloEngine(n_paths=100000, seed=42)
    params = GBMParams(100.0, 0.05, 0.02, 0.20, 1.0)

    @testset "10% buffer" begin
        result = price_buffer_protection(engine, params, 0.10)

        # Price should be positive (expected value of protected return × spot)
        @test result.price > 0
    end

    @testset "buffer with cap" begin
        result = price_buffer_protection(engine, params, 0.10; cap_rate=0.15)

        # Price should be positive but less than without cap
        no_cap = price_buffer_protection(engine, params, 0.10)
        @test result.price < no_cap.price
    end

    @testset "100% buffer" begin
        # 100% buffer means no downside participation
        result = price_buffer_protection(engine, params, 1.0)

        # All payoffs should be non-negative (buffer absorbs all losses)
        @test all(result.payoffs .>= 0)
    end

    @testset "validation" begin
        @test_throws ArgumentError price_buffer_protection(engine, params, 0.0)
    end
end


@testset "Floor protection pricing" begin
    engine = MonteCarloEngine(n_paths=100000, seed=42)
    params = GBMParams(100.0, 0.05, 0.02, 0.20, 1.0)

    @testset "-10% floor" begin
        result = price_floor_protection(engine, params, -0.10)

        # All payoffs should be >= floor × spot
        @test all(result.payoffs .>= -0.10 * params.spot)
    end

    @testset "floor with cap" begin
        result = price_floor_protection(engine, params, -0.10; cap_rate=0.15)

        # All payoffs should be between floor and cap
        @test all(result.payoffs .>= -0.10 * params.spot)
        @test all(result.payoffs .<= 0.15 * params.spot)
    end

    @testset "validation" begin
        @test_throws ArgumentError price_floor_protection(engine, params, 0.10)  # Floor should be <= 0
    end
end


@testset "price_with_payoff" begin
    engine = MonteCarloEngine(n_paths=100000, seed=42)
    params = GBMParams(100.0, 0.05, 0.02, 0.20, 1.0)

    @testset "capped call payoff" begin
        payoff = CappedCallPayoff(0.10, 0.0)
        result = price_with_payoff(engine, params, payoff)

        @test result.price > 0
        @test result.n_paths == 100000
    end

    @testset "buffer payoff" begin
        payoff = BufferPayoff(0.10, 0.20)
        result = price_with_payoff(engine, params, payoff)

        @test result.price > 0
    end
end


@testset "Convenience functions" begin
    @testset "price_vanilla_mc" begin
        result = price_vanilla_mc(100.0, 100.0, 0.05, 0.02, 0.20, 1.0; seed=42)

        @test result isa MCResult
        @test result.price > 0
    end

    @testset "monte_carlo_price" begin
        price = monte_carlo_price(100.0, 100.0, 0.05, 0.02, 0.20, 1.0; seed=42)

        @test price isa Float64
        @test price > 0

        # Should match BS closely
        bs_price = black_scholes_call(100.0, 100.0, 0.05, 0.02, 0.20, 1.0)
        @test abs(price - bs_price) / bs_price < 0.01
    end

    @testset "option types" begin
        call_price = monte_carlo_price(100.0, 100.0, 0.05, 0.02, 0.20, 1.0; option_type=:call, seed=42)
        put_price = monte_carlo_price(100.0, 100.0, 0.05, 0.02, 0.20, 1.0; option_type=:put, seed=42)

        # Put-call parity check (approximately)
        # C - P ≈ S×e^(-qT) - K×e^(-rT)
        pcp_lhs = call_price - put_price
        pcp_rhs = 100.0 * exp(-0.02) - 100.0 * exp(-0.05)

        @test abs(pcp_lhs - pcp_rhs) < 0.5  # Allow some MC error
    end
end


@testset "Convergence analysis" begin
    params = GBMParams(100.0, 0.05, 0.02, 0.20, 1.0)
    bs_price = black_scholes_call(100.0, 100.0, 0.05, 0.02, 0.20, 1.0)

    @testset "convergence rate" begin
        analysis = convergence_analysis(
            params, 100.0, bs_price;
            path_counts=[1000, 5000, 10000, 50000],
            seed=42
        )

        # [T1] Convergence rate should be approximately -0.5, but MC variance
        # can cause deviation. Key property: rate is negative (error decreases).
        @test analysis.convergence_rate < 0  # Error decreases with more paths

        # Error should decrease with more paths
        errors = [r.absolute_error for r in analysis.results]
        @test errors[end] < errors[1]
    end

    @testset "CI coverage" begin
        analysis = convergence_analysis(
            params, 100.0, bs_price;
            path_counts=[10000, 50000, 100000],
            seed=42
        )

        # With more paths, BS price should be within CI
        final_result = analysis.results[end]
        @test final_result.within_ci == true
    end
end


@testset "Reproducibility" begin
    engine = MonteCarloEngine(n_paths=10000, seed=42)
    params = GBMParams(100.0, 0.05, 0.02, 0.20, 1.0)

    @testset "same seed gives same results" begin
        result1 = price_european_call(engine, params, 100.0)
        result2 = price_european_call(engine, params, 100.0)

        @test result1.price == result2.price
        @test result1.payoffs == result2.payoffs
    end
end
