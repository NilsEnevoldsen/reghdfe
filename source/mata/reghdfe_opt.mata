// REGHDFE solver options
mata:
mata set matastrict on

class reghdfe_opt {
	`Boolean'		timeit				// Show elapsed time?
	`Boolean'		fast				// Faster; by removing features
	`Boolean'		ffirst				// First-stage F tests (IV/GMM only)
	`Boolean'		savecache			//
	`Boolean'		usecache			//
	`Boolean'		save_all_fe			// Save all FEs (auto naming if needed)
	`Boolean'		save_any_fe			// Save at least 1 FE
	`Boolean'		has_intercept		// Do the FEs include an intercept?
	`Boolean'		keepsingletons		// Default to 0
	`Boolean'		vce_is_hac
	`Boolean'		noabsorb			// 1 if we only have a constant term

	`Integer'		verbose			// Freq. of debug messages (0 to 4)

	`String'		select_if			// If condition
	`String'		select_in			// In condition

	`Varlist'		keepvars			// Used with cache(save)

	`String'		depvar				//
	`String'		indepvars			//
	`String'		endogvars			//
	`String'		instruments			//

	`String'		fe_format			// Format of the depvar
	`String'		estimator			// 2sls, gmm2s, etc (IV/GMM only)
	`String'		ivsuite				// ivregress/ivreg2

	`String'		weight_var			// Weighting variable
	`String'		weight_type			// Weight type (pw, fw, etc)
	`String'		weight_exp			// "[weight_type=weight_var]"
	`String'		original_absvars	// 
	`String'		extended_absvars	//

	`Varlist'		clustervars
	`Varlist'		clustervars_original // Note: need to apply tokens()
}

end
