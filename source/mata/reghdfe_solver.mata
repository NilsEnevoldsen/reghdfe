// REGHDFE solver
mata:
mata set matastrict on

class reghdfe_solver {
	`output'			out				// Values used to generate output table
	`options' 			opt				// Solver options from the cmd line
	`fixed_effects'		fes				// The G*1 vector of FE structures

	`Integer'			G				// Number of FEs
	`Integer'			C				// Number of cluster variables
	`Integer'			N				// Number of obs after map_precompute()
	`Variable'			w				// Contents of the weightvar
	`Varname'			panelvar
	`Varname'			timevar
	`Varlist'			sortedby		// Variables on which the dataset is sorted (if anything)
	
	// Optimization parameters

	`Integer'		poolsize 			// Partial-out in bunches of # vars (more is faster but uses more memory)
	`Real'			tolerance
	`Integer'		maxiterations
	`String'		transform			// Kaczmarz Cimmino Symmetric_kaczmarz (k c s)
	`String'		acceleration		// Acceleration method. None/No/Empty is none\
	`Integer'		accel_start			// Iteration where we start to accelerate // set it at 6? 2?3?
	
	// Specific to Aitken's acceleration
	`Integer'		accel_freq		
	`Integer'		stuck_threshold		// Call the improvement "slow" when it's less than e.g. 1%
	`Integer'		bad_loop_threshold	// If acceleration seems stuck X times in a row, pause it
	`Integer'		pause_length		// This is in terms of candidate accelerations, not iterations (i.e. x3)?

	// Temporary
	`Boolean'		storing_betas
	`Varname'		groupvar			// Name of the variable that will hold the mobility group
	`Varname'		grouptype			// Long, double, etc.
	`Varname'		grouplabel
	`Variable'		groupseries			// The actual data of the mobility group variable
	`Variable'		uid
	`Variable'		resid
	`Varname'		residname
	`Integer'		num_iters_last_run
	`Integer'		num_iters_max

	// Temporary storage for DoFs
	`Integer'		dof_M
	`Integer'		dof_M_due_to_nested
	`Integer'		dof_KminusM
	`Integer'		dof_N_hdfe_extended
	`Vector'		doflist_M
	`Vector'		doflist_M_is_exact
	`Vector'		doflist_M_is_nested
	`Vector'		dof_SubGs

	`String'		cache_hash			// Ensures that the mata obj matches the Stata transformed dataset
}

end

