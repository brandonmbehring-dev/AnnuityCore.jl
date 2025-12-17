# Hull Example 15.6 reference values (module-level constants)
# S=42, K=40, r=0.10, q=0, σ=0.20, T=0.5
# Call = 4.7594, Put = 0.8086 (to 4 decimal places)
const HULL_S = 42.0
const HULL_K = 40.0
const HULL_r = 0.10
const HULL_q = 0.0
const HULL_σ = 0.20
const HULL_τ = 0.5
const HULL_CALL = 4.7594
const HULL_PUT = 0.8086

@testset "Black-Scholes" begin

    @testset "Hull Example 15.6 - Call" begin
        call_price = black_scholes_call(HULL_S, HULL_K, HULL_r, HULL_q, HULL_σ, HULL_τ)

        # [T1] Validate against Hull textbook (1e-4 tolerance for 4 decimal places)
        @test call_price ≈ HULL_CALL atol=1e-4

        # More stringent internal consistency check
        @test call_price ≈ 4.759422392871532 atol=1e-10
    end

    @testset "Hull Example 15.6 - Put" begin
        put_price = black_scholes_put(HULL_S, HULL_K, HULL_r, HULL_q, HULL_σ, HULL_τ)

        # [T1] Validate against Hull textbook
        @test put_price ≈ HULL_PUT atol=1e-4

        # More stringent internal consistency
        @test put_price ≈ 0.8085993729000958 atol=1e-10
    end

    @testset "Put-Call Parity" begin
        call = black_scholes_call(HULL_S, HULL_K, HULL_r, HULL_q, HULL_σ, HULL_τ)
        put = black_scholes_put(HULL_S, HULL_K, HULL_r, HULL_q, HULL_σ, HULL_τ)

        # C - P = S·e^(-qτ) - K·e^(-rτ)
        lhs = call - put
        rhs = HULL_S * exp(-HULL_q * HULL_τ) - HULL_K * exp(-HULL_r * HULL_τ)

        @test lhs ≈ rhs atol=1e-10

        # Validation gate should pass
        @test validate_put_call_parity(call, put, HULL_S, HULL_K, HULL_r, HULL_q, HULL_τ) == PASS
    end

    @testset "No-Arbitrage Bounds" begin
        call = black_scholes_call(HULL_S, HULL_K, HULL_r, HULL_q, HULL_σ, HULL_τ)

        # [T1] Call cannot exceed underlying price
        @test call < HULL_S
        @test validate_no_arbitrage(call, HULL_S) == PASS

        # Put cannot exceed strike (ignoring discounting)
        put = black_scholes_put(HULL_S, HULL_K, HULL_r, HULL_q, HULL_σ, HULL_τ)
        @test put < HULL_K
    end

    @testset "Greeks" begin
        greeks = black_scholes_greeks(HULL_S, HULL_K, HULL_r, HULL_q, HULL_σ, HULL_τ)

        # Delta: For ITM call, should be high (close to 1)
        @test 0.5 < greeks.delta < 1.0
        @test greeks.delta ≈ 0.7791312909426691 atol=1e-10

        # Gamma: Always positive
        @test greeks.gamma > 0
        @test greeks.gamma ≈ 0.04996267040591185 atol=1e-10

        # Vega: Always positive
        @test greeks.vega > 0

        # Put delta should be negative
        put_greeks = black_scholes_greeks(HULL_S, HULL_K, HULL_r, HULL_q, HULL_σ, HULL_τ; is_call=false)
        @test put_greeks.delta < 0

        # Gamma should be same for call and put
        @test greeks.gamma ≈ put_greeks.gamma atol=1e-10

        # Vega should be same for call and put
        @test greeks.vega ≈ put_greeks.vega atol=1e-10
    end

    @testset "Edge Cases" begin
        # At expiry (τ = 0)
        @test black_scholes_call(HULL_S, HULL_K, HULL_r, HULL_q, HULL_σ, 0.0) == max(HULL_S - HULL_K, 0)
        @test black_scholes_put(HULL_S, HULL_K, HULL_r, HULL_q, HULL_σ, 0.0) == max(HULL_K - HULL_S, 0)

        # Zero volatility
        call_zero_vol = black_scholes_call(HULL_S, HULL_K, HULL_r, HULL_q, 0.0, HULL_τ)
        # With zero vol, call = max(S·e^((r-q)τ) - K, 0) · e^(-rτ)
        fwd = HULL_S * exp(HULL_r * HULL_τ)
        df = exp(-HULL_r * HULL_τ)
        @test call_zero_vol ≈ df * max(fwd - HULL_K, 0) atol=1e-10

        # Deep ITM call (should be close to intrinsic)
        deep_itm_call = black_scholes_call(100.0, 50.0, 0.05, 0.0, 0.20, 0.1)
        @test deep_itm_call > 49.0  # Close to S - K

        # Deep OTM call (should be close to 0)
        deep_otm_call = black_scholes_call(50.0, 100.0, 0.05, 0.0, 0.20, 0.1)
        @test deep_otm_call < 0.01
    end

    @testset "Mixed Numeric Types" begin
        # Should handle Int, Float32, Float64 combinations
        call_int = black_scholes_call(42, 40, 0.10, 0.0, 0.20, 0.5)
        @test call_int ≈ HULL_CALL atol=1e-4

        call_f32 = black_scholes_call(Float32(42), Float32(40), Float32(0.10),
                                       Float32(0), Float32(0.20), Float32(0.5))
        @test Float64(call_f32) ≈ HULL_CALL atol=1e-3  # Lower precision for Float32
    end

    @testset "Dividend Yield" begin
        # With dividend yield, call should be lower
        call_no_div = black_scholes_call(100.0, 100.0, 0.05, 0.0, 0.20, 1.0)
        call_with_div = black_scholes_call(100.0, 100.0, 0.05, 0.02, 0.20, 1.0)

        @test call_with_div < call_no_div

        # Put should be higher with dividends
        put_no_div = black_scholes_put(100.0, 100.0, 0.05, 0.0, 0.20, 1.0)
        put_with_div = black_scholes_put(100.0, 100.0, 0.05, 0.02, 0.20, 1.0)

        @test put_with_div > put_no_div
    end

end
