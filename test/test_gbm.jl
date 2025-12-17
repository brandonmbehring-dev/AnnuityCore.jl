"""
Tests for GBM path generation.
"""

using Test
using AnnuityCore
using Statistics

@testset "GBMParams" begin
    @testset "construction" begin
        params = GBMParams(100.0, 0.05, 0.02, 0.20, 1.0)
        @test params.spot == 100.0
        @test params.rate == 0.05
        @test params.dividend == 0.02
        @test params.volatility == 0.20
        @test params.time_to_expiry == 1.0
    end

    @testset "validation" begin
        # Spot must be positive
        @test_throws ArgumentError GBMParams(0.0, 0.05, 0.02, 0.20, 1.0)
        @test_throws ArgumentError GBMParams(-100.0, 0.05, 0.02, 0.20, 1.0)

        # Volatility must be non-negative
        @test_throws ArgumentError GBMParams(100.0, 0.05, 0.02, -0.20, 1.0)

        # Time to expiry must be positive
        @test_throws ArgumentError GBMParams(100.0, 0.05, 0.02, 0.20, 0.0)
        @test_throws ArgumentError GBMParams(100.0, 0.05, 0.02, 0.20, -1.0)

        # Zero volatility is allowed
        params = GBMParams(100.0, 0.05, 0.02, 0.0, 1.0)
        @test params.volatility == 0.0
    end

    @testset "drift and forward" begin
        params = GBMParams(100.0, 0.05, 0.02, 0.20, 1.0)

        # Drift = r - q - σ²/2 = 0.05 - 0.02 - 0.04/2 = 0.01
        @test drift(params) ≈ 0.01

        # Forward = S × exp((r-q)×T) = 100 × exp(0.03) ≈ 103.045
        @test forward(params) ≈ 100.0 * exp(0.03)
    end

    @testset "type promotion" begin
        # Mixed types should promote correctly
        params = GBMParams(100, 0.05f0, 0.02, 0.20, 1)
        @test params.spot isa Float64
        @test params.rate isa Float64
    end
end


@testset "generate_terminal_values" begin
    params = GBMParams(100.0, 0.05, 0.02, 0.20, 1.0)

    @testset "basic generation" begin
        terminal = generate_terminal_values(params, 10000; seed=42)
        @test length(terminal) == 10000
        @test all(terminal .> 0)  # GBM always positive
    end

    @testset "reproducibility" begin
        t1 = generate_terminal_values(params, 1000; seed=42)
        t2 = generate_terminal_values(params, 1000; seed=42)
        @test t1 == t2  # Same seed should give same results
    end

    @testset "antithetic variates" begin
        # Antithetic requires even number
        @test_throws ArgumentError generate_terminal_values(params, 1001; antithetic=true)

        # Should work with even number
        terminal = generate_terminal_values(params, 10000; seed=42, antithetic=true)
        @test length(terminal) == 10000
    end

    @testset "mean convergence to forward" begin
        # [T1] E[S(T)] = S(0) × exp((r-q)×T)
        terminal = generate_terminal_values(params, 100000; seed=42, antithetic=true)
        expected_mean = forward(params)

        # Mean should be within 1% of forward price
        @test abs(mean(terminal) - expected_mean) / expected_mean < 0.01
    end

    @testset "log-variance matches theory" begin
        # [T1] Var[log(S(T)/S(0))] = σ²T
        terminal = generate_terminal_values(params, 100000; seed=42, antithetic=true)
        log_returns = log.(terminal ./ params.spot)
        expected_var = params.volatility^2 * params.time_to_expiry

        # Variance should be within 5% of theoretical
        @test abs(var(log_returns) - expected_var) / expected_var < 0.05
    end
end


@testset "generate_gbm_paths" begin
    params = GBMParams(100.0, 0.05, 0.02, 0.20, 1.0)

    @testset "basic generation" begin
        result = generate_gbm_paths(params, 100, 252; seed=42)

        @test n_paths(result) == 100
        @test n_steps(result) == 252
        @test size(result.paths) == (100, 253)  # n_paths × (n_steps + 1)
        @test length(result.times) == 253
    end

    @testset "initial values" begin
        result = generate_gbm_paths(params, 100, 252; seed=42)

        # All paths should start at spot
        @test all(result.paths[:, 1] .== params.spot)

        # First time should be 0
        @test result.times[1] == 0.0
        @test result.times[end] ≈ params.time_to_expiry
    end

    @testset "terminal values accessor" begin
        result = generate_gbm_paths(params, 100, 252; seed=42)

        @test terminal_values(result) == result.paths[:, end]
    end

    @testset "total returns accessor" begin
        result = generate_gbm_paths(params, 100, 252; seed=42)
        returns = total_returns(result)

        @test length(returns) == 100
        expected = (result.paths[:, end] .- result.paths[:, 1]) ./ result.paths[:, 1]
        @test returns ≈ expected
    end

    @testset "validation errors" begin
        @test_throws ArgumentError generate_gbm_paths(params, 0, 252)
        @test_throws ArgumentError generate_gbm_paths(params, 100, 0)
        @test_throws ArgumentError generate_gbm_paths(params, 101, 252; antithetic=true)
    end
end


@testset "generate_paths_with_monthly_observations" begin
    params = GBMParams(100.0, 0.05, 0.02, 0.20, 1.0)

    @testset "monthly observation points" begin
        result = generate_paths_with_monthly_observations(params, 100; n_months=12, seed=42)

        # Should have 13 observation points (t=0 + 12 months)
        @test size(result.paths, 2) == 13
        @test length(result.times) == 13

        # All paths should start at spot
        @test all(result.paths[:, 1] .== params.spot)
    end
end


@testset "validate_gbm_simulation" begin
    params = GBMParams(100.0, 0.05, 0.02, 0.20, 1.0)

    @testset "validation results" begin
        result = validate_gbm_simulation(params; n_paths=100000, seed=42)

        @test result.validation_passed == true
        @test result.mean_error_pct < 1.0  # Less than 1% error
        @test result.variance_error_pct < 5.0  # Less than 5% error on variance
    end
end
