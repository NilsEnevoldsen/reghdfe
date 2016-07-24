cap pr drop ViewMataOptions
pr ViewMataOptions

loc options depvar indepvars endogvars instruments select_if select_in savecache usecache save_any_fe save_all_fe keepvars timeit fast verbose estimator ivsuite ffirst original_absvars extended_absvars has_intercept keepsingletons noabsorb fe_format weight_var weight_type weight_exp clustervars clustervars_original summarize_stats summarize_quietly stages stages_opt stages_save suboptions notes groupvar vceoption vcetype vcesuite vceextra vce_is_hac num_clusters bw dkraay twicerobust kiefer kernel dofadjustments residuals diopts ///
	base_varlist base_absvars base_clustervars

di as text "{bf: Main Options:}"
foreach opt of local options {
	loc val
	cap mata: st_local("val", strofreal(REGHDFE.opt.`opt'))
	cap mata: st_local("val", REGHDFE.opt.`opt')
	if (inlist("`val'", "", "0")) continue
	di as text `"   `opt' {col 22} = {res}`val'{txt}"'
}
di

loc options panelvar timevar sortedby poolsize tolerance maxiterations transform acceleration
di as text "{bf: Solver Options:}"
foreach opt of local options {
	loc val
	cap mata: st_local("val", strofreal(REGHDFE.`opt'))
	cap mata: st_local("val", REGHDFE.`opt')
	if (inlist("`val'", "", "0")) continue
	di as text `"   `opt' {col 22} = {res}`val'{txt}"'
}
di

di as text "{bf: Absorbed Fixed Effects:}"
mata: st_local("G", strofreal(REGHDFE.G))
loc options varlabel ivars cvars has_intercept num_slopes target
forval g = 1/`G' {
	di as text "   {bf:#`g'}" _c
	foreach opt of local options {
		loc val
		cap mata: st_local("val", strofreal(REGHDFE.fes[`g'].`opt'))
		cap mata: st_local("val", REGHDFE.fes[`g'].`opt')
		if (inlist("`val'", "", "0")) continue
		di as text `"{col 7}`opt' {col 22} = {res}`val'{txt}"'
	}
	di
}

end
