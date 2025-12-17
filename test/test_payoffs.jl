using CSV
using DataFrames

# Helper function to create payoff from truth table row
# Must be defined before use in @testset
function create_payoff_from_row(row)
    method = row.method

    cap_rate = ismissing(row.cap_rate) ? nothing : row.cap_rate
    participation_rate = ismissing(row.participation_rate) ? nothing : row.participation_rate
    spread_rate = ismissing(row.spread_rate) ? nothing : row.spread_rate
    trigger_rate = ismissing(row.trigger_rate) ? nothing : row.trigger_rate
    trigger_threshold = ismissing(row.trigger_threshold) ? 0.0 : row.trigger_threshold
    buffer_rate = ismissing(row.buffer_rate) ? nothing : row.buffer_rate
    floor_rate = ismissing(row.floor_rate) ? nothing : row.floor_rate

    if method == "cap"
        return CappedCallPayoff(
            cap_rate === nothing ? 0.10 : cap_rate,
            floor_rate === nothing ? 0.0 : floor_rate
        )
    elseif method == "participation"
        return ParticipationPayoff(
            participation_rate === nothing ? 1.0 : participation_rate,
            cap_rate,
            floor_rate === nothing ? 0.0 : floor_rate
        )
    elseif method == "spread"
        return SpreadPayoff(
            spread_rate === nothing ? 0.0 : spread_rate,
            cap_rate,
            floor_rate === nothing ? 0.0 : floor_rate
        )
    elseif method == "trigger"
        return TriggerPayoff(
            trigger_rate === nothing ? 0.0 : trigger_rate,
            trigger_threshold,
            floor_rate === nothing ? 0.0 : floor_rate
        )
    elseif method == "buffer"
        return BufferPayoff(
            buffer_rate === nothing ? 0.10 : buffer_rate,
            cap_rate
        )
    elseif method == "floor"
        return FloorPayoff(
            floor_rate === nothing ? -0.10 : floor_rate,
            cap_rate
        )
    elseif method == "buffer_floor"
        return BufferWithFloorPayoff(
            buffer_rate === nothing ? 0.10 : buffer_rate,
            floor_rate === nothing ? -0.10 : floor_rate,
            cap_rate
        )
    elseif method == "step_rate"
        # Step rate uses tier1=buffer_rate, tier2=buffer_rate, tier2_protection=0.5
        br = buffer_rate === nothing ? 0.10 : buffer_rate
        return StepRateBufferPayoff(br, br, 0.50, cap_rate)
    elseif method == "buffer_vs_floor"
        # Comparison cases use buffer
        return BufferPayoff(
            buffer_rate === nothing ? 0.10 : buffer_rate,
            cap_rate
        )
    else
        error("Unknown method: $method")
    end
end

