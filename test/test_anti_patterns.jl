@testset "Anti-Patterns" begin

    @testset "FIA Floor Enforcement - [T1]" begin
        # All FIA payoffs must enforce 0% floor - no negative credited returns

        @testset "Cap never negative" begin
            payoff = CappedCallPayoff(0.10, 0.0)
            for r in [-0.50, -0.25, -0.10, -0.05, -0.01, -0.001]
                result = calculate(payoff, r)
                @test result.credited_return >= 0.0
                @test result.floor_applied
            end
        end

        @testset "Participation never negative" begin
            for (idx_return, participation) in [(-0.20, 0.80), (-0.10, 1.50), (-0.50, 1.20)]
                payoff = ParticipationPayoff(participation, nothing, 0.0)
                result = calculate(payoff, idx_return)
                @test result.credited_return >= 0.0
            end
        end

        @testset "Spread never negative" begin
            # Even when spread > return
            for (idx_return, spread) in [(0.01, 0.02), (0.02, 0.05), (-0.10, 0.02)]
                payoff = SpreadPayoff(spread, nothing, 0.0)
                result = calculate(payoff, idx_return)
                @test result.credited_return >= 0.0
            end
        end

        @testset "Trigger never negative" begin
            payoff = TriggerPayoff(0.08, 0.0, 0.0)
            for r in [-0.50, -0.25, -0.10, -0.001]
                result = calculate(payoff, r)
                @test result.credited_return >= 0.0
            end
        end
    end

    @testset "Buffer Boundary - [T1]" begin
        payoff = BufferPayoff(0.10, 0.20)

        # At exact buffer boundary (-10%), credited return should be 0
        result = calculate(payoff, -0.10)
        @test result.credited_return ≈ 0.0 atol=1e-10
        @test result.buffer_applied

        # Just beyond buffer (-15%), excess loss passed through
        result = calculate(payoff, -0.15)
        @test result.credited_return ≈ -0.05 atol=1e-10
        @test result.buffer_applied
    end

    @testset "100% Buffer Edge Case - [T1]" begin
        # 100% buffer should provide FULL loss protection
        payoff = BufferPayoff(1.0, 0.25)

        for loss in [-0.30, -0.50, -0.75, -0.99]
            result = calculate(payoff, loss)
            @test result.credited_return == 0.0
            @test result.buffer_applied
        end
    end

    @testset "Floor at Boundary - [T1]" begin
        payoff = FloorPayoff(-0.10, 0.20)

        # At exact floor (-10%), credited return equals floor
        result = calculate(payoff, -0.10)
        @test result.credited_return ≈ -0.10 atol=1e-10

        # Beyond floor, loss is limited
        result = calculate(payoff, -0.25)
        @test result.credited_return == -0.10
        @test result.floor_applied
    end

    @testset "No-Arbitrage - [T1]" begin
        # Option value cannot exceed underlying
        S, K, r, q, σ, τ = 100.0, 100.0, 0.05, 0.02, 0.20, 1.0

        call = black_scholes_call(S, K, r, q, σ, τ)
        @test call < S
        @test validate_no_arbitrage(call, S) == PASS

        # Deliberate violation should HALT
        @test validate_no_arbitrage(S + 1.0, S) == HALT
    end

    @testset "Put-Call Parity - [T1]" begin
        S, K, r, q, σ, τ = 100.0, 100.0, 0.05, 0.02, 0.20, 1.0

        call = black_scholes_call(S, K, r, q, σ, τ)
        put = black_scholes_put(S, K, r, q, σ, τ)

        # Verify parity holds
        lhs = call - put
        rhs = S * exp(-q * τ) - K * exp(-r * τ)
        @test lhs ≈ rhs atol=1e-10

        # Validation gate should pass
        @test validate_put_call_parity(call, put, S, K, r, q, τ) == PASS

        # Deliberate violation should HALT
        bad_put = put + 0.10  # Inflate put by 10%
        @test validate_put_call_parity(call, bad_put, S, K, r, q, τ) == HALT
    end

    @testset "Buffer Absorbs Within Range - [T1]" begin
        payoff = BufferPayoff(0.10, 0.20)

        for loss in [-0.01, -0.05, -0.08, -0.10]
            result = calculate(payoff, loss)
            @test result.credited_return == 0.0
        end
    end

    @testset "Floor Protects Beyond - [T1]" begin
        payoff = FloorPayoff(-0.10, 0.20)

        for loss in [-0.15, -0.25, -0.50]
            result = calculate(payoff, loss)
            @test result.credited_return == -0.10
        end
    end

    @testset "Trigger at Threshold - [T1]" begin
        payoff = TriggerPayoff(0.08, 0.0, 0.0)

        # Exactly at threshold (0%) should trigger
        result = calculate(payoff, 0.0)
        @test result.credited_return == 0.08

        # Just below threshold should NOT trigger
        result = calculate(payoff, -0.001)
        @test result.credited_return == 0.0
    end

    @testset "Large Losses - [T1]" begin
        # Test extreme market scenarios

        @testset "FIA with large losses" begin
            cap_payoff = CappedCallPayoff(0.10, 0.0)
            for loss in [-0.50, -0.75, -0.90]
                result = calculate(cap_payoff, loss)
                @test result.credited_return == 0.0
            end
        end

        @testset "RILA buffer with large losses" begin
            buffer_payoff = BufferPayoff(0.10, 0.20)

            result = calculate(buffer_payoff, -0.50)
            @test result.credited_return == -0.40  # -50% + 10% buffer

            result = calculate(buffer_payoff, -0.75)
            @test result.credited_return == -0.65  # -75% + 10% buffer
        end

        @testset "RILA floor with large losses" begin
            floor_payoff = FloorPayoff(-0.10, 0.20)

            for loss in [-0.50, -0.75, -0.90]
                result = calculate(floor_payoff, loss)
                @test result.credited_return == -0.10  # Floor limits loss
            end
        end
    end

end
