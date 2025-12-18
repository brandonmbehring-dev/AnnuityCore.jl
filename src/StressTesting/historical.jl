"""
Historical Crisis Scenarios.

[T2] Calibrated to actual market data from major crises (2000-2022).

Data sources:
- S&P 500 returns: Yahoo Finance
- Treasury rates: FRED
- VIX levels: CBOE

Each crisis includes:
- Peak-to-trough equity decline
- Interest rate change over crisis period
- VIX peak during stress
- Duration and recovery characteristics
- Monthly profile where available
"""

# ============================================================================
# 2008 Global Financial Crisis [T2]
# ============================================================================

"""
2008 Global Financial Crisis (Oct 2007 - Mar 2009).

[T2] Market data:
- S&P 500: -56.8% peak-to-trough
- 10Y Treasury: -254 bps (4.75% -> 2.21%)
- VIX peak: 80.9 (Nov 20, 2008)
- Duration: 17 months to trough
- Recovery: 54 months to previous high (Mar 2013)
"""
const CRISIS_2008_GFC = HistoricalCrisis(
    name = "2008_gfc",
    display_name = "2008 Global Financial Crisis",
    start_date = "2007-10",
    equity_shock = -0.568,
    rate_shock = -0.0254,
    vix_peak = 80.9,
    duration_months = 17,
    recovery_months = 54,
    recovery_type = U_SHAPED,
    profile = [
        CrisisProfile(0, 0.0, 0.0475, 18.0),
        CrisisProfile(3, -0.10, 0.0425, 22.0),
        CrisisProfile(6, -0.15, 0.0380, 24.0),
        CrisisProfile(9, -0.20, 0.0350, 26.0),
        CrisisProfile(12, -0.40, 0.0280, 45.0),
        CrisisProfile(15, -0.52, 0.0250, 65.0),
        CrisisProfile(17, -0.568, 0.0221, 80.9),  # Trough
        CrisisProfile(20, -0.45, 0.0280, 40.0),
        CrisisProfile(24, -0.35, 0.0340, 28.0),
    ]
)

# ============================================================================
# 2020 COVID-19 Crisis [T2]
# ============================================================================

"""
2020 COVID-19 Market Crash (Feb-Mar 2020).

[T2] Market data:
- S&P 500: -31.3% peak-to-trough (fastest 30%+ drop ever)
- 10Y Treasury: -138 bps (1.88% -> 0.50%)
- VIX peak: 82.69 (Mar 16, 2020) - highest ever
- Duration: 1 month to trough
- Recovery: 5 months (V-shaped, Aug 2020)
"""
const CRISIS_2020_COVID = HistoricalCrisis(
    name = "2020_covid",
    display_name = "2020 COVID-19 Crisis",
    start_date = "2020-02",
    equity_shock = -0.313,
    rate_shock = -0.0138,
    vix_peak = 82.69,
    duration_months = 1,
    recovery_months = 5,
    recovery_type = V_SHAPED,
    profile = [
        CrisisProfile(0, 0.0, 0.0188, 15.0),
        CrisisProfile(0.5, -0.12, 0.0140, 40.0),
        CrisisProfile(1, -0.313, 0.0050, 82.69),  # Trough
        CrisisProfile(2, -0.20, 0.0065, 45.0),
        CrisisProfile(3, -0.10, 0.0070, 30.0),
        CrisisProfile(5, 0.0, 0.0075, 22.0),      # Recovery
    ]
)

# ============================================================================
# 2000-2002 Dot-Com Crash [T2]
# ============================================================================

"""
2000-2002 Dot-Com Bubble Crash (Mar 2000 - Oct 2002).

[T2] Market data:
- S&P 500: -49.2% peak-to-trough
- 10Y Treasury: -221 bps (6.26% -> 4.05%)
- VIX peak: ~45 (Jul 2002)
- Duration: 31 months to trough
- Recovery: 56 months (Oct 2006, adjusted for 9/11)
"""
const CRISIS_2000_DOTCOM = HistoricalCrisis(
    name = "2000_dotcom",
    display_name = "2000-2002 Dot-Com Crash",
    start_date = "2000-03",
    equity_shock = -0.492,
    rate_shock = -0.0221,
    vix_peak = 45.0,
    duration_months = 31,
    recovery_months = 56,
    recovery_type = L_SHAPED,
    profile = [
        CrisisProfile(0, 0.0, 0.0626, 22.0),
        CrisisProfile(6, -0.12, 0.0580, 26.0),
        CrisisProfile(12, -0.25, 0.0520, 30.0),
        CrisisProfile(18, -0.30, 0.0480, 28.0),  # 9/11 spike
        CrisisProfile(24, -0.38, 0.0450, 32.0),
        CrisisProfile(31, -0.492, 0.0405, 45.0), # Trough
    ]
)

