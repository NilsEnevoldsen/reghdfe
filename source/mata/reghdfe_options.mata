// Estimation options
mata:
mata set matastrict on

struct reghdfe_opt {
	`Boolean'		timeit, fast, ffirst, savecache, usecache, save_fe,
					has_intercept
	`String'		select_if, select_in
	`Varlist'		keepvars
	`String'		depvar, indepvars, endogvars, instruments
	`String'		fe_format, estimator, ivsuite
	`String'		weight_var, weight_type, weight_exp
	`String'		original_absvars, extended_absvars

}

end