@testset "Payoffs" begin

    # Load truth table for validation
    truth_table_path = joinpath(@__DIR__, "references", "payoff_truth_tables.csv")
    truth_table = CSV.read(truth_table_path, DataFrame)

    @testset "Truth Table Validation - $(row.test_id)" for row in eachrow(truth_table)
        payoff = create_payoff_from_row(row)
        index_return = row.index_return
        expected = row.expected_payoff

        result = calculate(payoff, index_return)

        @test result.credited_return ≈ expected atol=1e-10
    end

    @testset "FIA Payoffs - Manual Tests" begin

        @testset "CappedCallPayoff" begin
            payoff = CappedCallPayoff(0.10, 0.0)

            # Positive return under cap
            r = calculate(payoff, 0.05)
            @test r.credited_return == 0.05
            @test !r.cap_applied
            @test !r.floor_applied

            # Positive return at cap
            r = calculate(payoff, 0.10)
            @test r.credited_return == 0.10
            @test !r.cap_applied  # Exactly at cap, not over

            # Positive return over cap
            r = calculate(payoff, 0.15)
            @test r.credited_return == 0.10
            @test r.cap_applied

            # Negative return (floored)
            r = calculate(payoff, -0.10)
            @test r.credited_return == 0.0
            @test r.floor_applied
        end

        @testset "ParticipationPayoff" begin
            payoff = ParticipationPayoff(0.80, 0.15, 0.0)  # 80% participation, 15% cap

            # Normal participation
            r = calculate(payoff, 0.10)
            @test r.credited_return ≈ 0.08 atol=1e-10  # 80% of 10%

            # Participation exceeds cap
            r = calculate(payoff, 0.20)
            @test r.credited_return == 0.15  # Capped at 15%
            @test r.cap_applied

            # Negative return (floored)
            r = calculate(payoff, -0.10)
            @test r.credited_return == 0.0
            @test r.floor_applied
        end

        @testset "SpreadPayoff" begin
            payoff = SpreadPayoff(0.02, nothing, 0.0)  # 2% spread, no cap

            # Normal spread
            r = calculate(payoff, 0.10)
            @test r.credited_return == 0.08  # 10% - 2%

            # Spread exceeds return (floored)
            r = calculate(payoff, 0.01)
            @test r.credited_return == 0.0
            @test r.floor_applied
        end

        @testset "TriggerPayoff" begin
            payoff = TriggerPayoff(0.08, 0.0, 0.0)  # 8% trigger at 0% threshold

            # Above threshold
            r = calculate(payoff, 0.05)
            @test r.credited_return == 0.08

            # At threshold (triggered)
            r = calculate(payoff, 0.0)
            @test r.credited_return == 0.08

            # Below threshold (not triggered)
            r = calculate(payoff, -0.01)
            @test r.credited_return == 0.0
            @test r.floor_applied
        end
    end

    @testset "RILA Payoffs - Manual Tests" begin

        @testset "BufferPayoff" begin
            payoff = BufferPayoff(0.10, 0.20)  # 10% buffer, 20% cap

            # Positive return under cap
            r = calculate(payoff, 0.15)
            @test r.credited_return == 0.15
            @test !r.buffer_applied

            # Positive return over cap
            r = calculate(payoff, 0.25)
            @test r.credited_return == 0.20
            @test r.cap_applied

            # Small loss (within buffer)
            r = calculate(payoff, -0.05)
            @test r.credited_return == 0.0
            @test r.buffer_applied

            # At exact buffer boundary
            r = calculate(payoff, -0.10)
            @test r.credited_return == 0.0
            @test r.buffer_applied

            # Beyond buffer
            r = calculate(payoff, -0.15)
            @test r.credited_return ≈ -0.05 atol=1e-10  # -15% + 10% buffer
            @test r.buffer_applied
        end

        @testset "BufferPayoff - 100% Buffer Edge Case" begin
            # [T1] 100% buffer should provide full protection
            payoff = BufferPayoff(1.0, 0.25)

            for loss in [-0.10, -0.30, -0.50, -0.75, -0.99]
                r = calculate(payoff, loss)
                @test r.credited_return == 0.0
                @test r.buffer_applied
            end
        end

        @testset "FloorPayoff" begin
            payoff = FloorPayoff(-0.10, 0.20)  # -10% floor, 20% cap

            # Positive return
            r = calculate(payoff, 0.15)
            @test r.credited_return == 0.15

            # Loss within floor
            r = calculate(payoff, -0.05)
            @test r.credited_return == -0.05
            @test !r.floor_applied

            # At exact floor
            r = calculate(payoff, -0.10)
            @test r.credited_return == -0.10
            @test !r.floor_applied

            # Beyond floor (protected)
            r = calculate(payoff, -0.25)
            @test r.credited_return == -0.10
            @test r.floor_applied
        end

        @testset "Buffer vs Floor at Breakeven" begin
            # At -20%: Buffer(-20% + 10%) = -10%, Floor(max(-20%, -10%)) = -10%
            buffer_payoff = BufferPayoff(0.10, 0.20)
            floor_payoff = FloorPayoff(-0.10, 0.20)

            buffer_result = calculate(buffer_payoff, -0.20)
            floor_result = calculate(floor_payoff, -0.20)

            @test buffer_result.credited_return ≈ floor_result.credited_return atol=1e-10
            @test buffer_result.credited_return == -0.10
        end
    end

end