# ============================================================================
# 2011 European Debt Crisis [T2]
# ============================================================================

"""
2011 European Sovereign Debt Crisis (Apr-Oct 2011).

[T2] Market data:
- S&P 500: -14.5% peak-to-trough
- 10Y Treasury: -175 bps (3.75% -> 2.00%)
- VIX peak: 48 (Aug 8, 2011)
- Duration: 5 months
- Recovery: 6 months (double-dip pattern)
"""
const CRISIS_2011_EURO_DEBT = HistoricalCrisis(
    name = "2011_euro_debt",
    display_name = "2011 European Debt Crisis",
    start_date = "2011-04",
    equity_shock = -0.145,
    rate_shock = -0.0175,
    vix_peak = 48.0,
    duration_months = 5,
    recovery_months = 6,
    recovery_type = W_SHAPED,
    profile = [
        CrisisProfile(0, 0.0, 0.0375, 15.0),
        CrisisProfile(2, -0.05, 0.0320, 22.0),
        CrisisProfile(3, -0.10, 0.0260, 35.0),
        CrisisProfile(5, -0.145, 0.0200, 48.0),  # Trough
        CrisisProfile(7, -0.08, 0.0220, 30.0),
        CrisisProfile(8, -0.12, 0.0210, 38.0),   # Second dip
        CrisisProfile(11, 0.0, 0.0230, 18.0),
    ]
)

# ============================================================================
# 2015-2016 China/Oil Crisis [T2]
# ============================================================================

"""
2015-2016 China Slowdown / Oil Crisis (Aug 2015 - Feb 2016).

[T2] Market data:
- S&P 500: -12.3% peak-to-trough
- 10Y Treasury: -62 bps (2.25% -> 1.63%)
- VIX peak: 28 (Aug 24, 2015 - "Black Monday")
- Duration: 6 months
- Recovery: 7 months
"""
const CRISIS_2015_CHINA = HistoricalCrisis(
    name = "2015_china",
    display_name = "2015-16 China/Oil Crisis",
    start_date = "2015-08",
    equity_shock = -0.123,
    rate_shock = -0.0062,
    vix_peak = 28.0,
    duration_months = 6,
    recovery_months = 7,
    recovery_type = V_SHAPED,
    profile = [
        CrisisProfile(0, 0.0, 0.0225, 14.0),
        CrisisProfile(1, -0.08, 0.0210, 28.0),    # Flash crash
        CrisisProfile(3, -0.06, 0.0200, 18.0),
        CrisisProfile(5, -0.10, 0.0175, 22.0),
        CrisisProfile(6, -0.123, 0.0163, 26.0),   # Trough
        CrisisProfile(9, -0.05, 0.0180, 16.0),
        CrisisProfile(13, 0.0, 0.0195, 14.0),
    ]
)

# ============================================================================
# 2018 Q4 Selloff [T2]
# ============================================================================

"""
2018 Q4 Market Selloff (Oct-Dec 2018).

[T2] Market data:
- S&P 500: -19.3% peak-to-trough
- 10Y Treasury: -37 bps (3.23% -> 2.86%)
- VIX peak: 36 (Dec 24, 2018)
- Duration: 3 months
- Recovery: 4 months (V-shaped)
"""
const CRISIS_2018_Q4 = HistoricalCrisis(
    name = "2018_q4",
    display_name = "2018 Q4 Selloff",
    start_date = "2018-10",
    equity_shock = -0.193,
    rate_shock = -0.0037,
    vix_peak = 36.0,
    duration_months = 3,
    recovery_months = 4,
    recovery_type = V_SHAPED,
    profile = [
        CrisisProfile(0, 0.0, 0.0323, 13.0),
        CrisisProfile(1, -0.08, 0.0310, 22.0),
        CrisisProfile(2, -0.14, 0.0295, 28.0),
        CrisisProfile(3, -0.193, 0.0286, 36.0),   # Trough (Christmas Eve)
        CrisisProfile(4, -0.10, 0.0270, 20.0),
        CrisisProfile(7, 0.0, 0.0260, 14.0),
    ]
)

