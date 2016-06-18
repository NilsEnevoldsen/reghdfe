capture program drop Inner
pr Inner, eclass
	Parse `0' // inject locals with c_local; create HDFE_S Mata structure
	if (`timeit') Tic, n(50)
	
	preserve  // move it where it was before..

* CREATE UID - allows attaching e(sample) and the FE estimates into the restored dataset
	if (!`fast') {
		tempvar uid
		GenerateUID `uid'
	}

* COMPACT - Expand time and factor variables, and drop unused variables and obs.
	foreach cat in depvar indepvars endogvars instruments {
		local original_`cat' "``cat''"
	}
	if (`timeit') Tic, n(53)
	Compact, basevars(`basevars') depvar(`depvar') indepvars(`indepvars') endogvars(`endogvars') instruments(`instruments') uid(`uid') timevar(`timevar') panelvar(`panelvar') weightvar(`weightvar') weighttype(`weighttype') absorb_keepvars(`absorb_keepvars') clustervars(`clustervars') if(`if') in(`in') verbose(`verbose') vceextra(`vceextra')
	// Injects locals: depvar indepvars endogvars instruments expandedvars
	if (`timeit') Toc, n(53) msg(compact)

* PRECOMPUTE MATA OBJECTS (means, counts, etc.)
	if (`timeit') Tic, n(54)
	mata: map_init_keepvars(HDFE_S, "`expandedvars' `uid'") 	// Non-essential vars will be deleted (e.g. interactions of a clustervar)
	mata: map_precompute(HDFE_S)
	if (`timeit') Toc, n(54) msg(map_precompute())
	
	* Replace vceoption with the correct cluster names (e.g. if it's a FE or a new variable)
	if (`num_clusters'>0) {
		assert "`r(updated_clustervars)'"!=""
		local vceoption : subinstr local vceoption "<CLUSTERVARS>" "`r(updated_clustervars)'"
	}

* MEMORY REPORT
	Debug, level(2) msg("(dataset compacted: observations " as result "`raw_n' -> `c(N)'" as text " ; variables " as result "`raw_k' -> `c(k)'" as text ")")
	qui de, simple
	local new_mem = string(r(width) * r(N) / 2^20, "%6.2f")
	Debug, level(2) msg("(dataset compacted, c(memory): " as result "`old_mem'" as text "M -> " as result "`new_mem'" as text "M)")
	if (`verbose'>3) {
		di as text "(memory usage including mata:)"
		memory
		di as text ""
	}

* PREPARE - Compute untransformed tss, R2 of eqn w/out FEs
if (`timeit') Tic, n(55)
	Prepare, weightexp(`weightexp') depvar(`depvar') stages(`stages') model(`model') expandedvars(`expandedvars') vcetype(`vcetype') endogvars(`endogvars') has_intercept(`has_intercept')
	* Injects tss, tss_`endogvar' (with stages), and r2c
	if (`timeit') Toc, n(55) msg(prepare)

* STORE UID - Used to add variables to original dataset: e(sample), mobility group, and FE estimates
	if (!`fast') mata: store_uid(HDFE_S, "`uid'")
	if (`fast') Debug, msg("(option {opt fast} specified; will not save e(sample))")

* BACKUP UNTRANSFORMED VARIABLES - If we are saving the FEs, we need to backup the untransformed variables
	if (`will_save_fe') {
		if (`timeit') Tic, n(56)
		tempfile untransformed
		qui save "`untransformed'"
		if (`timeit') Toc, n(56) msg(save untransformed tempfile)
	}

* COMPUTE e(stats) - Summary statistics for the all the regression variables
	if ("`stats'"!="") {
		if (`timeit') Tic, n(57)
		tempname statsmatrix
		Stats `expandedvars', weightexp(`weightexp') stats(`stats') statsmatrix(`statsmatrix')
		if (`timeit') Toc, n(57) msg(stats matrix)
	}

* COMPUTE DOF
	if (`timeit') Tic, n(62)
	mata: map_estimate_dof(HDFE_S, "`dofadjustments'", "`groupvar'") // requires the IDs
	if (`timeit') Toc, n(62) msg(estimate dof)
	assert e(df_a)<. // estimate_dof() only sets e(df_a); map_ereturn_dof() is for setting everything aferwards
	local kk = e(df_a) // we need this for the regression step
	
* DROP FE IDs - Except if they are also a clustervar or we are saving their respecting alphas
	if (`timeit') Tic, n(64)
	mata: drop_ids(HDFE_S)
	if (`timeit') Toc, n(64) msg(drop ids)

* MAP_SOLVE() - WITHIN TRANFORMATION (note: overwrites variables)
	if (`timeit') Tic, n(60)
	qui ds `expandedvars'
	local NUM_VARS : word count `r(varlist)'
	Debug, msg("(computing residuals for `NUM_VARS' variables)")
	mata: map_solve(HDFE_S, "`expandedvars'")
	if (`timeit') Toc, n(60) msg(map_solve())

* STAGES SETUP - Deal with different stages
	assert "`stages'"!=""
	if ("`stages'"!="none") {
		Debug, level(1) msg(_n "{title:Stages to run}: " as result "`stages'")
		* Need to backup some locals
		local backuplist residuals groupvar fast will_save_fe depvar indepvars endogvars instruments original_depvar tss suboptions
		foreach loc of local backuplist {
			local backup_`loc' ``loc''
		}

		local num_stages : word count `stages'
		local last_stage : word `num_stages' of `stages'
		assert "`last_stage'"=="iv"
	}

* STAGES LOOPS
foreach stage of local stages {
Assert inlist("`stage'", "none", "iv", "first", "ols", "reduced", "acid")
if ("`stage'"=="first") {
	local lhs_endogvars "`backup_endogvars'"
	local i_endogvar 0
}
else {
	local lhs_endogvars "<none>"
	local i_endogvar
}

foreach lhs_endogvar of local lhs_endogvars {

	if ("`stage'"!="none") {
		* Start with backup values
		foreach loc of local backuplist {
			local `loc' `backup_`loc''
		}

		if ("`stage'"=="ols") {
			local indepvars `endogvars' `indepvars'
		}
		else if ("`stage'"=="reduced") {
			local indepvars `instruments' `indepvars'
		}
		else if ("`stage'"=="acid") {
			local indepvars `endogvars' `instruments' `indepvars'
		}
		else if ("`stage'"=="first") {
			local ++i_endogvar
			local tss = `tss_`lhs_endogvar''
			assert `tss'<.
			local depvar `lhs_endogvar'
			local indepvars `instruments' `indepvars'
			local original_depvar : char `depvar'[name]
		}

		if ("`stage'"!="iv") {
			local fast 1
			local will_save_fe 0
			local endogvars
			local instruments
			local groupvar
			local residuals
			local suboptions `stage_suboptions'
		}
	}

* REGRESS - Call appropiate wrapper (regress, avar, mwc for ols; ivreg2, ivregress for iv)
	ereturn clear
	if ("`stage'"=="none") Debug, level(2) msg("(running regresion: `model'.`ivsuite')")
	local wrapper "Wrapper_`subcmd'" // regress ivreg2 ivregress
	if ("`subcmd'"=="regress" & "`vcesuite'"=="avar") local wrapper "Wrapper_avar"
	if ("`subcmd'"=="regress" & "`vcesuite'"=="mwc") local wrapper "Wrapper_mwc"
	if (!inlist("`stage'","none", "iv")) {
		if ("`vcesuite'"=="default") local wrapper Wrapper_regress
		if ("`vcesuite'"!="default") local wrapper Wrapper_`vcesuite'
	}
	local opt_list
	local opts ///
		depvar indepvars endogvars instruments ///
		vceoption vcetype ///
		kk suboptions ffirst weightexp ///
		estimator twicerobust /// Whether to run or not two-step gmm
		num_clusters clustervars // Used to fix e() of ivreg2 first stages
	foreach opt of local opts {
		local opt_list `opt_list' `opt'(``opt'')
	}
	Debug, level(3) msg(_n "call to wrapper:" _n as result "`wrapper', `opt_list'")
	if (`timeit') Tic, n(66)
	`wrapper', `opt_list'
	if (`timeit') Toc, n(66) msg(regression)

* COMPUTE AND STORE RESIDS (based on SaveFE.ado)
	local drop_resid_vector
	if ("`residuals'"!="") {
		local drop_resid_vector drop_resid_vector(0)
		local subpredict = e(predict)
		local score = cond("`model'"=="ols", "score", "resid")
		if e(df_m)>0 {
			`subpredict' double `residuals', `score' // equation: y = xb + d + e, we recovered "e"
		}
		else {
			gen double `residuals' = `depvar'
		}
		mata: store_resid(HDFE_S, "`residuals'")
	}

* SAVE FE - This loads back the untransformed dataset!
	if (`will_save_fe') {
		if (`timeit') Tic, n(68)
		local subpredict = e(predict) // used to recover the FEs
		SaveFE, model(`model') depvar(`depvar') untransformed(`untransformed') weightexp(`weightexp') has_intercept(`has_intercept') subpredict(`subpredict') `drop_resid_vector'
		if (`timeit') Toc, n(68) msg(save fes in mata)
	}

* FIX VARNAMES - Replace tempnames in the coefs table (run AFTER regress and BEFORE restore)
	* (e.g. __00001 -> L.somevar)
	tempname b
	matrix `b' = e(b)
	local backup_colnames : colnames `b'
	FixVarnames `backup_colnames'
	local newnames "`r(newnames)'"
	matrix colnames `b' = `newnames'
	// ereturn repost b=`b', rename // I cannot run repost before preserve. Why? Who knows... (running it in Post.ado)
	ereturn local depvar = "`original_depvar'" // Run after SaveFE

* (optional) Restore
	if inlist("`stage'","none", "iv") {
		if (`timeit') Tic, n(70)
		restore
		Debug, level(2) newline
		Debug, level(2) msg("(dataset restored)")
		// TODO: Format alphas
		if (`timeit') Toc, n(70) msg(restore)
	}

* SAVE RESIDS (after restore)
	if ("`residuals'"!="") mata: resid2dta(HDFE_S, 1, 1)

* (optional) Save mobility groups
	if ("`groupvar'"!="") mata: groupvar2dta(HDFE_S)

* (optional) Save alphas (fixed effect estimates)
	if (`will_save_fe') {
		if (`timeit') Tic, n(74)
		mata: alphas2dta(HDFE_S)
		if (`timeit') Toc, n(74) msg(save fes in dta)
	}

* (optional) Add e(sample)
	if (!`fast') {
		if (`timeit') Tic, n(76)
		tempvar sample
		mata: esample2dta(HDFE_S, "`sample'")
		qui replace `sample' = 0 if `sample'==.
		la var `sample' "[HDFE Sample]"
		ereturn repost , esample(`sample')
		mata: drop_uid(HDFE_S)
		if (`timeit') Toc, n(76) msg(add e(sample))
	}

* POST ERETURN - Add e(...) (besides e(sample) and those added by the wrappers)	
	local opt_list
	local opts dofadjustments subpredict model stage stages subcmd cmdline vceoption equation_d original_absvars extended_absvars vcetype vcesuite tss r2c savestages diopts weightvar estimator dkraay by level num_clusters clustervars timevar backup_original_depvar original_indepvars original_endogvars original_instruments has_intercept
	foreach opt of local opts {
		local opt_list `opt_list' `opt'(``opt'')
	}
	if (`timeit') Tic, n(78)
	Post, `opt_list' coefnames(`b')
	if (`timeit') Toc, n(78) msg(post)

* REPLAY - Show the regression table
	Replay
	
* ATTACH - Add e(stats) and e(notes)
	Attach, notes(`notes') statsmatrix(`statsmatrix') summarize_quietly(`summarize_quietly')

* Store stage result
	if (!inlist("`stage'","none", "iv") & `savestages') est store reghdfe_`stage'`i_endogvar', nocopy

} // lhs_endogvar
} // stage

* CLEANUP
	mata: mata drop HDFE_S // cleanup
	if (`timeit') Toc, n(50) msg([TOTAL])
end
