"""
Tests for Automatic Differentiation Greeks via Zygote.jl.

Validates that AD Greeks match analytical Black-Scholes Greeks.
"""

@testset "AD Greeks" begin

    @testset "AD vs Analytical - Call Options" begin
        # Hull Example 15.6 parameters
        S, K, r, q, σ, τ = 42.0, 40.0, 0.10, 0.0, 0.20, 0.5

        ad = ad_greeks_call(S, K, r, q, σ, τ)
        bs = black_scholes_greeks(S, K, r, q, σ, τ; is_call=true)

        @test ad.delta ≈ bs.delta atol=1e-10
        @test ad.gamma ≈ bs.gamma atol=1e-10
        @test ad.vega ≈ bs.vega atol=1e-10
        @test ad.theta ≈ bs.theta atol=1e-8  # Theta convention may differ slightly
        @test ad.rho ≈ bs.rho atol=1e-10
    end

    @testset "AD vs Analytical - Put Options" begin
        S, K, r, q, σ, τ = 42.0, 40.0, 0.10, 0.0, 0.20, 0.5

        ad = ad_greeks_put(S, K, r, q, σ, τ)
        bs = black_scholes_greeks(S, K, r, q, σ, τ; is_call=false)

        @test ad.delta ≈ bs.delta atol=1e-10
        @test ad.gamma ≈ bs.gamma atol=1e-10
        @test ad.vega ≈ bs.vega atol=1e-10
        @test ad.theta ≈ bs.theta atol=1e-8
        @test ad.rho ≈ bs.rho atol=1e-10
    end

    @testset "AD Greeks - ATM Options" begin
        # At-the-money options
        S, K, r, q, σ, τ = 100.0, 100.0, 0.05, 0.02, 0.20, 1.0

        ad = ad_greeks_call(S, K, r, q, σ, τ)
        bs = black_scholes_greeks(S, K, r, q, σ, τ; is_call=true)

        @test ad.delta ≈ bs.delta atol=1e-10
        @test ad.gamma ≈ bs.gamma atol=1e-10
        @test ad.vega ≈ bs.vega atol=1e-10
    end

    @testset "AD Greeks - Deep ITM/OTM" begin
        # Deep in-the-money call
        S, K, r, q, σ, τ = 150.0, 100.0, 0.05, 0.02, 0.20, 1.0

        ad_itm = ad_greeks_call(S, K, r, q, σ, τ)
        bs_itm = black_scholes_greeks(S, K, r, q, σ, τ; is_call=true)

        @test ad_itm.delta ≈ bs_itm.delta atol=1e-10
        @test ad_itm.delta > 0.9  # Deep ITM call delta ~ 1

        # Deep out-of-the-money call
        S, K = 50.0, 100.0
        ad_otm = ad_greeks_call(S, K, r, q, σ, τ)
        bs_otm = black_scholes_greeks(S, K, r, q, σ, τ; is_call=true)

        @test ad_otm.delta ≈ bs_otm.delta atol=1e-10
        @test ad_otm.delta < 0.1  # Deep OTM call delta ~ 0
    end

    @testset "AD Greeks - With Dividends" begin
        S, K, r, q, σ, τ = 100.0, 100.0, 0.05, 0.03, 0.25, 0.5

        ad = ad_greeks_call(S, K, r, q, σ, τ)
        bs = black_scholes_greeks(S, K, r, q, σ, τ; is_call=true)

        @test ad.delta ≈ bs.delta atol=1e-10
        @test ad.gamma ≈ bs.gamma atol=1e-10
        @test ad.vega ≈ bs.vega atol=1e-10
    end

    @testset "Portfolio Greeks" begin
        # Long 2 calls, short 1 put (typical delta-hedged position)
        positions = [(:call, 2.0), (:put, -1.0)]
        S, K, r, q, σ, τ = 100.0, 100.0, 0.05, 0.02, 0.20, 1.0

        port = portfolio_greeks(positions; S=S, K=K, r=r, q=q, σ=σ, τ=τ)

        # Manually compute expected portfolio Greeks
        call_greeks = ad_greeks_call(S, K, r, q, σ, τ)
        put_greeks = ad_greeks_put(S, K, r, q, σ, τ)

        expected_delta = 2.0 * call_greeks.delta - 1.0 * put_greeks.delta
        expected_gamma = 2.0 * call_greeks.gamma - 1.0 * put_greeks.gamma
        expected_vega = 2.0 * call_greeks.vega - 1.0 * put_greeks.vega

        @test port.delta ≈ expected_delta atol=1e-10
        @test port.gamma ≈ expected_gamma atol=1e-10
        @test port.vega ≈ expected_vega atol=1e-10
    end

    @testset "Validate AD vs Analytical Function" begin
        # Use built-in validation
        @test validate_ad_vs_analytical(100.0, 100.0, 0.05, 0.02, 0.20, 1.0)
        @test validate_ad_vs_analytical(42.0, 40.0, 0.10, 0.0, 0.20, 0.5)
        @test validate_ad_vs_analytical(150.0, 100.0, 0.05, 0.02, 0.20, 1.0)
    end

    @testset "ADGreeks Type" begin
        ad = ad_greeks_call(100.0, 100.0, 0.05, 0.02, 0.20, 1.0)

        @test ad isa ADGreeks
        @test ad isa ADGreeks{Float64}
        @test typeof(ad.delta) == Float64
    end

    @testset "Mixed Numeric Types" begin
        # Should promote types correctly
        ad = ad_greeks_call(100, 100.0, 0.05, 0.02, 0.20, 1.0)
        @test ad isa ADGreeks{Float64}

        ad2 = ad_greeks_put(100, 100, 0.05, 0.02, 0.20, 1)
        @test ad2 isa ADGreeks{Float64}
    end

    @testset "Greek Sensitivities Sanity" begin
        S, K, r, q, σ, τ = 100.0, 100.0, 0.05, 0.02, 0.20, 1.0

        call = ad_greeks_call(S, K, r, q, σ, τ)
        put = ad_greeks_put(S, K, r, q, σ, τ)

        # Call delta is positive, put delta is negative
        @test call.delta > 0
        @test put.delta < 0

        # Both have positive gamma
        @test call.gamma > 0
        @test put.gamma > 0

        # Both have positive vega
        @test call.vega > 0
        @test put.vega > 0

        # Gamma is same for call and put (at same strike)
        @test call.gamma ≈ put.gamma atol=1e-10

        # Vega is same for call and put
        @test call.vega ≈ put.vega atol=1e-10

        # Call theta is typically negative (time decay)
        @test call.theta < 0

        # Call rho is positive (benefits from higher rates)
        @test call.rho > 0

        # Put rho is negative
        @test put.rho < 0
    end

end
