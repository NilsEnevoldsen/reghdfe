capture program drop mark_obs_and_vars
pr mark_obs_and_vars, rclass
	syntax varlist(fv ts) [if] [in] [fw aw pw iw], ///
		MARK() [CLustervars(varlist fv ts)]
	
	fvrevar `varlist' `clustervars' `weightvar', list
	local keepvars `r(varlist)'
	* create mark variable based on weights (>0), if in, and keepvars not being missing or empty (but can be string)

	return local varlist `keepvars'
end
