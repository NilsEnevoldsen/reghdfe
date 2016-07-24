cap pr drop Prepare
pr Prepare
* Save statistics on untransformed variables
	
* TSS of untransformed depvar(s)
	Inject depvar stages endogvars weight_exp has_intercept
	if (!`: list posof "first" in stages') loc endogvars
	local tmpweightexp = subinstr("`weight_exp'", "[pweight=", "[aweight=", 1)

	foreach var of varlist `depvar' `endogvars' {
		qui su `var' `tmpweightexp'
		local tss = r(Var)*(r(N)-1)
		if (!`has_intercept') local tss = `tss' + r(sum)^2 / (r(N))
		mata: asarray(REGHDFE.tss, "`var'") = `tss'
	}

* (optional) R2 of regression without FE, to build joint FTest for FEs
	Inject model vcetype base_varlist
	if ("`model'"=="ols" & inlist("`vcetype'", "unadjusted", "ols")) {
		qui _regress `base_varlist' `weight_exp', noheader notable
		mata: REGHDFE.r2c = `e(r2)'
	}
end
