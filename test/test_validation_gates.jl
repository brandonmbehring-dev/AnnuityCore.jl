"""
Tests for the Validation Gates framework.

Covers:
- Core types (GateResult, ValidationReport)
- All 8 gate implementations
- ValidationEngine
- Convenience functions
- Edge cases and anti-patterns
"""

@testset "Validation Gates" begin

    #=========================================================================
    # Core Types Tests
    =========================================================================#

    @testset "GateResult" begin
        @testset "Construction" begin
            result = GateResult(
                status = PASS,
                gate_name = "test_gate",
                message = "Test passed"
            )
            @test result.status == PASS
            @test result.gate_name == "test_gate"
            @test result.message == "Test passed"
            @test result.value === nothing
            @test result.threshold === nothing
        end

        @testset "With value and threshold" begin
            result = GateResult(
                status = HALT,
                gate_name = "test_gate",
                message = "Value exceeded threshold",
                value = 150.0,
                threshold = 100.0
            )
            @test result.value == 150.0
            @test result.threshold == 100.0
        end

        @testset "passed function" begin
            @test passed(GateResult(status = PASS, gate_name = "g", message = "m"))
            @test passed(GateResult(status = WARN, gate_name = "g", message = "m"))
            @test !passed(GateResult(status = HALT, gate_name = "g", message = "m"))
        end
    end

    @testset "ValidationReport" begin
        @testset "All pass" begin
            results = [
                GateResult(status = PASS, gate_name = "g1", message = "m1"),
                GateResult(status = PASS, gate_name = "g2", message = "m2")
            ]
            report = ValidationReport(results)
            @test overall_status(report) == PASS
            @test passed(report)
            @test isempty(halted_gates(report))
            @test isempty(warned_gates(report))
        end

        @testset "One warning" begin
            results = [
                GateResult(status = PASS, gate_name = "g1", message = "m1"),
                GateResult(status = WARN, gate_name = "g2", message = "m2")
            ]
            report = ValidationReport(results)
            @test overall_status(report) == WARN
            @test passed(report)  # WARN still passes
            @test length(warned_gates(report)) == 1
        end

        @testset "One halt" begin
            results = [
                GateResult(status = PASS, gate_name = "g1", message = "m1"),
                GateResult(status = HALT, gate_name = "g2", message = "m2")
            ]
            report = ValidationReport(results)
            @test overall_status(report) == HALT
            @test !passed(report)
            @test length(halted_gates(report)) == 1
        end

        @testset "Halt overrides warn" begin
            results = [
                GateResult(status = WARN, gate_name = "g1", message = "m1"),
                GateResult(status = HALT, gate_name = "g2", message = "m2")
            ]
            report = ValidationReport(results)
            @test overall_status(report) == HALT
        end

        @testset "Dict conversion" begin
            results = [
                GateResult(status = PASS, gate_name = "g1", message = "m1"),
                GateResult(status = HALT, gate_name = "g2", message = "m2", value = 1.0)
            ]
            report = ValidationReport(results)
            d = Dict(report)
            @test d[:overall_status] == "HALT"
            @test d[:passed] == false
            @test d[:n_halted] == 1
            @test length(d[:results]) == 2
        end
    end

    #=========================================================================
    # PresentValueBoundsGate Tests
    =========================================================================#

    @testset "PresentValueBoundsGate" begin
        gate = PresentValueBoundsGate()

        @testset "Valid PV passes" begin
            # Create a simple mock result with present_value field
            result = (present_value = 100.0,)
            gate_result = check(gate, result, premium = 100.0)
            @test gate_result.status == PASS
        end

        @testset "Negative PV halts" begin
            result = (present_value = -10.0,)
            gate_result = check(gate, result, premium = 100.0)
            @test gate_result.status == HALT
            @test occursin("below minimum", gate_result.message)
        end

        @testset "PV exceeds max multiple halts" begin
            result = (present_value = 400.0,)  # 4x premium, default max is 3x
            gate_result = check(gate, result, premium = 100.0)
            @test gate_result.status == HALT
            @test occursin("exceeds", gate_result.message)
        end

        @testset "Custom bounds" begin
            custom_gate = PresentValueBoundsGate(min_pv = 10.0, max_pv_multiple = 2.0)

            # Just above min
            result = (present_value = 15.0,)
            @test check(custom_gate, result, premium = 100.0).status == PASS

            # Below custom min
            result = (present_value = 5.0,)
            @test check(custom_gate, result, premium = 100.0).status == HALT

            # Above custom max (2x = 200)
            result = (present_value = 250.0,)
            @test check(custom_gate, result, premium = 100.0).status == HALT
        end
    end

    #=========================================================================
    # DurationBoundsGate Tests
    =========================================================================#

    @testset "DurationBoundsGate" begin
        gate = DurationBoundsGate()

        @testset "Valid duration passes" begin
            result = (present_value = 100.0, duration = 5.0)
            gate_result = check(gate, result)
            @test gate_result.status == PASS
        end

        @testset "Negative duration halts" begin
            result = (present_value = 100.0, duration = -1.0)
            gate_result = check(gate, result)
            @test gate_result.status == HALT
            @test occursin("negative", gate_result.message)
        end

        @testset "Duration exceeds max halts" begin
            result = (present_value = 100.0, duration = 35.0)  # Default max is 30
            gate_result = check(gate, result)
            @test gate_result.status == HALT
            @test occursin("exceeds maximum", gate_result.message)
        end

        @testset "No duration field passes" begin
            result = (present_value = 100.0,)  # No duration field
            gate_result = check(gate, result)
            @test gate_result.status == PASS
            @test occursin("not available", gate_result.message)
        end

        @testset "Custom max duration" begin
            custom_gate = DurationBoundsGate(max_duration = 10.0)
            result = (present_value = 100.0, duration = 15.0)
            @test check(custom_gate, result).status == HALT
        end
    end

    #=========================================================================
    # FIAOptionBudgetGate Tests
    =========================================================================#

    @testset "FIAOptionBudgetGate" begin
        gate = FIAOptionBudgetGate()

        @testset "Within budget passes" begin
            result = FIAPricingResult(
                100.0, 2.5, 3.0, 0.08, 0.55, 0.035,
                Dict{Symbol, Any}()
            )
            gate_result = check(gate, result)
            @test gate_result.status == PASS
        end

        @testset "Zero budget halts" begin
            result = FIAPricingResult(
                100.0, 5.0, 0.0, 0.08, 0.55, 0.035,
                Dict{Symbol, Any}()
            )
            gate_result = check(gate, result)
            @test gate_result.status == HALT
            @test occursin("zero or negative", gate_result.message)
        end

        @testset "Exceeds budget by more than tolerance halts" begin
            result = FIAPricingResult(
                100.0, 5.0, 3.0, 0.08, 0.55, 0.035,  # 5.0 / 3.0 = 1.67, >1.10
                Dict{Symbol, Any}()
            )
            gate_result = check(gate, result)
            @test gate_result.status == HALT
        end

        @testset "Within tolerance passes" begin
            result = FIAPricingResult(
                100.0, 3.2, 3.0, 0.08, 0.55, 0.035,  # 3.2 / 3.0 = 1.067, <1.10
                Dict{Symbol, Any}()
            )
            gate_result = check(gate, result)
            @test gate_result.status == PASS
        end

        @testset "Non-FIA result skipped" begin
            result = (present_value = 100.0,)
            gate_result = check(gate, result)
            @test gate_result.status == PASS
            @test occursin("Not a FIA", gate_result.message)
        end

        @testset "Custom tolerance" begin
            strict_gate = FIAOptionBudgetGate(tolerance = 0.01)
            result = FIAPricingResult(
                100.0, 3.05, 3.0, 0.08, 0.55, 0.035,  # 3.05 / 3.0 = 1.017, >1.01
                Dict{Symbol, Any}()
            )
            @test check(strict_gate, result).status == HALT
        end
    end

    #=========================================================================
    # FIAExpectedCreditGate Tests
    =========================================================================#

    @testset "FIAExpectedCreditGate" begin
        gate = FIAExpectedCreditGate()

        @testset "Positive credit passes" begin
            result = FIAPricingResult(
                100.0, 3.0, 3.0, 0.08, 0.55, 0.035,
                Dict{Symbol, Any}()
            )
            gate_result = check(gate, result)
            @test gate_result.status == PASS
        end

        @testset "Negative credit halts (violates floor)" begin
            result = FIAPricingResult(
                100.0, 3.0, 3.0, 0.08, 0.55, -0.02,  # Negative expected credit
                Dict{Symbol, Any}()
            )
            gate_result = check(gate, result)
            @test gate_result.status == HALT
            @test occursin("negative", gate_result.message)
            @test occursin("floor", gate_result.message)
        end

        @testset "Credit exceeds cap halts" begin
            result = FIAPricingResult(
                100.0, 3.0, 3.0, 0.08, 0.55, 0.15,  # 15% expected credit
                Dict{Symbol, Any}()
            )
            gate_result = check(gate, result, cap_rate = 0.10)
            @test gate_result.status == HALT
            @test occursin("exceeds", gate_result.message)
        end

        @testset "Non-FIA result skipped" begin
            result = (present_value = 100.0,)
            gate_result = check(gate, result)
            @test gate_result.status == PASS
        end
    end

    #=========================================================================
    # RILAMaxLossGate Tests
    =========================================================================#

    @testset "RILAMaxLossGate" begin
        gate = RILAMaxLossGate()

        @testset "Valid max loss passes" begin
            result = RILAPricingResult(
                100.0, 10.0, :buffer, 15.0, 0.05, 0.90, -0.02,
                Dict{Symbol, Any}()
            )
            gate_result = check(gate, result)
            @test gate_result.status == PASS
        end

        @testset "Negative max loss halts" begin
            result = RILAPricingResult(
                100.0, 10.0, :buffer, 15.0, 0.05, -0.10, -0.02,
                Dict{Symbol, Any}()
            )
            gate_result = check(gate, result)
            @test gate_result.status == HALT
            @test occursin("negative", gate_result.message)
        end

        @testset "Max loss > 100% halts" begin
            result = RILAPricingResult(
                100.0, 10.0, :buffer, 15.0, 0.05, 1.50, -0.02,
                Dict{Symbol, Any}()
            )
            gate_result = check(gate, result)
            @test gate_result.status == HALT
            @test occursin("exceeds 100%", gate_result.message)
        end

        @testset "Buffer max loss consistency warns" begin
            # With 10% buffer, expected max loss = 90%
            result = RILAPricingResult(
                100.0, 10.0, :buffer, 15.0, 0.05, 0.80, -0.02,  # 80% doesn't match 90%
                Dict{Symbol, Any}()
            )
            gate_result = check(gate, result, buffer_rate = 0.10)
            @test gate_result.status == WARN
        end

        @testset "Non-RILA result skipped" begin
            result = (present_value = 100.0,)
            gate_result = check(gate, result)
            @test gate_result.status == PASS
        end
    end

    #=========================================================================
    # RILAProtectionValueGate Tests
    =========================================================================#

    @testset "RILAProtectionValueGate" begin
        gate = RILAProtectionValueGate()

        @testset "Valid protection value passes" begin
            result = RILAPricingResult(
                100.0, 10.0, :buffer, 15.0, 0.05, 0.90, -0.02,
                Dict{Symbol, Any}()
            )
            gate_result = check(gate, result, premium = 100.0)
            @test gate_result.status == PASS
        end

        @testset "Negative protection halts" begin
            result = RILAPricingResult(
                100.0, -5.0, :buffer, 15.0, 0.05, 0.90, -0.02,
                Dict{Symbol, Any}()
            )
            gate_result = check(gate, result, premium = 100.0)
            @test gate_result.status == HALT
            @test occursin("negative", gate_result.message)
        end

        @testset "Protection exceeds 50% warns" begin
            result = RILAPricingResult(
                100.0, 60.0, :buffer, 15.0, 0.05, 0.90, -0.02,  # 60 > 50% of 100
                Dict{Symbol, Any}()
            )
            gate_result = check(gate, result, premium = 100.0)
            @test gate_result.status == WARN
        end

        @testset "Custom max percentage" begin
            strict_gate = RILAProtectionValueGate(max_protection_pct = 0.20)
            result = RILAPricingResult(
                100.0, 25.0, :buffer, 15.0, 0.05, 0.90, -0.02,  # 25 > 20% of 100
                Dict{Symbol, Any}()
            )
            @test check(strict_gate, result, premium = 100.0).status == WARN
        end

        @testset "Non-RILA result skipped" begin
            result = (present_value = 100.0,)
            gate_result = check(gate, result)
            @test gate_result.status == PASS
        end
    end

    #=========================================================================
    # ArbitrageBoundsGate Tests
    =========================================================================#

    @testset "ArbitrageBoundsGate" begin
        gate = ArbitrageBoundsGate()

        @testset "FIA - Option value < premium passes" begin
            result = FIAPricingResult(
                100.0, 5.0, 3.0, 0.08, 0.55, 0.035,
                Dict{Symbol, Any}()
            )
            gate_result = check(gate, result, premium = 100.0)
            @test gate_result.status == PASS
        end

        @testset "FIA - Option value > premium halts" begin
            result = FIAPricingResult(
                100.0, 150.0, 3.0, 0.08, 0.55, 0.035,  # 150 > 100 premium
                Dict{Symbol, Any}()
            )
            gate_result = check(gate, result, premium = 100.0)
            @test gate_result.status == HALT
            @test occursin("arbitrage", gate_result.message)
        end

        @testset "RILA - Protection < max loss passes" begin
            result = RILAPricingResult(
                100.0, 10.0, :buffer, 15.0, 0.05, 0.90, -0.02,
                Dict{Symbol, Any}()
            )
            gate_result = check(gate, result, premium = 100.0)
            @test gate_result.status == PASS
        end

        @testset "RILA - Protection > max loss halts" begin
            result = RILAPricingResult(
                100.0, 100.0, :buffer, 15.0, 0.05, 0.10, -0.02,  # 100 > 10% * 100 = 10
                Dict{Symbol, Any}()
            )
            gate_result = check(gate, result, premium = 100.0)
            @test gate_result.status == HALT
        end

        @testset "Other result types pass" begin
            result = (present_value = 100.0,)
            gate_result = check(gate, result)
            @test gate_result.status == PASS
        end
    end

    #=========================================================================
    # ProductParameterSanityGate Tests
    =========================================================================#

    @testset "ProductParameterSanityGate" begin
        gate = ProductParameterSanityGate()

        @testset "Valid parameters pass" begin
            result = (present_value = 100.0,)
            gate_result = check(gate, result,
                cap_rate = 0.10,
                participation_rate = 0.80,
                buffer_rate = 0.10,
                spread_rate = 0.02
            )
            @test gate_result.status == PASS
        end

        @testset "Negative cap rate halts" begin
            result = (present_value = 100.0,)
            gate_result = check(gate, result, cap_rate = -0.05)
            @test gate_result.status == HALT
            @test occursin("cap_rate", gate_result.message)
            @test occursin("negative", gate_result.message)
        end

        @testset "Cap rate > 30% halts" begin
            result = (present_value = 100.0,)
            gate_result = check(gate, result, cap_rate = 0.40)
            @test gate_result.status == HALT
            @test occursin("cap_rate", gate_result.message)
            @test occursin("exceeds", gate_result.message)
        end

        @testset "Participation rate <= 0 halts" begin
            result = (present_value = 100.0,)
            gate_result = check(gate, result, participation_rate = 0.0)
            @test gate_result.status == HALT
            @test occursin("participation_rate", gate_result.message)
        end

        @testset "Participation rate > 300% halts" begin
            result = (present_value = 100.0,)
            gate_result = check(gate, result, participation_rate = 4.0)
            @test gate_result.status == HALT
        end

        @testset "Buffer rate negative halts" begin
            result = (present_value = 100.0,)
            gate_result = check(gate, result, buffer_rate = -0.05)
            @test gate_result.status == HALT
        end

        @testset "Buffer rate > 30% halts" begin
            result = (present_value = 100.0,)
            gate_result = check(gate, result, buffer_rate = 0.40)
            @test gate_result.status == HALT
        end

        @testset "Spread rate > 10% halts" begin
            result = (present_value = 100.0,)
            gate_result = check(gate, result, spread_rate = 0.15)
            @test gate_result.status == HALT
        end

        @testset "Multiple issues reported" begin
            result = (present_value = 100.0,)
            gate_result = check(gate, result,
                cap_rate = -0.05,
                buffer_rate = 0.50
            )
            @test gate_result.status == HALT
            @test length(gate_result.value) == 2  # Two issues
        end
    end

    #=========================================================================
    # ValidationEngine Tests
    =========================================================================#

    @testset "ValidationEngine" begin
        @testset "Default gates" begin
            engine = ValidationEngine()
            @test length(engine.gates) == 8
        end

        @testset "Custom gates" begin
            gates = [PresentValueBoundsGate(), DurationBoundsGate()]
            engine = ValidationEngine(gates)
            @test length(engine.gates) == 2
        end

        @testset "validate function" begin
            engine = ValidationEngine()
            result = FIAPricingResult(
                100.0, 3.0, 3.0, 0.08, 0.55, 0.035,
                Dict{Symbol, Any}()
            )
            report = validate(engine, result, premium = 100.0)
            @test report isa ValidationReport
            @test length(report.results) == 8
        end

        @testset "validate_and_raise - passes" begin
            engine = ValidationEngine()
            result = FIAPricingResult(
                100.0, 2.5, 3.0, 0.08, 0.55, 0.035,
                Dict{Symbol, Any}()
            )
            returned = validate_and_raise(engine, result, premium = 100.0)
            @test returned === result
        end

        @testset "validate_and_raise - halts" begin
            engine = ValidationEngine()
            result = FIAPricingResult(
                -10.0, 3.0, 3.0, 0.08, 0.55, 0.035,  # Negative PV
                Dict{Symbol, Any}()
            )
            @test_throws ErrorException validate_and_raise(engine, result, premium = 100.0)
        end
    end

    #=========================================================================
    # Convenience Functions Tests
    =========================================================================#

    @testset "Convenience Functions" begin
        @testset "validate_pricing_result" begin
            result = FIAPricingResult(
                100.0, 2.5, 3.0, 0.08, 0.55, 0.035,
                Dict{Symbol, Any}()
            )
            report = validate_pricing_result(result, premium = 100.0)
            @test passed(report)
        end

        @testset "ensure_valid - passes" begin
            result = FIAPricingResult(
                100.0, 2.5, 3.0, 0.08, 0.55, 0.035,
                Dict{Symbol, Any}()
            )
            returned = ensure_valid(result, premium = 100.0)
            @test returned === result
        end

        @testset "ensure_valid - halts" begin
            result = FIAPricingResult(
                -10.0, 3.0, 3.0, 0.08, 0.55, 0.035,
                Dict{Symbol, Any}()
            )
            @test_throws ErrorException ensure_valid(result, premium = 100.0)
        end
    end

    #=========================================================================
    # Standalone Validation Functions Tests
    =========================================================================#

    @testset "Standalone Functions" begin
        @testset "validate_no_arbitrage" begin
            @test validate_no_arbitrage(5.0, 100.0) == PASS
            @test validate_no_arbitrage(100.0, 100.0) == PASS
            @test validate_no_arbitrage(101.0, 100.0) == HALT
            @test validate_no_arbitrage(100.0 + 1e-11, 100.0) == PASS  # Within tolerance
        end

        @testset "validate_put_call_parity" begin
            # Perfect parity
            S, K, r, q, τ = 100.0, 100.0, 0.05, 0.02, 1.0
            call = black_scholes_call(S, K, r, q, 0.20, τ)
            put = black_scholes_put(S, K, r, q, 0.20, τ)
            @test validate_put_call_parity(call, put, S, K, r, q, τ) == PASS

            # Small violation (WARN)
            @test validate_put_call_parity(call + 0.005, put, S, K, r, q, τ) == WARN

            # Large violation (HALT)
            @test validate_put_call_parity(call + 0.05, put, S, K, r, q, τ) == HALT
        end
    end

    #=========================================================================
    # Integration Tests
    =========================================================================#

    @testset "Integration" begin
        @testset "FIA full validation" begin
            result = FIAPricingResult(
                100.0, 2.5, 3.0, 0.08, 0.55, 0.035,
                Dict{Symbol, Any}()
            )
            report = validate_pricing_result(result,
                premium = 100.0,
                cap_rate = 0.10
            )
            @test passed(report)
            @test overall_status(report) == PASS
        end

        @testset "RILA full validation" begin
            result = RILAPricingResult(
                100.0, 10.0, :buffer, 15.0, 0.05, 0.90, -0.02,
                Dict{Symbol, Any}()
            )
            report = validate_pricing_result(result,
                premium = 100.0,
                buffer_rate = 0.10
            )
            @test passed(report)
        end

        @testset "Multiple failures captured" begin
            result = FIAPricingResult(
                -10.0, 150.0, 0.0, 0.08, 0.55, -0.05,
                Dict{Symbol, Any}()
            )
            report = validate_pricing_result(result, premium = 100.0)
            @test !passed(report)
            @test length(halted_gates(report)) >= 3  # PV, budget, credit, arbitrage
        end
    end

    #=========================================================================
    # Anti-Pattern Tests
    =========================================================================#

    @testset "Anti-Patterns" begin
        @testset "Sanity bounds prevent extreme values" begin
            gate = ProductParameterSanityGate()
            result = (present_value = 100.0,)

            # These should all be caught
            @test check(gate, result, cap_rate = 0.50).status == HALT
            @test check(gate, result, participation_rate = 5.0).status == HALT
            @test check(gate, result, buffer_rate = 0.50).status == HALT
            @test check(gate, result, spread_rate = 0.20).status == HALT
        end

        @testset "Arbitrage violations caught" begin
            gate = ArbitrageBoundsGate()

            # FIA option value > premium
            fia_result = FIAPricingResult(
                100.0, 200.0, 3.0, 0.08, 0.55, 0.035,
                Dict{Symbol, Any}()
            )
            @test check(gate, fia_result, premium = 100.0).status == HALT

            # RILA protection > max loss value
            rila_result = RILAPricingResult(
                100.0, 50.0, :buffer, 15.0, 0.05, 0.10, -0.02,
                Dict{Symbol, Any}()
            )
            @test check(gate, rila_result, premium = 100.0).status == HALT
        end

        @testset "Empty or minimal validation report" begin
            # All gates should run even if result is minimal
            engine = ValidationEngine()
            result = (present_value = 50.0,)
            report = validate(engine, result, premium = 100.0)
            @test length(report.results) == 8  # All gates ran
        end
    end

    #=========================================================================
    # Display Tests
    =========================================================================#

    @testset "Display" begin
        @testset "GateResult show" begin
            result = GateResult(status = PASS, gate_name = "test", message = "Test passed")
            io = IOBuffer()
            show(io, result)
            str = String(take!(io))
            @test occursin("✓", str)
            @test occursin("test", str)
        end

        @testset "ValidationReport show" begin
            results = [
                GateResult(status = PASS, gate_name = "g1", message = "m1"),
                GateResult(status = HALT, gate_name = "g2", message = "m2")
            ]
            report = ValidationReport(results)
            io = IOBuffer()
            show(io, report)
            str = String(take!(io))
            @test occursin("HALTED", str)
        end

        @testset "print_validation_report" begin
            results = [
                GateResult(status = PASS, gate_name = "g1", message = "m1"),
                GateResult(status = WARN, gate_name = "g2", message = "m2"),
                GateResult(status = HALT, gate_name = "g3", message = "m3", value = 1.0, threshold = 0.5)
            ]
            report = ValidationReport(results)
            io = IOBuffer()
            print_validation_report(report, io = io)
            str = String(take!(io))
            @test occursin("HALTED", str)
            @test occursin("WARNED", str)
            @test occursin("PASSED", str)
        end
    end

end
