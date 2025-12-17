using Test
using AnnuityCore
using Statistics

@testset "AnnuityCore.jl" begin
    # Core pricing
    include("test_black_scholes.jl")
    include("test_payoffs.jl")
    include("test_anti_patterns.jl")
    include("test_gbm.jl")
    include("test_monte_carlo.jl")
    include("test_ad_greeks.jl")

    # Stochastic volatility models (Phase 3.1)
    include("test_heston.jl")
    include("test_sabr.jl")
    include("test_heston_cos.jl")
    include("test_vol_surface.jl")

    # GLWB pricing (Phase 3.2)
    include("test_glwb.jl")
end
