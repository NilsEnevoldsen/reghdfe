// Simple data types --------------------------------------------------------

local Boolean 			real scalar
local Integer 			real scalar
local Real 				real scalar
local Vector			real colvector
local Matrix			real matrix
local Variable			real colvector	// N*1
local Variables			real matrix		// N*K
local String 			string scalar	// Arbitrary string
local Varname 			string scalar
local Varlist 			string rowvector // rowvector so they match tokens()

// Structures and classes ---------------------------------------------------

local FunctionP 		pointer(`Variables' function) scalar
local Solver			class reghdfe_solver scalar
local Options			class reghdfe_opt scalar
local Output			class reghdfe_out scalar
local FixedEffects		class reghdfe_fe  colvector

// Miscellanea ---------------------------------------------------------------

mata:
	mata clear
	mata set matastrict on
	mata set mataoptimize on
	mata set matalnum off
	// Taken from David Roodman's boottest
	string scalar reghdfe_stata_version() return("`c(stata_version)'")
end

// Include Mata files -------------------------------------------------------

include mata/reghdfe_solver.mata
include mata/reghdfe_fe.mata
include mata/reghdfe_opt.mata
include mata/reghdfe_out.mata











// local Problem			struct MapProblem scalar
// local FE				struct FixedEffect scalar

// ----------------------------------------------------------------------------
//	include assert_msg.mata
//	include FixedEffect.mata
//	include MapProblem.mata
//	include map_common.mata
//	include map_init.mata
//	include map_precompute.mata
//	include map_precompute_part1.mata
//	include map_precompute_part2.mata
//	include map_precompute_part3.mata
//	include map_projection.mata
//	include map_solve.mata
//	include map_save_fe.mata
//	include map_solve_accelerations.mata
//	include map_solve_transformations.mata
//	include map_estimate_dof.mata
//	include map_connected_groups.mata

	// This is not part of the MAP code but for simplicity we'll put it here
	//include fix_psd.mata
// ----------------------------------------------------------------------------
