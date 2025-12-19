#=============================================================================
# Regulatory Module - Phase 9
#
# [PROTOTYPE] EDUCATIONAL USE ONLY - NOT FOR PRODUCTION REGULATORY FILING
# =========================================================================
# This module implements simplified NAIC VM-21 and VM-22 calculations for
# educational and research purposes. It is NOT suitable for:
# - Actual regulatory reserve filings
# - Statutory reporting
# - Compliance certification
#
# For production regulatory work, you need:
# 1. Qualified actuarial certification (FSA/MAAA)
# 2. NAIC-prescribed scenario generators (GOES/AAA ESG)
# 3. Full policy administration system integration
# 4. Independent model validation
# 5. Regulatory approval of methods
#
# See: docs/regulatory/AG43_COMPLIANCE_GAP.md for detailed gap analysis.
# =========================================================================
#
# Implements NAIC VM-21 and VM-22 for annuity reserves:
# - AG43/VM-21: Variable annuity reserve requirements
# - VM-22: Fixed annuity principle-based reserves
# - Scenario generation: Economic scenarios for stochastic modeling
#
# See: docs/knowledge/domain/vm21_vm22.md
=============================================================================#

# Include type definitions first
include("types.jl")

# Include implementations
include("scenarios.jl")
include("vm21.jl")
include("vm22.jl")
