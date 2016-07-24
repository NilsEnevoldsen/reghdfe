// REGHDFE solver options
mata:
mata set matastrict on

class reghdfe_opt {
	`String'		depvar				//
	`String'		indepvars			//
	`String'		endogvars			//
	`String'		instruments			//

	`String'		original_depvar
	`String'		original_indepvars
	`String'		original_endogvars
	`String'		original_instruments

	`String'		select_if			// If condition
	`String'		select_in			// In condition

	`Boolean'		savecache			//
	`Boolean'		usecache			//
	`Boolean'		save_all_fe			// Save all FEs (auto naming if needed)
	`Varlist'		keepvars			// Used with cache(save)
	
	`Boolean'		timeit				// Show elapsed time?
	`Boolean'		fast				// Faster; by removing features
	`Integer'		verbose			// Freq. of debug messages (0 to 4)

	`String'		estimator			// 2sls, gmm2s, etc (IV/GMM only)
	`String'		ivsuite				// ivregress/ivreg2
	`Boolean'		ffirst				// First-stage F tests (IV/GMM only)
	`String'		model				// ols, iv
	
	`String'		original_absvars	// 
	`String'		extended_absvars	//
	`Boolean'		save_any_fe			// Save at least 1 FE
	`Boolean'		has_intercept		// Do the FEs include an intercept?
	`Boolean'		keepsingletons		// Default to 0
	`Boolean'		noabsorb			// 1 if we only have a constant term
	`String'		fe_format			// Format of the depvar

	`String'		weight_var			// Weighting variable
	`String'		weight_type			// Weight type (pw, fw, etc)
	`String'		weight_exp			// "[weight_type=weight_var]"

	`Varlist'		clustervars
	`Varlist'		clustervars_original // Note: need to apply tokens()

	`String'		summarize_stats
	`Boolean'		summarize_quietly

	`String'		stages
	`String'		stages_opt
	`Boolean'		stages_save

	`String'		suboptions
	`String'		notes
	`Varname'		groupvar

	`String'		vceoption
	`String'		vcetype
	`String'		vcesuite
	`String'		vceextra
	`Boolean'		vce_is_hac
	`Integer'		num_clusters
	`Integer'		bw
	`Integer'		dkraay
	`Integer'		twicerobust
	`String'		kiefer
	`String'		kernel

	`String'		dofadjustments
	`String'		residuals
	`String'		diopts

	`String'		base_varlist
	`String'		base_absvars
	`String'		base_clustervars
}
end
