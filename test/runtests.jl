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

    # Product Pricers (Phase 3.3)
    include("test_products.jl")

    # Behavioral Models (Phase 3.4)
    include("test_behavioral.jl")

    # Stress Testing (Phase 3.5)
    include("test_stress_testing.jl")

    # Data Loaders (Phase 3.6)
    include("test_loaders.jl")

    # Competitive Analysis (Phase 3.7)
    include("test_competitive.jl")

    # Credit Risk (Phase 3.8)
    include("test_credit.jl")

    # Validation Gates (Phase 3.9)
    include("test_validation_gates.jl")

    # Rate Setting (Phase 3.10)
    include("test_rate_setting.jl")

    # Regulatory (Phase 3.11)
    include("test_regulatory.jl")
end
