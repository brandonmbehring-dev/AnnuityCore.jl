using Test
using AnnuityCore
using Statistics

@testset "AnnuityCore.jl" begin
    include("test_black_scholes.jl")
    include("test_payoffs.jl")
    include("test_anti_patterns.jl")
    include("test_gbm.jl")
    include("test_monte_carlo.jl")
    include("test_ad_greeks.jl")
end