# ============================================================================
# 2022 Rate Shock [T2]
# ============================================================================

"""
2022 Rate Shock / Inflation Crisis (Jan-Oct 2022).

[T2] Market data:
- S&P 500: -24.9% peak-to-trough
- 10Y Treasury: +282 bps (1.52% -> 4.34%) - RISING rates (unique!)
- VIX peak: 36.5 (Mar 7, 2022)
- Duration: 10 months
- Recovery: Ongoing (as of analysis date)

Note: This is the ONLY crisis with rising rates - important for
testing scenarios where equity and rates move in opposite directions.
"""
const CRISIS_2022_RATES = HistoricalCrisis(
    name = "2022_rates",
    display_name = "2022 Rate Shock",
    start_date = "2022-01",
    equity_shock = -0.249,
    rate_shock = 0.0282,  # POSITIVE - rates rose!
    vix_peak = 36.5,
    duration_months = 10,
    recovery_months = 24,  # Estimated
    recovery_type = U_SHAPED,
    profile = [
        CrisisProfile(0, 0.0, 0.0152, 18.0),
        CrisisProfile(2, -0.12, 0.0200, 36.5),    # VIX peak (Russia)
        CrisisProfile(4, -0.15, 0.0295, 25.0),
        CrisisProfile(6, -0.20, 0.0320, 28.0),
        CrisisProfile(8, -0.18, 0.0390, 26.0),
        CrisisProfile(10, -0.249, 0.0434, 32.0),  # Trough
    ]
)

# ============================================================================
# Collections and Utilities
# ============================================================================

"""
All historical crises.
"""
const ALL_HISTORICAL_CRISES = [
    CRISIS_2008_GFC,
    CRISIS_2020_COVID,
    CRISIS_2000_DOTCOM,
    CRISIS_2011_EURO_DEBT,
    CRISIS_2015_CHINA,
    CRISIS_2018_Q4,
    CRISIS_2022_RATES
]

"""
Crises with falling rates (typical risk-off pattern).
"""
const FALLING_RATE_CRISES = [
    CRISIS_2008_GFC,
    CRISIS_2020_COVID,
    CRISIS_2000_DOTCOM,
    CRISIS_2011_EURO_DEBT,
    CRISIS_2015_CHINA,
    CRISIS_2018_Q4
]

"""
Crises with rising rates (stagflation/inflation pattern).
"""
const RISING_RATE_CRISES = [
    CRISIS_2022_RATES
]

"""
Get historical crisis by name.

# Example
```julia
crisis = get_crisis("2008_gfc")
```
"""
function get_crisis(name::String)::Union{HistoricalCrisis, Nothing}
    for crisis in ALL_HISTORICAL_CRISES
        crisis.name == name && return crisis
    end
    nothing
end

"""
Get all crises sorted by equity severity.
"""
function crises_by_severity()::Vector{HistoricalCrisis}
    sort(collect(ALL_HISTORICAL_CRISES), by=c -> c.equity_shock)
end

"""
Get all crises sorted by duration.
"""
function crises_by_duration()::Vector{HistoricalCrisis}
    sort(collect(ALL_HISTORICAL_CRISES), by=c -> c.duration_months, rev=true)
end

"""
Get all crises sorted by recovery time.
"""
function crises_by_recovery()::Vector{HistoricalCrisis}
    sort(collect(ALL_HISTORICAL_CRISES), by=c -> c.recovery_months, rev=true)
end

"""
Convert all historical crises to scenarios.
"""
function historical_scenarios()::Vector{StressScenario}
    [crisis_to_scenario(c) for c in ALL_HISTORICAL_CRISES]
end

# ============================================================================
# Profile Interpolation
# ============================================================================

