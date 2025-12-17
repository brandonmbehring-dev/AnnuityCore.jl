"""
Benchmark suite for AnnuityCore.jl

Run with:
    julia --project=. benchmark/benchmarks.jl

Or to run specific benchmarks:
    julia --project=. -e 'using AnnuityCore; include("benchmark/benchmarks.jl"); run(SUITE["bs"])'
"""

using BenchmarkTools
using AnnuityCore
using Random

# Create benchmark suite
const SUITE = BenchmarkGroup()

# =============================================================================
# Black-Scholes Benchmarks
# =============================================================================

SUITE["bs"] = BenchmarkGroup()

# Single call pricing
SUITE["bs"]["call_single"] = @benchmarkable black_scholes_call(100.0, 100.0, 0.05, 0.02, 0.20, 1.0)

# Single put pricing
SUITE["bs"]["put_single"] = @benchmarkable black_scholes_put(100.0, 100.0, 0.05, 0.02, 0.20, 1.0)

# Greeks calculation
SUITE["bs"]["greeks"] = @benchmarkable black_scholes_greeks(100.0, 100.0, 0.05, 0.02, 0.20, 1.0)

# Batch pricing (1K calls)
SUITE["bs"]["call_1K"] = @benchmarkable begin
    for _ in 1:1_000
        black_scholes_call(100.0, 100.0, 0.05, 0.02, 0.20, 1.0)
    end
end

# Batch pricing (1M calls)
SUITE["bs"]["call_1M"] = @benchmarkable begin
    for _ in 1:1_000_000
        black_scholes_call(100.0, 100.0, 0.05, 0.02, 0.20, 1.0)
    end
end


# =============================================================================
# FIA Payoff Benchmarks
# =============================================================================

SUITE["fia"] = BenchmarkGroup()

# Cap payoff
SUITE["fia"]["cap_single"] = @benchmarkable calculate(CappedCallPayoff(0.10, 0.0), 0.08)

# Participation payoff
SUITE["fia"]["participation_single"] = @benchmarkable calculate(ParticipationPayoff(0.80, 0.15, 0.0), 0.10)

# Spread payoff
SUITE["fia"]["spread_single"] = @benchmarkable calculate(SpreadPayoff(0.02, nothing, 0.0), 0.10)

# Trigger payoff
SUITE["fia"]["trigger_single"] = @benchmarkable calculate(TriggerPayoff(0.08, 0.0, 0.0), 0.05)

# Vectorized cap payoff (10K returns)
SUITE["fia"]["cap_vectorized"] = @benchmarkable begin
    payoff = CappedCallPayoff(0.10, 0.0)
    for r in returns
        calculate(payoff, r)
    end
end setup=(returns = randn(10_000) * 0.20)


# =============================================================================
# RILA Payoff Benchmarks
# =============================================================================

SUITE["rila"] = BenchmarkGroup()

# Buffer payoff
SUITE["rila"]["buffer_single"] = @benchmarkable calculate(BufferPayoff(0.10, 0.20), -0.05)

# Floor payoff
SUITE["rila"]["floor_single"] = @benchmarkable calculate(FloorPayoff(-0.10, 0.20), -0.15)

# Buffer+Floor payoff
SUITE["rila"]["buffer_floor_single"] = @benchmarkable calculate(BufferWithFloorPayoff(0.10, -0.10, 0.20), -0.15)

# Step-rate buffer payoff
SUITE["rila"]["step_rate_single"] = @benchmarkable calculate(StepRateBufferPayoff(0.10, 0.10, 0.50, 0.20), -0.15)

# Vectorized buffer payoff (10K returns)
SUITE["rila"]["buffer_vectorized"] = @benchmarkable begin
    payoff = BufferPayoff(0.10, 0.20)
    for r in returns
        calculate(payoff, r)
    end
end setup=(returns = randn(10_000) * 0.20)

# 100% buffer edge case
SUITE["rila"]["100_buffer"] = @benchmarkable calculate(BufferPayoff(1.0, 0.25), -0.50)


# =============================================================================
# Validation Benchmarks
# =============================================================================

SUITE["validation"] = BenchmarkGroup()

# No-arbitrage check
SUITE["validation"]["no_arbitrage"] = @benchmarkable validate_no_arbitrage(5.0, 100.0)

# Put-call parity check
SUITE["validation"]["pcp"] = @benchmarkable validate_put_call_parity(10.0, 8.0, 100.0, 100.0, 0.05, 0.02, 1.0)


# =============================================================================
# Run Benchmarks
# =============================================================================

if abspath(PROGRAM_FILE) == @__FILE__
    println("Running AnnuityCore.jl Benchmarks")
    println("=" ^ 60)

    # Run and display results
    results = run(SUITE, verbose=true, seconds=5)

    println("\n" * "=" ^ 60)
    println("Summary")
    println("=" ^ 60)

    for (group_name, group_results) in results
        println("\n$group_name:")
        for (bench_name, bench_result) in group_results
            median_time = BenchmarkTools.median(bench_result).time / 1e9  # Convert to seconds
            if median_time < 1e-6
                println("  $bench_name: $(round(median_time * 1e9, digits=2)) ns")
            elseif median_time < 1e-3
                println("  $bench_name: $(round(median_time * 1e6, digits=2)) μs")
            else
                println("  $bench_name: $(round(median_time * 1e3, digits=2)) ms")
            end
        end
    end

    # TTFX measurement advice
    println("\n" * "=" ^ 60)
    println("TTFX (Time-To-First-X) Notes:")
    println("=" ^ 60)
    println("""
    To measure TTFX, run from fresh Julia session:

        time julia --project=. -e 'using AnnuityCore; black_scholes_call(100.0, 100.0, 0.05, 0.02, 0.20, 1.0)'

    Target: < 3 seconds for full package load + first calculation
    """)
end