"""
    interpolate_crisis_profile(crisis, month)

Interpolate crisis profile at a given month.

# Arguments
- `crisis::HistoricalCrisis`: Crisis with profile
- `month::Float64`: Month from crisis start

# Returns
- `CrisisProfile`: Interpolated profile values

# Example
```julia
profile = interpolate_crisis_profile(CRISIS_2008_GFC, 10.5)
```
"""
function interpolate_crisis_profile(crisis::HistoricalCrisis, month::Float64)::CrisisProfile
    profile = crisis.profile
    isempty(profile) && error("Crisis $(crisis.name) has no profile data")

    # Handle bounds
    month <= profile[1].month && return profile[1]
    month >= profile[end].month && return profile[end]

    # Find bracketing points
    for i in 1:(length(profile)-1)
        p1, p2 = profile[i], profile[i+1]
        if p1.month <= month <= p2.month
            # Linear interpolation
            t = (month - p1.month) / (p2.month - p1.month)
            return CrisisProfile(
                month,
                p1.equity_cumulative + t * (p2.equity_cumulative - p1.equity_cumulative),
                p1.rate_level + t * (p2.rate_level - p1.rate_level),
                p1.vix_level + t * (p2.vix_level - p1.vix_level)
            )
        end
    end

    # Fallback (shouldn't reach here)
    profile[end]
end

"""
    crisis_scenario_at_month(crisis, month)

Create stress scenario from crisis state at a specific month.

# Example
```julia
# Get scenario at 6 months into 2008 crisis
scenario = crisis_scenario_at_month(CRISIS_2008_GFC, 6.0)
```
"""
function crisis_scenario_at_month(crisis::HistoricalCrisis, month::Float64)::StressScenario
    isempty(crisis.profile) && return crisis_to_scenario(crisis)

    profile = interpolate_crisis_profile(crisis, month)

    # Calculate vol shock from VIX (baseline ~20)
    vol_shock = profile.vix_level / 20.0

    # Rate shock is change from initial
    initial_rate = crisis.profile[1].rate_level
    rate_shock = profile.rate_level - initial_rate

    StressScenario(
        name = "$(crisis.name)_m$(round(Int, month))",
        display_name = "$(crisis.display_name) Month $(round(Int, month))",
        equity_shock = profile.equity_cumulative,
        rate_shock = rate_shock,
        vol_shock = vol_shock,
        scenario_type = HISTORICAL
    )
end

"""
    generate_crisis_path(crisis; step_months=1.0)

Generate sequence of scenarios representing crisis evolution.

# Arguments
- `crisis::HistoricalCrisis`: Crisis to model
- `step_months::Float64`: Time step between scenarios

# Returns
- `Vector{StressScenario}`: Path of scenarios

# Example
```julia
path = generate_crisis_path(CRISIS_2020_COVID, step_months=0.5)
```
"""
function generate_crisis_path(
    crisis::HistoricalCrisis;
    step_months::Float64 = 1.0
)::Vector{StressScenario}
    isempty(crisis.profile) && return [crisis_to_scenario(crisis)]

    months = 0.0:step_months:crisis.profile[end].month
    [crisis_scenario_at_month(crisis, m) for m in months]
end

# ============================================================================
# Summary Statistics
# ============================================================================

"""
Print summary of historical crisis data.
"""
function print_crisis_summary()
    println("Historical Crisis Summary")
    println("="^70)
    println()

    for crisis in ALL_HISTORICAL_CRISES
        println("$(crisis.display_name) ($(crisis.start_date))")
        println("  Equity: $(round(Int, crisis.equity_shock * 100))%")
        sign_str = crisis.rate_shock >= 0 ? "+" : ""
        println("  Rates:  $(sign_str)$(round(Int, crisis.rate_shock * 10000)) bps")
        println("  VIX:    $(round(crisis.vix_peak, digits=1))")
        println("  Duration: $(crisis.duration_months) months → Recovery: $(crisis.recovery_months) months")
        println("  Pattern: $(crisis.recovery_type)")
        println()
    end
end

"""
Get crisis statistics as a dictionary.
"""
function crisis_statistics()::Dict{String, Any}
    Dict(
        "count" => length(ALL_HISTORICAL_CRISES),
        "worst_equity" => minimum(c.equity_shock for c in ALL_HISTORICAL_CRISES),
        "worst_rate_drop" => minimum(c.rate_shock for c in FALLING_RATE_CRISES),
        "worst_rate_rise" => maximum(c.rate_shock for c in RISING_RATE_CRISES),
        "highest_vix" => maximum(c.vix_peak for c in ALL_HISTORICAL_CRISES),
        "longest_duration" => maximum(c.duration_months for c in ALL_HISTORICAL_CRISES),
        "longest_recovery" => maximum(c.recovery_months for c in ALL_HISTORICAL_CRISES),
        "avg_equity" => mean(c.equity_shock for c in ALL_HISTORICAL_CRISES),
        "avg_duration" => mean(c.duration_months for c in ALL_HISTORICAL_CRISES)
    )
end
