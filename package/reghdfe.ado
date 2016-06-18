*! reghdfe 3.3.22 27may2016 (dev)
*! Sergio Correia (sergio.correia@gmail.com)
*! http://scorreia.com/software/reghdfe/

capture program drop reghdfe
program define reghdfe
	version `=clip(c(version), 11.2, 14.1)'

* Intercept -version-
	cap syntax, version [*]
	if !c(rc) {
		Version, `options'
		exit
	}

* Intercept -cache(save)-
	cap syntax anything(everything) [fw aw pw/], [*] CACHE(string)
	if (strpos("`cache'", "save")==1) {
		cap noi InnerSaveCache `0'
		if (c(rc)) {
			local rc = c(rc)
			Cleanup
			exit `rc'
		}
		exit
	}

* Intercept -cache(use)-
	cap syntax anything(everything) [fw aw pw/], [*] CACHE(string)
	if ("`cache'"=="use") {
		InnerUseCache `0'
		exit
	}

* Intercept -cache(clear)-
	cap syntax, CACHE(string)
	if ("`cache'"=="clear") {
		Cleanup
		exit
	}

* Intercept replays; must be at the end
	if replay() {
		if (`"`e(cmd)'"'!="reghdfe") error 301
		if ("`0'"=="") local comma ","
		Replay `comma' `0' stored // also replays stored regressions (first stages, reduced, etc.)
		exit
	}

* Finally, call Inner if not intercepted before
	local is_cache : char _dta[reghdfe_cache]
	Assert ("`is_cache'"!="1"), msg("reghdfe error: data transformed with -savecache- requires option -usecache-")
	Cleanup, estimates
	cap noi Inner `0'
	if (c(rc)) {
		local rc = c(rc)
		Cleanup, estimates
		exit `rc'
	}
end

// -------------------------------------------------------------------------------------------------

// -------------------------------------------------------------
// Simple assertions
// -------------------------------------------------------------

program define Assert
    syntax anything(everything equalok) [, MSG(string asis) RC(integer 198)]
    if !(`anything') {
        di as error `msg'
        exit `rc'
    }
end


// -------------------------------------------------------------
// Simple debugging
// -------------------------------------------------------------

program define Debug

	syntax, [MSG(string asis) Level(integer 1) NEWline COLOR(string)] [tic(integer 0) toc(integer 0)]
	
	mata: verbose2local(HDFE_S, "VERBOSE")
	assert "`VERBOSE'"!=""
	assert inrange(`VERBOSE',0, 5)
	
	assert inrange(`level',0, 5)
	assert (`tic'>0) + (`toc'>0)<=1

	if ("`color'"=="") local color text
	assert inlist("`color'", "text", "res", "result", "error", "input")

	if (`VERBOSE'>=`level') {

		if (`tic'>0) {
			timer clear `tic'
			timer on `tic'
		}
		if (`toc'>0) {
			timer off `toc'
			qui timer list `toc'
			local time = r(t`toc')
			if (`time'<10) local time = string(`time'*1000, "%tcss.ss!s")
			else if (`time'<60) local time = string(`time'*1000, "%tcss!s")
			else if (`time'<3600) local time = string(`time'*1000, "%tc+mm!m! SS!s")
			else if (`time'<24*3600) local time = string(`time'*1000, "%tc+hH!h! mm!m! SS!s")
			timer clear `toc'
			local time `" as result " `time'""'
		}

		if (`"`msg'"'!="") di as `color' `msg'`time'
		if ("`newline'"!="") di
	}
end


// -------------------------------------------------------------
// Report HDFE/REGHDFE version
// -------------------------------------------------------------

program define Version, eclass
    syntax , [STABLE DEV DEPENDENCIES]
    local all_dependencies ivreg2 avar tuples group3hdfe

    if ("`stable'" != "") {
        ado uninstall reghdfe
        ssc install reghdfe
        pr drop _all
        exit
    }

    if ("`dev'" != "") {
        ado uninstall reghdfe
        net install reghdfe, from("http://scorreia.com/software/reghdfe")
        pr drop _all
        exit
    }


    if ("`dependencies'" != "") {
        foreach dep of local all_dependencies {
            cap which `dep'
            if (_rc) ssc install `dep'
        }
        exit
    }

    local version "3.3.22 27may2016 (dev)"
    ereturn clear
    di as text "`version'"
    ereturn local version "`version'"

    di as text _n "Dependencies installed?"
    foreach dep of local all_dependencies {
    	cap findfile `dep'.ado
    	if (_rc) {
    		di as text "{lalign 20: - `dep'}" as result " no" ///
             as text " {stata ssc install `dep':(click to install)}"
    	}
    	else {
    		di as text "{lalign 20: - `dep'}" as result "yes"
    	}
    }

    di as text _n "Updates:"
    di as text " - reghdfe:{stata reghdfe, version stable: update to latest stable version (from ssc)}"
    di as text " - reghdfe:{stata reghdfe, version dev: update to latest development version (from github)}"
    di as text " - dependencies:{stata reghdfe, version dependencies: install all}"
    di as text " - dependencies:{stata adoupdate update `all_dependencies', update: update all if installed}"

end

program define Tic
syntax, n(integer)
	timer clear `n'
	timer on `n'
end

program define Toc
syntax, n(integer) msg(string)
	timer off `n'
	qui timer list `n'
	di as text "[timer]{tab}" as result %8.3f `r(t`n')' as text "{col 20}`msg'{col 77}`n'" 
	timer clear `n'
end

program define Cleanup
	syntax , [estimates]
	
	cap mata: mata drop HDFE_S
	cap mata: mata drop varlist_cache
	cap mata: mata drop tss_cache
	cap global updated_clustervars
	cap matrix drop reghdfe_statsmatrix

	if ("`estimates'" != "") {
		ereturn clear // Clear previous results; drop e(sample)
		cap estimates drop reghdfe_*
	}
end

program define Inner, eclass
	preserve
	Parse `0' // inject locals with c_local; create HDFE_S Mata structure
	if (`timeit') Tic, n(50)

* CREATE UID - allows attaching e(sample) and the FE estimates into the restored dataset
	if (!`fast') {
		tempvar uid
		GenUID `uid'
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

	
// -------------------------------------------------------------
// Parsing and basic sanity checks for REGHDFE.ado
// -------------------------------------------------------------

program define Parse

* Remove extra spacing from cmdline (just for aesthetics)
	mata: st_local("cmdline", stritrim(`"reghdfe `0'"') )

* Parse the broad syntax (also see map_init(), ParseAbsvars.ado, ParseVCE.ado, etc.)
	syntax anything(id="varlist" name=0 equalok) [if] [in] [aw pw fw/] , ///
		/// Model ///
		[Absorb(string) NOAbsorb] ///
		[ ///
		RESiduals(name) ///
		SUBOPTions(string) /// Options to be passed to the estimation command (e.g . to regress)
		/// Standard Errors ///
		VCE(string) CLuster(string) /// cluster() is an undocumented alternative to vce(cluster ...)
		/// IV/2SLS/GMM ///
		ESTimator(string) /// 2SLS GMM2s CUE LIML
		STAGEs(string) /// besides iv (always on), first reduced ols acid (and all)
		FFirst /// Save first-stage stats (only with ivreg2)
		IVsuite(string) /// ivreg2 or ivregress
		/// Diagnostic ///
		Verbose(string) ///
		TIMEit ///
		/// Optimization /// Defaults are handled within Mata		
		TOLerance(string) ///
		MAXITerations(string) ///
		POOLsize(string) /// Process variables in batches of #
		ACCELeration(string) ///
		TRAnsform(string) ///
		/// Speedup Tricks ///
		CACHE(string) ///
		FAST ///
		/// Degrees-of-freedom Adjustments ///
		DOFadjustments(string) ///
		GROUPVar(name) /// Variable that will contain the first connected group between FEs
		/// Undocumented ///
		KEEPSINgletons /// (UNDOCUMENTED) Will keep singletons
		NOTES(string) /// NOTES(key=value ...), will be stored on e()
		] [*] // Captures i) display options, ii) SUmmarize|SUmmarize(...)

	local allkeys cmdline if in timeit

* Do this early
	local timeit = "`timeit'"!=""
	local fast = "`fast'"!=""
	local ffirst = "`ffirst'"!=""
	
	if ("`cluster'"!="") {
		Assert ("`vce'"==""), msg("cannot specify both cluster() and vce()")
		local vce cluster `cluster'
		local cluster // Set it to empty to avoid bugs in subsequent lines
	}

* Also early
	ParseCache, cache(`cache') ifin(`if'`in') absorb(`absorb') vce(`vce')
	local keys savecache keepvars usecache
	foreach key of local keys {
		local `key' "`s(`key')'"
	}
	local allkeys `allkeys' `keys'

* Parse varlist: depvar indepvars (endogvars = iv_vars)
	ParseIV `0', estimator(`estimator') ivsuite(`ivsuite')
	local keys subcmd model ivsuite estimator depvar indepvars endogvars instruments fe_format basevars
	foreach key of local keys {
		local `key' "`s(`key')'"
	}
	local allkeys `allkeys' `keys'

* Weights
	if ("`weight'"!="") {
		local weightvar `exp'
		local weighttype `weight'
		local weightexp [`weight'=`weightvar']
		unab weightvar : `weightvar', min(1) max(1) // simple weights only

		* Check that weights are correct (e.g. with fweight they need to be integers)
		local num_type = cond("`weight'"=="fweight", "integers", "reals")
		local basenote "{txt}weight {res}`weightvar'{txt} can only contain strictly positive `num_type', but"
		local if_and "if"
		if ("`if'"!="") local if_and "`if' &"
		qui cou `if_and' `weightvar'<0
		Assert (`r(N)'==0), msg("`basenote' `r(N)' negative values were found!")  rc(402)
		qui cou `if_and' `weightvar'==0
		if (`r(N)'>0) di as text "`basenote' `r(N)' zero values were found (will be dropped)"
		qui cou `if_and' `weightvar'>=.
		if (`r(N)'>0) di as text "`basenote' `r(N)' missing values were found (will be dropped)"
		if ("`weight'"=="fweight") {
			qui cou `if_and' mod(`weightvar',1) & `weightvar'<.
			Assert (`r(N)'==0), msg("`basenote' `r(N)' non-integer values were found!" "{err} Stopping execution") rc(401)
		}
	}
	local allkeys `allkeys' weightvar weighttype weightexp

* Parse Absvars and optimization options
if (!`usecache') {
	Assert ("`absorb'"!="") + ("`noabsorb'"!="") > 0, ///
		msg("options {bf:absorb()} or {bf:noabsorb} required")
	Assert ("`absorb'"!="") + ("`noabsorb'"!="") < 2, ///
		msg("cannot have both {bf:absorb()} and {bf:noabsorb} options")
	if ("`noabsorb'" != "") {
		gen byte _constant = 1
		local absorb _constant
	}
	ParseAbsvars `absorb' // Stores results in r()
		if (inlist("`verbose'", "4", "5")) return list
		local absorb_keepvars `r(all_ivars)' `r(all_cvars)'
		local N_hdfe `r(G)'
		local has_intercept = `r(has_intercept)'
		assert inlist(`has_intercept', 0, 1)

	mata: HDFE_S = map_init() // Reads results from r()
		local will_save_fe = `r(will_save_fe)' // Returned from map_init()
		local original_absvars "`r(original_absvars)'"
		local extended_absvars "`r(extended_absvars)'"
		local equation_d "`r(equation_d)'"
}
else {
	local will_save_fe 0
	local original_absvars : char _dta[original_absvars]
	local extended_absvars : char _dta[extended_absvars]
	local equation_d
	local N_hdfe : char _dta[N_hdfe]
	local has_intercept : char _dta[has_intercept]
}
	local allkeys `allkeys' absorb_keepvars N_hdfe will_save_fe original_absvars extended_absvars equation_d has_intercept

	* Tell Mata what weightvar we have
	if ("`weightvar'"!="" & !`usecache') mata: map_init_weights(HDFE_S, "`weightvar'", "`weighttype'")

	* Time/panel variables (need to give them to Mata)
	local panelvar `_dta[_TSpanel]'
	local timevar `_dta[_TStvar]'
	if ("`panelvar'"!="") {
		cap conf var `panelvar'
		if (c(rc)==111) local panelvar // if the var doesn't exist, set it empty
	}
	if ("`timevar'"!="") {
		cap conf var `timevar'
		if (c(rc)==111) local timevar // if the var doesn't exist, set it empty
	}

	* Parse optimization options (pass them to map_init_*)
	* String options
	local optlist transform acceleration panelvar timevar
	foreach opt of local optlist {
		if ("``opt''"!="" & !`usecache') mata: map_init_`opt'(HDFE_S, "``opt''")
	}
	local allkeys `allkeys' `optlist'

	* This allows changing the groupvar name with -usecache-
	if ("`groupvar'"!="") mata: map_init_groupvar(HDFE_S, "`groupvar'")

	* Numeric options
	local keepsingletons = ("`keepsingletons'"!="")
	local optlist poolsize verbose tolerance maxiterations keepsingletons timeit
	foreach opt of local optlist {
		if ( "``opt''"!="" & (!`usecache' | "`opt'"=="verbose") ) mata: map_init_`opt'(HDFE_S, ``opt'')
	}
	local allkeys `allkeys' `optlist'

	* Return back default value of -verbose-
	mata: verbose2local(HDFE_S, "verbose")
	local allkeys `allkeys' verbose

* Stages (before vce)
	ParseStages, stages(`stages') model(`model')
	local stages "`s(stages)'"
	local stage_suboptions "`s(stage_suboptions)'"
	local savestages = `s(savestages)'
	local allkeys `allkeys' stages stage_suboptions savestages

* Parse VCE options (after stages)
	local keys vceoption vcetype vcesuite vceextra num_clusters clustervars bw kernel dkraay kiefer twicerobust
	if (!`usecache') {
		mata: st_local("hascomma", strofreal(strpos("`vce'", ","))) // is there a commma already in `vce'?
		local vcetmp `vce'
		if (!`hascomma') local vcetmp `vce' ,
		ParseVCE `vcetmp' weighttype(`weighttype') ivsuite(`ivsuite') model(`model')
		foreach key of local keys {
			local `key' "`s(`key')'"
		}
	}
	else {
		foreach key of local keys {
			local `key' : char _dta[`key']
		}
	}

	local allkeys `allkeys' `keys'

* Parse FFIRST (save first stage statistics)
	local allkeys `allkeys' ffirst
	if (`ffirst') Assert "`model'"!="ols", msg("ols does not support {cmd}ffirst")
	if (`ffirst') Assert "`ivsuite'"=="ivreg2", msg("option {cmd}ffirst{err} requires ivreg2")
	
* Update Mata
	if ("`clustervars'"!="" & !`usecache') mata: map_init_clustervars(HDFE_S, "`clustervars'")
	if ("`vceextra'"!="" & !`usecache') mata: map_init_vce_is_hac(HDFE_S, 1)

* DoF Adjustments
	if ("`dofadjustments'"=="") local dofadjustments all
	ParseDOF , `dofadjustments'
	local dofadjustments "`s(dofadjustments)'"
	* Mobility groups
	if ("`groupvar'"!="") conf new var `groupvar'
	local allkeys `allkeys' dofadjustments groupvar

* Parse residuals
	if ("`residuals'"!="") {
		Assert !`will_save_fe', msg("option residuals() is mutually exclusive with saving fixed effects")
		Assert !`savecache', msg("option residuals() is mutually exclusive with -savecache-")
		conf new var `residuals'
		local allkeys `allkeys' residuals
	}

* Parse summarize option: [summarize | summarize( stats... [,QUIetly])]
	* Note: ParseImplicit deals with "implicit" options and fills their default values
	local default_stats mean min max
	ParseImplicit, opt(SUmmarize) default(`default_stats') input(`options') syntax([namelist(name=stats)] , [QUIetly]) inject(stats quietly)
	local summarize_quietly = ("`quietly'"!="")
	if ("`stats'"=="" & "`quietly'"!="") local stats `default_stats'
	local allkeys `allkeys' stats summarize_quietly

* Parse speedups
	if (`fast' & ("`groupvar'"!="" | `will_save_fe'==1 | "`residuals'"!="")) {
		di as error "(warning: option -fast- disabled; not allowed when saving variables: saving fixed effects, mobility groups, residuals)"
		local fast 0
	}
	local allkeys `allkeys' fast level

* Nested
	local nested = cond("`nested'"!="", 1, 0) // 1=Yes
	if (`nested' & !("`model'"=="ols" & "`vcetype'"=="unadjusted") ) {
		di as error "-nested- not implemented currently"
		Debug, level(0) msg("(option nested ignored, only works with OLS and conventional/unadjusted VCE)") color("error")
	}
	local allkeys `allkeys' nested

* Sanity checks on speedups
* With -savecache-, this adds chars (modifies the dta!) so put it close to the end
	if (`savecache') {
		* Savecache "requires" a previous preserve, so we can directly modify the dataset
		Assert "`endogvars'`instruments'"=="", msg("cache(save) option requires a normal varlist, not an iv varlist")
		char _dta[reghdfe_cache] 1
		local chars absorb N_hdfe has_intercept original_absvars extended_absvars vce vceoption vcetype vcesuite vceextra num_clusters clustervars bw kernel dkraay kiefer twicerobust
		foreach char of local  chars {
			char _dta[`char'] ``char''	
		}
	}

* Parse Coef Table Options (do this last!)
	_get_diopts diopts options, `options' // store in `diopts', and the rest back to `options'
	Assert `"`options'"'=="", msg(`"invalid options: `options'"')
	if ("`hascons'`tsscons'"!="") di in ye "(option `hascons'`tsscons' ignored)"
	local allkeys `allkeys' diopts

* Other keys:
	local allkeys `allkeys' suboptions notes
	// Missing keys: check

* Return values
	Debug, level(3) newline
	Debug, level(3) msg("{title:Parsed options:}")
	foreach key of local allkeys {
		if (`"``key''"'!="") Debug, level(3) msg("  `key' = " as result `"``key''"')
		c_local `key' `"``key''"' // Inject values into caller (reghdfe.ado)
	}

end

program define ParseCache, sclass
	syntax, [CACHE(string)] [IFIN(string) ABSORB(string) VCE(string)] 
	if ("`cache'"!="") {
		local 0 `cache'
		syntax name(name=opt id="cache option"), [KEEPvars(varlist)]
		Assert inlist("`opt'", "save", "use"), msg("invalid cache option {cmd`opt'}") // -clear- is also a valid option but intercepted earlier
	}

	local savecache = ("`opt'"=="save")
	local usecache = ("`opt'"=="use")
	local is_cache : char _dta[reghdfe_cache]

	* Sanity checks on usecache
	if (`usecache') {
		local cache_obs : char _dta[cache_obs]
		local cache_absorb : char _dta[absorb]
		local cache_vce : char _dta[vce]

		Assert "`is_cache'"=="1" , msg("cache(use) requires a previous cache(save) operation")
		Assert `cache_obs'==`c(N)', msg("dataset cannot change after cache(save)")
		Assert "`cache_absorb'"=="`absorb'", msg("cached dataset has different absorb()")
		Assert "`ifin'"=="", msg("cannot use if/in with cache(use); data has already been transformed")
		Assert "`cache_vce'"=="`vce'", msg("cached dataset has a different vce()")
	}
	else {
		Assert "`is_cache'"!="1", msg("reghdfe error: data transformed with cache(save) requires cache(use)")
	}
	
	if (!`savecache') Assert "`keepvars'"=="", msg("reghdfe error: {cmd:keepvars()} suboption requires {cmd:cache(save)}")

	local keys savecache keepvars usecache
	foreach key of local keys {
		sreturn local `key' ``key''
	}
end

program define ParseIV, sclass
	syntax anything(id="varlist" name=0 equalok), ///
		estimator(string) ivsuite(string) ]

	* Parses varlist: depvar indepvars [(endogvars = instruments)]
		* depvar: dependent variable
		* indepvars: included exogenous regressors
		* endogvars: included endogenous regressors
		* instruments: excluded exogenous regressors

	* Model: OLS or IV-type?
	local model ols
	foreach _ of local 0 {
		if (substr(`"`_'"', 1, 1)=="(") {
			local model iv
			continue, break
		}
	}

	* IV Suite
	if ("`model'"=="iv") {
		if ("`ivsuite'"=="") local ivsuite ivreg2 // Set default
		Assert inlist("`ivsuite'","ivreg2","ivregress") , ///
			msg("error: wrong IV routine (`ivsuite'), valid options are -ivreg2- and -ivregress-")
		cap findfile `ivsuite'.ado
		Assert !_rc , msg("error: -`ivsuite'- not installed, please run {stata ssc install `ivsuite'} or change the option 	-ivsuite-")
		local subcmd `ivsuite'
	}
	else {
		local subcmd regress
	}

	* Estimator
	if ("`estimator'"=="" & "`model'"=="iv") local estimator 2sls // Set default
	if ("`estimator'"!="") {
		Assert "`model'"=="iv", ///
			msg("reghdfe error: estimator() requires an instrumental-variable regression")
		if (substr("`estimator'", 1, 3)=="gmm") local estimator gmm2s
		Assert inlist("`estimator'", "2sls", "gmm2s", "liml", "cue"), ///
			msg("reghdfe error: invalid estimator `estimator'")
		if ("`estimator'"=="cue") Assert "`ivsuite'"=="ivreg2", ///
			msg("reghdfe error: estimator `estimator' only available with the ivreg2 command, not ivregress")
		if ("`estimator'"=="cue") di as text "(WARNING: -cue- estimator is not exact, see help file)"
	}

	* For this, _iv_parse would have been useful, but I don't want to do factor expansions when parsing
	if ("`model'"=="iv") {

		* get part before parentheses
		local wrongparens 1
		while (`wrongparens') {
			gettoken tmp 0 : 0 ,p("(")
			local left `left'`tmp'
			* Avoid matching the parens of e.g. L(-1/2) and L.(var1 var2)
			* Using Mata to avoid regexm() and trim() space limitations
			mata: st_local("tmp1", subinstr(`"`0'"', " ", "") ) // wrong parens if ( and then a number
			mata: st_local("tmp2", substr(strtrim(`"`left'"'), -1) ) // wrong parens if dot
			local wrongparens = regexm(`"`tmp1'"', "^\([0-9-]") | (`"`tmp2'"'==".")
			if (`wrongparens') {
				gettoken tmp 0 : 0 ,p(")")
				local left `left'`tmp'
			}
		}

		* get part in parentheses
		gettoken right 0 : 0 ,bind match(parens)
		Assert trim(`"`0'"')=="" , msg("error: remaining argument: `0'")

		* now parse part in parentheses
		gettoken endogvars instruments : right ,p("=")
		gettoken equalsign instruments : instruments ,p("=")

		fvstrip `endogvars'

		Assert "`endogvars'"!="", msg("iv: endogvars required")


		local 0 `endogvars'
		syntax varlist(fv ts numeric)
		local endogvars `varlist'

		Assert "`instruments'"!="", msg("iv: instruments required")
		local 0 `instruments'
		syntax varlist(fv ts numeric)
		local instruments `varlist'
		
		local 0 `left' // So OLS part can handle it
	}

* OLS varlist
	syntax varlist(fv ts numeric)
	gettoken depvar indepvars : varlist
	_fv_check_depvar `depvar'

* Extract format of depvar so we can format FEs like this
	fvrevar `depvar', list
	local fe_format : format `r(varlist)' // The format of the FEs that will be saved

* Variables shouldn't be repeated
* This is not perfect (e.g. doesn't deal with "x1-x10") but still helpful
	local allvars `depvar' `indepvars' `endogvars' `instruments'
	local dupvars : list dups allvars
	Assert "`dupvars'"=="", msg("error: there are repeated variables: <`dupvars'>")

* Get base variables of time and factor variables (e.g. i.foo L(1/3).bar -> foo bar)
	foreach vars in depvar indepvars endogvars instruments {
		if ("``vars''"!="") {
			fvrevar ``vars'' , list
			local basevars `basevars' `r(varlist)'
		}
	}

	local keys subcmd model ivsuite estimator depvar indepvars endogvars instruments fe_format ///
		basevars
	foreach key of local keys {
		sreturn local `key' ``key''
	}
end 

program define ParseStages, sclass
	syntax, model(string) [stages(string)] // model can't be blank at this point!
	local 0 `stages'
	syntax [namelist(name=stages)], [noSAVE] [*]
	
	if ("`stages'"=="") local stages none
	if ("`stages'"=="all") local stages iv first ols reduced acid

	if ("`stages'"!="none") {
		Assert "`model'"!="ols", msg("{cmd:stages(`stages')} not allowed with ols")
		local special iv none
		local valid_stages first ols reduced acid
		local stages : list stages - special
		local wrong_stages : list stages - valid_stages
		Assert "`wrong_stages'"=="", msg("Error, invalid stages(): `wrong_stages'")
		* The "iv" stage will be always on for IV-type regressions
		local stages `stages' iv // put it last so it does the restore
	}

	sreturn local stages `stages'
	sreturn local stage_suboptions `options'
	sreturn local savestages = ("`save'"!="nosave")
end

program define ParseVCE, sclass
	* Note: bw=1 *usually* means just do HC instead of HAC
	* BUGBUG: It is not correct to ignore the case with "bw(1) kernel(Truncated)"
	* but it's too messy to add -if-s everywhere just for this rare case (see also Mark Schaffer's email)

	syntax 	[anything(id="VCE type")] , ///
			[bw(integer 1) KERnel(string) dkraay(integer 1) kiefer] ///
			[suite(string) TWICErobust] ///
			[weighttype(string)] ///
			model(string) ///
			[ivsuite(string)]

	Assert `bw'>0, msg("VCE bandwidth must be a positive integer")
	gettoken vcetype clustervars : anything
	* Expand variable abbreviations; but this adds unwanted i. prefixes
	if ("`clustervars'"!="") {
		fvunab clustervars : `clustervars'
		local clustervars : subinstr local clustervars "i." "", all
	}

	* vcetype abbreviations:
	if (substr("`vcetype'",1,3)=="ols") local vcetype unadjusted
	if (substr("`vcetype'",1,2)=="un") local vcetype unadjusted
	if (substr("`vcetype'",1,1)=="r") local vcetype robust
	if (substr("`vcetype'",1,2)=="cl") local vcetype cluster
	if ("`vcetype'"=="conventional") local vcetype unadjusted // Conventional is the name given in e.g. xtreg
	Assert strpos("`vcetype'",",")==0, msg("Unexpected contents of VCE: <`vcetype'> has a comma")

	* Implicit defaults
	if ("`vcetype'"=="" & "`weighttype'"=="pweight") local vcetype robust
	if ("`vcetype'"=="") local vcetype unadjusted

	* Sanity checks on vcetype
	Assert inlist("`vcetype'", "unadjusted", "robust", "cluster"), ///
		msg("vcetype '`vcetype'' not allowed")

	Assert !("`vcetype'"=="unadjusted" & "`weighttype'"=="pweight"), ///
		msg("pweights do not work with vce(unadjusted), use a different vce()")
	* Recall that [pw] = [aw] + _robust http://www.stata.com/statalist/archive/2007-04/msg00282.html
	
	* Also see: http://www.stata.com/statalist/archive/2004-11/msg00275.html
	* "aweights are for cell means data, i.e. data which have been collapsed through averaging,
	* and pweights are for sampling weights"

	* Cluster vars
	local num_clusters : word count `clustervars'
	Assert inlist( (`num_clusters'>0) + ("`vcetype'"=="cluster") , 0 , 2), msg("Can't specify cluster without clustervars and viceversa") // XOR

	* VCE Suite
	local vcesuite `suite'
	if ("`vcesuite'"=="") local vcesuite default
	if ("`vcesuite'"=="default") {
		if (`bw'>1 | `dkraay'>1 | "`kiefer'"!="" | "`kernel'"!="") {
			local vcesuite avar
		}
		else if (`num_clusters'>1) {
			local vcesuite mwc
		}
	}

	Assert inlist("`vcesuite'", "default", "mwc", "avar"), msg("Wrong vce suite: `vcesuite'")

	if ("`vcesuite'"=="mwc") {
		cap findfile tuples.ado
		Assert !_rc , msg("error: -tuples- not installed, please run {stata ssc install tuples} to estimate multi-way clusters.")
	}
	
	if ("`vcesuite'"=="avar") { 
		cap findfile avar.ado
		Assert !_rc , msg("error: -avar- not installed, please run {stata ssc install avar} or change the option -vcesuite-")
	}

	* Some combinations are not coded
	Assert !("`ivsuite'"=="ivregress" & (`num_clusters'>1 | `bw'>1 | `dkraay'>1 | "`kiefer'"!="" | "`kernel'"!="") ), msg("option vce(`vce') incompatible with ivregress")
	Assert !("`ivsuite'"=="ivreg2" & (`num_clusters'>2) ), msg("ivreg2 doesn't allow more than two cluster variables")
	Assert !("`model'"=="ols" & "`vcesuite'"=="avar" & (`num_clusters'>2) ), msg("avar doesn't allow more than two cluster variables")
	Assert !("`model'"=="ols" & "`vcesuite'"=="default" & (`bw'>1 | `dkraay'>1 | "`kiefer'"!="" | "`kernel'"!="") ), msg("to use those vce options you need to use -avar- as the vce suite")
	if (`num_clusters'>0) local temp_clustervars " <CLUSTERVARS>"
	if (`bw'==1 & `dkraay'==1 & "`kernel'"!="") local kernel // No point in setting kernel here 
	if (`bw'>1 | "`kernel'"!="") local vceextra `vceextra' bw(`bw') 
	if (`dkraay'>1) local vceextra `vceextra' dkraay(`dkraay') 
	if ("`kiefer'"!="") local vceextra `vceextra' kiefer 
	if ("`kernel'"!="") local vceextra `vceextra' kernel(`kernel')
	if ("`vceextra'"!="") local vceextra , `vceextra'
	local vceoption "`vcetype'`temp_clustervars'`vceextra'" // this excludes "vce(", only has the contents

* Parse -twicerobust-
	* If true, will use wmatrix(...) vce(...) instead of wmatrix(...) vce(unadjusted)
	* The former is closer to -ivregress- but not exact, the later matches -ivreg2-
	local twicerobust = ("`twicerobust'"!="")

	local keys vceoption vcetype vcesuite vceextra num_clusters clustervars bw kernel dkraay twicerobust kiefer
	foreach key of local keys {
		sreturn local `key' ``key''
	}
end

program define ParseAbsvars, rclass
syntax anything(id="absvars" name=absvars equalok everything), [SAVEfe]
	* Logic: split absvars -> expand each into factors -> split each into parts

	local g 0
	local all_cvars
	local all_ivars

	* Convert "target = absvar" into "target=absvar"
	* Need to deal with "= " " =" "  =   " and similar cases
	while (regexm("`absvars'", "[ ][ ]+")) {
		local absvars : subinstr local absvars "  " " ", all
	}
	local absvars : subinstr local absvars " =" "=", all
	local absvars : subinstr local absvars "= " "=", all

	local has_intercept 0
	
	while ("`absvars'"!="") {
		local ++g
		gettoken absvar absvars : absvars, bind
		local target
		if strpos("`absvar'","=") gettoken target absvar : absvar, parse("=")
		if ("`target'"!="") {
			conf new var `target'
			gettoken eqsign absvar : absvar, parse("=")
		}

		local hasdot = strpos("`absvar'", ".")
		local haspound = strpos("`absvar'", "#")
		if (!`hasdot' & !`haspound') local absvar i.`absvar'
		
		local 0 `absvar'
		syntax varlist(numeric fv) // REPLACETHIS!!!
		* This will expand very aggressively:
			* EG: x##c.y -> i.x c.y i.x#c.y
			* di as error "    varlist=<`varlist'>"
		
		local ivars
		local cvars
		
		local absvar_has_intercept 0

		foreach factor of local varlist {
			local hasdot = strpos("`factor'", ".")
			local haspound = strpos("`factor'", "#")
			local factor_has_cvars 0

			if (!`hasdot') continue
			while ("`factor'"!="") {
				gettoken part factor : factor, parse("#")
				local is_indicator = strpos("`part'", "i.")
				local is_continuous = strpos("`part'", "c.")
				local basevar = substr("`part'", 3, .)
				if (`is_indicator') local ivars `ivars' `basevar'
				if (`is_continuous') {
					local cvars `cvars' `basevar'
					local factor_has_cvars 1
				}
			}
			if (!`factor_has_cvars') local absvar_has_intercept 1
		}
		
		local ivars : list uniq ivars
		local num_slopes : word count `cvars'
		Assert "`ivars'"!="", msg("error parsing absvars: no indicator variables in absvar <`absvar'> (expanded to `varlist')")
		local unique_cvars : list uniq cvars
		Assert (`: list unique_cvars == cvars'), msg("error parsing absvars: factor interactions such as i.x##i.y not allowed")

		local all_cvars `all_cvars' `cvars'
		local all_ivars `all_ivars' `ivars'

		if (`absvar_has_intercept') local has_intercept 1

		return local target`g' `target'
		return local ivars`g' `ivars'
		return local cvars`g' `cvars'
		return scalar has_intercept`g' = `absvar_has_intercept'
		return scalar num_slopes`g' = `num_slopes'
	
		local label : subinstr local ivars " " "#", all
		if (`num_slopes'==1) {
			local label `label'#c.`cvars'
		}
		else if (`num_slopes'>1) {
			local label `label'#c.(`cvars')
		}
		return local varlabel`g' `label'
	
	}
	
	local all_ivars : list uniq all_ivars
	local all_cvars : list uniq all_cvars

	return scalar G = `g'
	return scalar savefe = ("`savefe'"!="")
	return local all_ivars `all_ivars'
	return local all_cvars `all_cvars'
	return scalar has_intercept = `has_intercept' // 1 if the model is not a pure-slope one
end

program define ParseDOF, sclass
	syntax, [ALL NONE] [PAIRwise TWO THREE] [CLusters] [CONTinuous]
	local opts `pairwise' `two' `three' `clusters' `continuous'
	local n : word count `opts'
	local first_opt : word 1 of `opt'

	opts_exclusive "`all' `none'" dofadjustments
	opts_exclusive "`pairwise' `two' `three'" dofadjustments
	opts_exclusive "`all' `first_opt'" dofadjustments
	opts_exclusive "`none' `first_opt'" dofadjustments

	if ("`none'" != "") local opts
	if ("`all'" != "") local opts pairwise clusters continuous

	if (`: list posof "three" in opts') {
		cap findfile group3hdfe.ado
		Assert !_rc , msg("error: -group3hdfe- not installed, please run {stata ssc install group3hdfe}")
	}

	sreturn local dofadjustments "`opts'"
end

program define ParseImplicit
* Parse options in the form NAME|NAME(arguments)
	* opt()			name of the option (so if opt=spam, we can have spam or spam(...))
	* default()		default value for the implicit form (in case we don't have a parenthesis)
	* syntax()		syntax of the contents of the parenthesis
	* input()		text to parse (usually `options', the result of a previous syntax .. , .. [*] )
	* inject()		what locals to inject on the caller (depend on -syntax)
	* xor			opt is mandatory (one of the two versions must occur)
	syntax, opt(name local) default(string) syntax(string asis) [input(string asis)] inject(namelist local) [xor]

	* First see if the implicit version is possible
	local lower_opt = lower("`opt'")
	local 0 , `input'
	cap syntax, `opt' [*]
	if ("`xor'"=="") local capture capture
	local rc = _rc
	if (`rc') {
		`capture' syntax, `opt'(string asis) [*]
		if ("`capture'"!="" & _rc) exit
	}
	else {
		local `lower_opt' `default'
	}
	local 0 ``lower_opt''
	syntax `syntax'
	foreach loc of local inject {
		c_local `loc' ``loc''
	}
	c_local options `options'
end

program define GenUID
	args uid
	local uid_type = cond(c(N)>c(maxlong), "double", "long")
	gen `uid_type' `uid' = _n // Useful for later merges
	la var `uid' "[UID]"
end

program define Compact, sclass
syntax, basevars(string) verbose(integer) [depvar(string) indepvars(string) endogvars(string) instruments(string)] ///
	[uid(string) timevar(string) panelvar(string) weightvar(string) weighttype(string) ///
	absorb_keepvars(string) clustervars(string)] ///
	[if(string) in(string) vceextra(string)] [savecache(integer 0) more_keepvars(varlist)]

* Drop unused variables
	local weight "`weighttype'"
	local exp "= `weightvar'"

	marksample touse, novar // Uses -if- , -in- and -exp- ; can't drop any var until this
	local cluster_keepvars `clustervars'
	local cluster_keepvars : subinstr local cluster_keepvars "#" " ", all
	local cluster_keepvars : subinstr local cluster_keepvars "i." "", all
	keep `uid' `touse' `basevars' `timevar' `panelvar' `weightvar' `absorb_keepvars' `cluster_keepvars' `more_keepvars'

* Expand factor and time-series variables
	local expandedvars
	local sets depvar indepvars endogvars instruments // depvar MUST be first
	Debug, level(4) newline
	Debug, level(4) msg("{title:Expanding factor and time-series variables:}")
	foreach set of local sets {
		local varlist ``set''
		if ("`varlist'"=="") continue
		// local original_`set' `varlist'
		* the -if- prevents creating dummies for categories that have been excluded
		ExpandFactorVariables `varlist' if `touse', setname(`set') verbose(`verbose') savecache(`savecache')
		local `set' "`r(varlist)'"
		local expandedvars `expandedvars' ``set''
	}

* Variables needed for savecache
	if (`savecache') {
		local cachevars `timevar' `panelvar'
		foreach basevar of local basevars {
			local in_expanded : list basevar in expandedvars
			if (!`in_expanded') {
				local cachevars `cachevars' `basevar'
			}
		}
		c_local cachevars `cachevars'
		if ("`cachevars'"!="") Debug, level(0) msg("(cachevars: {res}`cachevars'{txt})")
	}

* Drop unused basevars and tsset vars (usually no longer needed)
	if ("`vceextra'"!="") local tsvars `panelvar' `timevar' // We need to keep them only with autoco-robust VCE
	keep `uid' `touse' `expandedvars' `weightvar' `absorb_keepvars' `cluster_keepvars' `tsvars' `cachevars' `more_keepvars'

* Convert absvar and clustervar string variables to numeric
* Note that this will still fail if we did absorb(i.somevar)
	tempvar encoded
	foreach var of varlist `absorb_keepvars' `cluster_keepvars' {
		local vartype : type `var'
		local is_string = substr("`vartype'", 1, 3) == "str"
		if (`is_string') {
			encode `var', gen(`encoded')
			drop `var'
			rename `encoded' `var'
			qui compress `var'
		}
	}

* Drop excluded observations and observations with missing values
	markout `touse' `expandedvars' `weightvar' `absorb_keepvars' `cluster_keepvars'
	qui keep if `touse'
	if ("`weightvar'"!="") assert `weightvar'>0 // marksample should have dropped those // if ("`weightvar'"!="") qui drop if (`weightvar'==0)
	Assert c(N)>0, rc(2000) msg("Empty sample, check for missing values or an always-false if statement")
	if ("`weightvar'"!="") {
		la var `weightvar' "[WEIGHT] `: var label `weightvar''"
	}
	foreach set of local sets {
		if ("``set''"!="") c_local `set' ``set''
	}
	c_local expandedvars `expandedvars'
end

		
// -------------------------------------------------------------------------------------------------
// Expand factor time-series variables
// -------------------------------------------------------------------------------------------------
* Steps:
* 1) Call -fvrevar-
* 2) Label newly generated temporary variables
* 3) Drop i) omitted variables, and ii) base variables (if not part of a #c.var interaction)

program define ExpandFactorVariables, rclass
syntax varlist(min=1 numeric fv ts) [if] [,setname(string)] [SAVECACHE(integer 0)] verbose(integer)
	
	* If saving the data for later regressions -savecache(..)- we will need to match each expansion to its newvars
	* The mata array is used for that
	* Note: This explains why we need to wrap -fvrevar- in a loop
	if (`savecache') {
		mata: varlist_cache = asarray_create()
		mata: asarray_notfound(varlist_cache, "")
	}

	local expanded_msg `"" - variable expansion for `setname': {res}`varlist'{txt} ->""'
	while (1) {
		gettoken factorvar varlist : varlist, bind
		if ("`factorvar'"=="") continue, break

		* Create temporary variables from time and factor expressions
		* -fvrevar- is slow so only call it if needed
		mata: st_local("hasdot", strofreal(strpos("`factorvar'", ".")>0))
		if (`hasdot') {
			fvrevar `factorvar' `if' // , stub(__V__) // stub doesn't work in Stata 11.2
			local subvarlist `r(varlist)'
		}
		else {
			local subvarlist `factorvar'
		}

		local contents
		foreach var of varlist `subvarlist' {
			LabelRenameVariable `var' // Tempvars not renamed will be dropped automatically
			if !r(is_dropped) {
				local contents `contents' `r(varname)'
				// if (`savecache') di as error `"<mata: asarray(varlist_cache, "`factorvar'", "`r(varname)'")>"'
				if (`savecache') mata: asarray(varlist_cache, "`factorvar'", asarray(varlist_cache, "`factorvar'") + " " + "`r(varname)'")
			}
			* Yellow=Already existed, White=Created, Red=NotCreated (omitted or base)
			local color = cond(r(is_dropped), "error", cond(r(is_newvar), "input", "result"))
			if (`verbose'>3) {
				local expanded_msg `"`expanded_msg' as `color' " `r(name)'" as text " (`r(varname)')""'
			}
		}
		Assert "`contents'"!="", msg("error: variable -`factorvar'- in varlist -`varlist'- in category -`setname'- is  empty after factor/time expansion")
		local newvarlist `newvarlist' `contents'
	}

	Debug, level(4) msg(`expanded_msg')
	return clear
	return local varlist "`newvarlist'"
end

program define LabelRenameVariable, rclass
syntax varname
	local var `varlist'
	local fvchar : char `var'[fvrevar]
	local tschar : char `var'[tsrevar]
	local is_newvar = ("`fvchar'`tschar'"!="") & substr("`var'", 1, 2)=="__"
	local name "`var'"
	local will_drop 0

	if (`is_newvar') {
		local name "`fvchar'`tschar'"
		local parts : subinstr local fvchar "#" " ", all
		local has_cont_interaction = strpos("`fvchar'", "c.")>0
		local is_omitted 0
		local is_base 0
		foreach part of local parts {
			if (regexm("`part'", "b.*\.")) local is_base 1
			if (regexm("`part'", "o.*\.")) local is_omitted 1
		}

		local will_drop = (`is_omitted') | (`is_base' & !`has_cont_interaction')
		if (!`will_drop') {
			char `var'[name] `name'
			la var `var' "[TEMPVAR] `name'"
			local newvar : subinstr local name "." "__", all
			local newvar : subinstr local newvar "#" "_X_", all
			* -permname- selects newname# if newname is taken (# is the first number available)
			local newvar : permname __`newvar', length(30)
			rename `var' `newvar'
			local var `newvar'
		}
	}
	else {
		char `var'[name] `var'
	}

	return scalar is_newvar = `is_newvar'
	return scalar is_dropped = `will_drop'
	return local varname "`var'"
	return local name "`name'"
end

program define Prepare, sclass

syntax, depvar(string) stages(string) model(string) expandedvars(string) vcetype(string) ///
	 has_intercept(integer) ///
	 [weightexp(string) endogvars(string)]

* Save the statistics we need before transforming the variables
	* Compute TSS of untransformed depvar
	local tmpweightexp = subinstr("`weightexp'", "[pweight=", "[aweight=", 1)
	qui su `depvar' `tmpweightexp'
	
	local tss = r(Var)*(r(N)-1)
	if (!`has_intercept') local tss = `tss' + r(sum)^2 / (r(N))
	c_local tss = `tss'

	if (`: list posof "first" in stages') {
		foreach var of varlist `endogvars' {
			qui su `var' `tmpweightexp'

			local tss = r(Var)*(r(N)-1)
			if (!`has_intercept') local tss = `tss' + r(sum)^2 / (r(N))
			c_local tss_`var' = `tss'
		}
	}

* (optional) Compute R2/RSS to run nested Ftests on the FEs
	* a) Compute R2 of regression without FE, to build the joint FTest for all the FEs
	* b) Also, compute RSS of regressions with less FEs so we can run nested FTests on the FEs
	if ("`model'"=="ols" & inlist("`vcetype'", "unadjusted", "ols")) {
		qui _regress `expandedvars' `weightexp', noheader notable
		c_local r2c = e(r2)
	}
end

	
// -----------------------------------------------------------------------------
// Matrix of summary statistics
// -----------------------------------------------------------------------------

program define Stats
	syntax varlist(numeric), [weightexp(string)] stats(string) statsmatrix(string) [USEcache]

	if ("`usecache'"=="") {
		local tabstat_weight : subinstr local weightexp "[pweight" "[aweight"
		qui tabstat `varlist' `tabstat_weight' , stat(`stats') col(stat) save
		matrix `statsmatrix' = r(StatTotal)

		* Fix names (__L__.price -> L.price)
		local colnames : colnames `statsmatrix'
		FixVarnames `colnames'
		local colnames "`r(newnames)'"
		matrix colnames `statsmatrix' = `colnames'
	}
	else {
		cap conf matrix reghdfe_statsmatrix
		
		* Fix names
		FixVarnames `varlist'
		local sample_names "`r(newnames)'"

		* Trim matrix
		local all_names : colnames reghdfe_statsmatrix
		local first 1 // 1 if `statsmatrix' is still empty
		foreach name of local all_names {
			local is_match : list name in sample_names
			if (`is_match' & `first') {
				local first 0
				matrix `statsmatrix' = reghdfe_statsmatrix[1..., "`name'"]
			}
			else if (`is_match') {
				matrix `statsmatrix' = `statsmatrix' , reghdfe_statsmatrix[1..., "`name'"]	
			}
		}
	}
end

	
* Compute model F-test; called by regress/mwc/avar wrappers

program define JointTest, eclass
	args K
	if (`K'>0) {
		RemoveOmitted
		qui test `r(indepvars)' // Wald test
		if (r(drop)==1) {
			Debug, level(0) msg("WARNING: Missing F statistic (dropped variables due to collinearity or too few clusters).")
			ereturn scalar F = .
		}
		else {
			ereturn scalar F = r(F)
			if missing(e(F)) di as error "WARNING! Missing FStat"
		}
		ereturn scalar df_m = r(df)
		ereturn scalar rank = r(df) // Not adding constant anymore
	}
	else {
		ereturn scalar F = 0
		ereturn scalar df_m = 0
		ereturn scalar rank = 0 // Not adding constant anymore
	}
end

* Remove omitted variables from a beta matrix, and return remaining indepvars

program define RemoveOmitted, rclass
	tempname b
	matrix `b' = e(b)
	local names : colnames `b'
	foreach name of local names {
		_ms_parse_parts `name'
		assert inlist(r(omit),0,1)
		if !r(omit) {
			local indepvars `indepvars' `name'
		}
	}
	return local indepvars `indepvars'
end

program define Wrapper_regress, eclass
	syntax , depvar(varname) [indepvars(varlist)] ///
		vceoption(string asis)  ///
		kk(integer) ///
		[weightexp(string)] ///
		[SUBOPTions(string)] [*] // [*] are ignored!
	
	if ("`options'"!="") Debug, level(3) msg("(ignored options: `options')")
	if (c(version)>=12) local hidden hidden

* Convert -vceoption- to what -regress- expects
	gettoken vcetype clustervars : vceoption
	local clustervars `clustervars' // Trim
	local vceoption : subinstr local vceoption "unadjusted" "ols"
	local vceoption "vce(`vceoption')"

	RemoveCollinear, depvar(`depvar') indepvars(`indepvars') weightexp(`weightexp')
	local K = r(df_m)
	local vars `r(vars)'

* Run -regress-
	local subcmd regress `vars' `weightexp', `vceoption' `suboptions' noconstant noheader notable
	Debug, level(3) msg("Subcommand: " in ye "`subcmd'")
	qui `subcmd'
	
	local N = e(N) // We can't use c(N) due to possible frequency weights
	local WrongDoF = `N' - `K'
	if ("`vcetype'"!="cluster" & e(df_r)!=`WrongDoF') {
		local difference = `WrongDoF' - e(df_r)
		local NewDFM = e(df_m) - `difference'	
		di as result "(warning: regress returned e(df_r)==`e(df_r)', but we expected it to be `WrongDoF')"
		Assert e(df_m)>=0, msg("try removing collinear regressors or setting a higher tol()")
		di as result "(workaround: we will set e(df_m)=`NewDFM' instead of `e(df_m)')"
	}
	local CorrectDoF = `WrongDoF' - `kk' // kk = Absorbed DoF

* Store results for the -ereturn post-
	tempname b V
	matrix `b' = e(b)
	matrix `V' = e(V)
	local N = e(N)
	local marginsok = e(marginsok)
	local rmse = e(rmse)
	local rss = e(rss)
	local tss = e(mss) + e(rss) // Regress doesn't report e(tss)
	local N_clust = e(N_clust)

	local predict = e(predict)
	local cmd = e(cmd)
	local cmdline "`e(cmdline)'"
	local title = e(title)

	* Fix V
	if (`K'>0) matrix `V' = `V' * (`WrongDoF' / `CorrectDoF')

	* DoF
	if ("`vcetype'"=="cluster") {
		Assert e(df_r) == e(N_clust) - 1
		*Assert e(N_clust) > `K', msg("insufficient observations (N_clust=`e(N_clust)', K=`K')") rc(2001)
		if (e(N_clust) <= `K') {
			di as error "WARNING: insufficient observations (N_clust=`e(N_clust)', K=`K')"
		}
	}
	local df_r = cond( "`vcetype'"=="cluster" , e(df_r) , max( `CorrectDoF' , 0 ) )

	* Post
		* Note: the dof() option of regress is *useless* with robust errors,
		* and overriding e(df_r) is also useless because -test- ignores it,
		* so we have to go all the way and do a -post- from scratch
	capture ereturn post `b' `V' `weightexp', dep(`depvar') obs(`N') dof(`df_r') properties(b V)
	local rc = _rc
	Assert inlist(_rc,0,504), msg("error `=_rc' when adjusting the VCV") // 504 = Matrix has MVs
	Assert `rc'==0, msg("Error: estimated variance-covariance matrix has missing values")
	ereturn local marginsok = "`marginsok'"
	ereturn local predict = "`predict'"
	ereturn local cmd = "`cmd'"
	ereturn local cmdline `"`cmdline'"'
	ereturn local title = "`title'"
	ereturn local clustvar = "`clustervars'"
	ereturn scalar rmse = `rmse'
	ereturn scalar rss = `rss'
	ereturn scalar tss = `tss'
	if (`N_clust'<.) ereturn scalar N_clust = `N_clust'
	if (`N_clust'<.) ereturn scalar N_clust1 = `N_clust'
	ereturn `hidden' scalar unclustered_df_r = `CorrectDoF' // Used later in R2 adj

* Compute model F-test
	JointTest `K' // adds e(F), e(df_m), e(rank)
end

		
* Tag Collinear Variables with an o. and compute correct e(df_m)
	* Obtain K so we can obtain DoF = N - K - kk
	* This is already done by regress EXCEPT when clustering
	* (but we still need the unclustered version for r2_a, etc.)

program define RemoveCollinear, rclass
	syntax, depvar(varname numeric) [indepvars(varlist numeric) weightexp(string)]

	qui _rmcoll `indepvars' `weightexp', forcedrop
	local okvars "`r(varlist)'"
	if ("`okvars'"==".") local okvars
	local df_m : list sizeof okvars

	foreach var of local indepvars {
		local ok : list var in okvars
		local prefix = cond(`ok', "", "o.")
		local label : char `var'[name]
		if (!`ok') di as text "note: `label' omitted because of collinearity"
		local varlist `varlist' `prefix'`var'
	}

	mata: st_local("vars", strtrim(stritrim( "`depvar' `varlist'" )) ) // Just for aesthetic purposes
	return local vars "`vars'"
	return scalar df_m = `df_m'

end

program define Wrapper_avar, eclass
	syntax , depvar(varname) [indepvars(varlist)] ///
		vceoption(string asis) ///
		kk(integer) ///
		[weightexp(string)] ///
		[SUBOPTions(string)] [*] // [*] are ignored!

	if ("`options'"!="") Debug, level(3) msg("(ignored options: `options')")
	if (c(version)>=12) local hidden hidden

	local tmpweightexp = subinstr("`weightexp'", "[pweight=", "[aweight=", 1)

* Convert -vceoption- to what -avar- expects
	local 0 `vceoption'
	syntax namelist(max=3) , [bw(integer 1) dkraay(integer 1) kernel(string) kiefer]
	gettoken vcetype clustervars : namelist
	local clustervars `clustervars' // Trim
	Assert inlist("`vcetype'", "unadjusted", "robust", "cluster")
	local vceoption = cond("`vcetype'"=="unadjusted", "", "`vcetype'")
	if ("`clustervars'"!="") local vceoption `vceoption'(`clustervars')
	if (`bw'>1) local vceoption `vceoption' bw(`bw')
	if (`dkraay'>1) local vceoption `vceoption' dkraay(`dkraay')
	if ("`kernel'"!="") local vceoption `vceoption' kernel(`kernel')
	if ("`kiefer'"!="") local vceoption `vceoption' kiefer

* Before -avar- we need:
*	i) inv(X'X)
*	ii) DoF lost due to included indepvars
*	iii) resids

* Remove collinear variables; better than what -regress- does
	RemoveCollinear, depvar(`depvar') indepvars(`indepvars') weightexp(`weightexp')
	local K = r(df_m)
	local vars `r(vars)'

* Note: It would be shorter to use -mse1- (b/c then invSxx==e(V)*e(N)) but then I don't know e(df_r)
	local subcmd regress `vars' `weightexp', noconstant
	Debug, level(3) msg("Subcommand: " in ye "`subcmd'")
	qui `subcmd'
	qui cou if !e(sample)
	assert r(N)==0

	local K = e(df_m) // Should also be equal to e(rank)+1
	local WrongDoF = e(df_r)

	* Store some results for the -ereturn post-
	tempname b
	matrix `b' = e(b)
	local N = e(N)
	local marginsok = e(marginsok)
	local rmse = e(rmse)
	local rss = e(rss)
	local tss = e(mss) + e(rss) // Regress doesn't report e(tss)

	local predict = e(predict)
	local cmd = e(cmd)
	local cmdline `"`e(cmdline)'"'
	local title = e(title)

	* Compute the bread of the sandwich inv(X'X/N)
	tempname XX invSxx
	qui mat accum `XX' = `indepvars' `tmpweightexp', noconstant
	* WHY DO I NEED TO REPLACE PWEIGHT WITH AWEIGHT HERE?!?
	
	* (Is this precise enough? i.e. using -matrix- commands instead of mata?)
	mat `invSxx' = syminv(`XX' * 1/`N')
	
	* Resids
	tempvar resid
	predict double `resid', resid

	* DoF
	local df_r = max( `WrongDoF' - `kk' , 0 )

* Use -avar- to get meat of sandwich
	local subcmd avar `resid' (`indepvars') `weightexp', `vceoption' noconstant // dofminus(0)
	Debug, level(3) msg("Subcommand: " in ye "`subcmd'")
	cap `subcmd'
	local rc = _rc
	if (`rc') {
		di as error "Error in -avar- module:"
		noi `subcmd'
		exit 198
	}

	local N_clust = r(N_clust)
	local N_clust1 = cond(r(N_clust1)<., r(N_clust1), r(N_clust))
	local N_clust2 = r(N_clust2)

* Get the entire sandwich
	* Without clusters it's as if every obs. is is own cluster
	local M = cond( r(N_clust) < . , r(N_clust) , r(N) )
	local q = ( `N' - 1 ) / `df_r' * `M' / (`M' - 1) // General formula, from Stata PDF
	tempname V

	* A little worried about numerical precision
	matrix `V' = `invSxx' * r(S) * `invSxx' / r(N) // Large-sample version
	matrix `V' = `V' * `q' // Small-sample adjustments
	* At this point, we have the true V and just need to add it to e()

* Avoid corner case error when all the RHS vars are collinear with the FEs
	local unclustered_df_r = `df_r' // Used later in R2 adj
	if (`dkraay'>1) local clustervars "`_dta[_TStvar]'" // BUGBUG ?
	if ("`clustervars'"!="") local df_r = `M' - 1

	capture ereturn post `b' `V' `weightexp', dep(`depvar') obs(`N') dof(`df_r') properties(b V)

	local rc = _rc
	Assert inlist(_rc,0,504), msg("error `=_rc' when adjusting the VCV") // 504 = Matrix has MVs
	Assert `rc'==0, msg("Error: estimated variance-covariance matrix has missing values")
	ereturn local marginsok = "`marginsok'"
	ereturn local predict = "`predict'"
	ereturn local cmd = "`cmd'"
	ereturn local cmdline `"`cmdline'"'
	ereturn local title = "`title'"
	ereturn local clustvar = "`clustervars'"

	ereturn scalar rmse = `rmse'
	ereturn scalar rss = `rss'
	ereturn scalar tss = `tss'
	if ("`N_clust'"!="") ereturn scalar N_clust = `N_clust'
	if ("`N_clust1'"!="" & "`N_clust1'"!=".") ereturn scalar N_clust1 = `N_clust1'
	if ("`N_clust2'"!="" & "`N_clust2'"!=".") ereturn scalar N_clust2 = `N_clust2'
	ereturn `hidden' scalar unclustered_df_r = `unclustered_df_r'

	if (`bw'>1) {
		ereturn scalar bw = `bw'
		if ("`kernel'"=="") local kernel Bartlett // Default
	}
	if ("`kernel'"!="") ereturn local kernel = "`kernel'"
	if ("`kiefer'"!="") ereturn local kiefer = "`kiefer'"
	if (`dkraay'>1) ereturn scalar dkraay = `dkraay'

* Compute model F-test
	JointTest `K' // adds e(F), e(df_m), e(rank)
end

program define Wrapper_mwc, eclass
* This will compute an ols regression with 2+ clusters
syntax , depvar(varname) [indepvars(varlist)] ///
	vceoption(string asis) ///
	kk(integer) ///
	[weightexp(string)] ///
	[SUBOPTions(string)] [*] // [*] are ignored!

	if ("`options'"!="") Debug, level(3) msg("(ignored options: `options')")
	if (c(version)>=12) local hidden hidden

* Parse contents of VCE()
	local 0 `vceoption'
	syntax namelist(max=11) // Of course clustering by anything beyond 2-3 is insane
	gettoken vcetype clustervars : namelist
	assert "`vcetype'"=="cluster"
	local clustervars `clustervars' // Trim

* Remove collinear variables; better than what -regress- does
	RemoveCollinear, depvar(`depvar') indepvars(`indepvars') weightexp(`weightexp')
	local K = r(df_m)
	local vars `r(vars)'

* Obtain e(b), e(df_m), and resids
	local subcmd regress `vars' `weightexp', noconstant
	Debug, level(3) msg("Subcommand: " in ye "`subcmd'")
	qui `subcmd'

	local K = e(df_m)
	local WrongDoF = e(df_r)

	* Store some results for the -ereturn post-
	tempname b
	matrix `b' = e(b)
	local N = e(N)
	local marginsok = e(marginsok)
	local rmse = e(rmse)
	local rss = e(rss)
	local tss = e(mss) + e(rss) // Regress doesn't report e(tss)

	local predict = e(predict)
	local cmd = e(cmd)
	local cmdline "`e(cmdline)'"
	local title = e(title)

	* Compute the bread of the sandwich D := inv(X'X/N)
	tempname XX invSxx
	qui mat accum `XX' = `indepvars' `weightexp', noconstant
	mat `invSxx' = syminv(`XX') // This line is different from <Wrapper_avar>

	* Resids
	tempvar resid
	predict double `resid', resid

	* DoF
	local df_r = max( `WrongDoF' - `kk' , 0 )

* Use MWC to get meat of sandwich "M" (notation: V = DMD)
	local size = rowsof(`invSxx')
	tempname M V // Will store the Meat and the final Variance
	matrix `V' = J(`size', `size', 0)

* This gives all the required combinations of clustervars (ssc install tuples)
	tuples `clustervars' // create locals i) ntuples, ii) tuple1 .. tuple#
	tempvar group
	local N_clust = .
	local j 0

	forval i = 1/`ntuples' {
		matrix `M' =  `invSxx'
		local vars `tuple`i''
		local numvars : word count `vars'
		local sign = cond(mod(`numvars', 2), "+", "-") // + with odd number of variables, - with even

		GenerateID `vars', gen(`group')
		
		if (`numvars'==1) {
			su `group', mean
			local ++j
			local h : list posof "`vars'" in clustervars
			local N_clust`h' = r(max)

			local N_clust = min(`N_clust', r(max))
			Debug, level(2) msg(" - multi-way-clustering: `vars' has `r(max)' groups")
		}
		
		* Compute the full sandwich (will be saved in `M')

		_robust `resid' `weightexp', variance(`M') minus(0) cluster(`group') // Use minus==1 b/c we adjust the q later
		Debug, level(3) msg(as result "`sign' `vars'")
		* Add it to the other sandwiches
		matrix `V' = `V' `sign' `M'
		drop `group'
	}

	local N_clustervars = `j'

* If the VCV matrix is not positive-semidefinite, use the fix from
* Cameron, Gelbach & Miller - Robust Inference with Multi-way Clustering (JBES 2011)
* 1) Use eigendecomposition V = U Lambda U' where U are the eigenvectors and Lambda = diag(eigenvalues)
* 2) Replace negative eigenvalues into zero and obtain FixedLambda
* 3) Recover FixedV = U * FixedLambda * U'
* This will fail if V is not symmetric (we could use -mata makesymmetric- to deal with numerical precision errors)

	mata: fix_psd("`V'") // This will update `V' making it PSD
	assert inlist(`eigenfix', 0, 1)
	if (`eigenfix') Debug, level(0) msg("Warning: VCV matrix was non-positive semi-definite; adjustment from Cameron, Gelbach & Miller applied.")

	local M = `N_clust' // cond( `N_clust' < . , `N_clust' , `N' )
	local q = ( `N' - 1 ) / `df_r' * `M' / (`M' - 1) // General formula, from Stata PDF
	matrix `V' = `V' * `q'

	* At this point, we have the true V and just need to add it to e()

	local unclustered_df_r = `df_r' // Used later in R2 adj
	local df_r = `M' - 1 // Cluster adjustment

	capture ereturn post `b' `V' `weightexp', dep(`depvar') obs(`N') dof(`df_r') properties(b V)

	local rc = _rc
	Assert inlist(_rc,0,504), msg("error `=_rc' when adjusting the VCV") // 504 = Matrix has MVs
	Assert `rc'==0, msg("Error: estimated variance-covariance matrix has missing values")
	ereturn local marginsok = "`marginsok'"
	ereturn local predict = "`predict'"
	ereturn local cmd = "`cmd'"
	ereturn local cmdline `"`cmdline'"'
	ereturn local title = "`title'"
	ereturn scalar rmse = `rmse'
	ereturn scalar rss = `rss'
	ereturn scalar tss = `tss'
	ereturn `hidden' scalar unclustered_df_r = `unclustered_df_r'

	ereturn local clustvar = "`clustervars'"
	assert `N_clust'<.
	ereturn scalar N_clust = `N_clust'
	forval i = 1/`N_clustervars' {
		ereturn scalar N_clust`i' = `N_clust`i''
	}

* Compute model F-test
	JointTest `K' // adds e(F), e(df_m), e(rank)
end

program define Wrapper_ivreg2, eclass
	syntax , depvar(varname) endogvars(varlist) instruments(varlist) ///
		[indepvars(varlist)] ///
		vceoption(string asis) ///
		KK(integer) ///
		ffirst(integer) ///
		[weightexp(string)] ///
		[ESTimator(string)] ///
		[num_clusters(string) clustervars(string)] ///
		[SUBOPTions(string)] [*] // [*] are ignored!
	if ("`options'"!="") Debug, level(3) msg("(ignored options: `options')")
	if (c(version)>=12) local hidden hidden
	
	* Disable some options
	local 0 , `suboptions'
	syntax , [SAVEFPrefix(name)] [*] // Will ignore SAVEFPREFIX
	local suboptions `options'

	* Convert -vceoption- to what -ivreg2- expects
	local 0 `vceoption'
	syntax namelist(max=3) , [bw(string) dkraay(string) kernel(string) kiefer]
	gettoken vcetype transformed_clustervars : namelist
	local transformed_clustervars `transformed_clustervars' // Trim
	Assert inlist("`vcetype'", "unadjusted", "robust", "cluster")
	local vceoption = cond("`vcetype'"=="unadjusted", "", "`vcetype'")
	if ("`transformed_clustervars'"!="") local vceoption `vceoption'(`transformed_clustervars')
	if ("`bw'"!="") local vceoption `vceoption' bw(`bw')
	if ("`dkraay'"!="") local vceoption `vceoption' dkraay(`dkraay')
	if ("`kernel'"!="") local vceoption `vceoption' kernel(`kernel')
	if ("`kiefer'"!="") local vceoption `vceoption' kiefer
	
	mata: st_local("vars", strtrim(stritrim( "`depvar' `indepvars' (`endogvars'=`instruments')" )) )

	local opt small nocons sdofminus(`kk') `vceoption'  `suboptions'
	if (`ffirst') local opt `opt' ffirst
	if ("`estimator'"!="2sls") local opt `opt' `estimator'
	
	local subcmd ivreg2 `vars' `weightexp', `opt'
	Debug, level(3) msg(_n "call to subcommand: " _n as result "`subcmd'")
	qui `subcmd'
	ereturn scalar tss = e(mss) + e(rss) // ivreg2 doesn't report e(tss)
	ereturn scalar unclustered_df_r = e(N) - e(df_m)

	if ("`e(vce)'"=="robust cluster") ereturn local vce = "cluster"

	if !missing(e(ecollin)) {
		di as error "endogenous covariate <`e(ecollin)'> was perfectly predicted by the instruments!"
		error 2000
	}

	local cats depvar instd insts inexog exexog collin dups ecollin clist redlist ///
		exexog1 inexog1 instd1 
	foreach cat in `cats' {
		FixVarnames `e(`cat')'
		ereturn local `cat' = "`r(newnames)'"
	}
end

program define Wrapper_ivregress, eclass
	syntax , depvar(varname) endogvars(varlist) instruments(varlist) ///
		[indepvars(varlist)] ///
		vceoption(string asis) ///
		KK(integer) ///
		[weightexp(string)] ///
		[ESTimator(string) TWICErobust(integer 0)] ///
		[SUBOPTions(string)] [*] // [*] are ignored!

	if ("`options'"!="") Debug, level(3) msg("(ignored options: `options')")
	mata: st_local("vars", strtrim(stritrim( "`depvar' `indepvars' (`endogvars'=`instruments')" )) )
	if (c(version)>=12) local hidden hidden

	local opt_estimator = cond("`estimator'"=="gmm2s", "gmm", "`estimator'")

	* Convert -vceoption- to what -ivreg2- expects
	local 0 `vceoption'
	syntax namelist(max=2)
	gettoken vceoption clustervars : namelist
	local clustervars `clustervars' // Trim
	Assert inlist("`vceoption'", "unadjusted", "robust", "cluster")
	if ("`clustervars'"!="") local vceoption `vceoption' `clustervars'
	local vceoption "vce(`vceoption')"

	if ("`estimator'"=="gmm2s") {
		local wmatrix : subinstr local vceoption "vce(" "wmatrix("
		local vceoption = cond(`twicerobust', "", "vce(unadjusted)")
	}
	
	* Note: the call to -ivregress- could be optimized.
	* EG: -ivregress- calls ereturn post .. ESAMPLE(..) but we overwrite the esample and its SLOW
	* But it's a 1700 line program so let's not worry about it

* Subcmd
	local subcmd ivregress `opt_estimator' `vars' `weightexp', `wmatrix' `vceoption' small noconstant `suboptions'
	Debug, level(3) msg("Subcommand: " in ye "`subcmd'")
	qui `subcmd'
	qui test `indepvars' `endogvars' // Wald test
	ereturn scalar F = r(F)

	
	* Fix DoF if needed
	local N = e(N)
	local K = e(df_m)
	local WrongDoF = `N' - `K'
	local CorrectDoF = `WrongDoF' - `kk'
	Assert !missing(`CorrectDoF')

	* We should have used M/M-1 instead of N/N-1, but we are making ivregress to do the wrong thing by using vce(unadjusted) (which makes it fit with ivreg2)
	local q 1
	if ("`estimator'"=="gmm2s" & "`clustervars'"!="") {
		local N = e(N)
		tempvar group
		GenerateID `clustervars', gen(`group')
		su `group', mean
		drop `group'
		local M = r(max) // N_clust
		local q = ( `M' / (`M' - 1)) / ( `N' / (`N' - 1) ) // multiply correct, divide prev wrong one
		ereturn scalar df_r = `M' - 1
	}

	tempname V
	matrix `V' = e(V) * (`WrongDoF' / `CorrectDoF') * `q'
	ereturn repost V=`V'
	
	if ("`clustervars'"=="") ereturn scalar df_r = `CorrectDoF'

	* ereturns specific to this command
	ereturn scalar F = e(F) * `CorrectDoF' / `WrongDoF'

	ereturn scalar tss = e(mss) + e(rss) // ivreg2 doesn't report e(tss)
	ereturn `hidden' scalar unclustered_df_r = `CorrectDoF' // Used later in R2 adj
end

		
// -------------------------------------------------------------
// Faster alternative to -egen group-. MVs, IF, etc not allowed!
// -------------------------------------------------------------

program define GenerateID, sortpreserve
syntax varlist(numeric) , [REPLACE Generate(name)] [CLUSTERVARS(namelist) NESTED]
assert ("`replace'"!="") + ("`generate'"!="") == 1

	foreach var of varlist `varlist' {
		assert !missing(`var')
	}

	local numvars : word count `varlist'
	if ("`replace'"!="") assert `numvars'==1 // Can't replace more than one var!
	
	// Create ID
	tempvar new_id
	sort `varlist'
	by `varlist': gen long `new_id' = (_n==1)
	qui replace `new_id' = sum(`new_id')
	qui compress `new_id'
	assert !missing(`new_id')
	
	local name = "i." + subinstr("`varlist'", " ", "#i.", .)
	char `new_id'[name] `name'
	la var `new_id' "[ID] `name'"

	// Could use these chars to speed up DropSingletons	and Wrapper_mwc
	*char `new_id'[obs] `c(N)' 
	*char `new_id'[id] 1 

	// Either replace or generate
	if ("`replace'"!="") {
		drop `varlist'
		rename `new_id' `varlist'
		local new_id `varlist' // I need to keep track of the variable for the clustervar part
	}
	else {
		rename `new_id' `generate'
		local new_id `generate'
	}

	// See if var. is nested within a clustervar
	local in_clustervar 0
	local is_clustervar 0

	if ("`clustervars'"!="") {
		
		* Check if clustervar===ID
		foreach clustervar of local clustervars {
			if ("`new_id'"=="`clustervar'") {
				local is_clustervar 1
				local nesting_clustervar "`clustervar'"
				continue, break
			}
		}
		
		* Check if ID is nested within cluster ("if two obs. belong to the same ID, they belong to the same cluster")
		if (!`is_clustervar' & "`nested'"!="") {
			tempvar same
			qui gen byte `same' = .
			foreach clustervar of local clustervars {

				* Avoid check if clustervar is another absvar
				* Reason: it would be stupid to have one absvar nested in another (same result as dropping nesting one)
				local clustervar_is_absvar = regexm("`clustervar'","__FE[0-9]+__")
				if (`clustervar_is_absvar') continue

				qui bys `new_id' (`clustervar'): replace `same' = (`clustervar'[1] == `clustervar'[_N])
				qui cou if (`same'==0)
				if r(N)==0 {
					local in_clustervar 1
					local nesting_clustervar "`clustervar'"
					continue, break
				}
			}
		}
	}

	char `new_id'[is_clustervar] `is_clustervar'
	char `new_id'[in_clustervar] `in_clustervar'
	char `new_id'[nesting_clustervar] `nesting_clustervar' 
end

program define SaveFE
	syntax, model(string) depvar(string) untransformed(string) subpredict(string) ///
		has_intercept(integer) ///
		[weightexp(string)] [drop_resid_vector(integer 1)]

	Debug, level(2) msg("(calculating fixed effects)")
	tempvar resid
	local score = cond("`model'"=="ols", "score", "resid")
	Debug, level(3) msg(" - predicting resid (equation: y=xb+d+cons+resid)")
	if e(df_m)>0 {
		`subpredict' double `resid', `score' // equation: y = xb + d + e, we recovered "e"
	}
	else {
		gen double `resid' = `depvar'
	}
	mata: store_resid(HDFE_S, "`resid'")

	Debug, level(3) msg(" - reloading untransformed dataset")
	qui use "`untransformed'", clear
	erase "`untransformed'"
	mata: resid2dta(HDFE_S, 0, `drop_resid_vector')

	Debug, level(3) msg(" - predicting resid+d+cons (equation: y=xb+d+cons+resid)")
	tempvar resid_d
	if e(df_m)>0 {
		`subpredict' double `resid_d', `score' // This is "d+e" (including constant)
	}
	else {
		gen double `resid_d' = `depvar'
	}

	Debug, level(3) msg(" - computing d = resid_d - mean(resid_d) - resid")
	tempvar d

	* Computing mean(resid_d), the constant term (only if there is an intercept in absorb)
	if (`has_intercept') {
		local tmpweightexp = subinstr("`weightexp'", "[pweight=", "[aweight=", 1)
		su `resid_d' `tmpweightexp', mean
		gen double `d' = `resid_d' - r(mean) - `resid'
	}
	else {
		gen double `d' = `resid_d' - `resid'
	}	
	
	drop `resid' `resid_d'
	//clonevar dd = `d'

	Debug, level(3) msg(" - disaggregating d = z1 + z2 + ...")
	mata: map_save_fe(HDFE_S, "`d'")
	//regress dd __hdfe*, nocons
	drop `d'
end

program define Post, eclass
	syntax, coefnames(string) ///
		model(string) stage(string) stages(string) subcmd(string) cmdline(string) vceoption(string) original_absvars(string) extended_absvars(string) vcetype(string) vcesuite(string) tss(string) num_clusters(string) ///
			has_intercept(integer) ///
		[dofadjustments(string) clustervars(string) timevar(string) r2c(string) equation_d(string) subpredict(string) savestages(string) diopts(string) weightvar(string) dkraay(string) estimator(string) by(string) level(string)] ///
		[backup_original_depvar(string) original_indepvars(string) original_endogvars(string) original_instruments(string)]

	if (`c(version)'>=12) local hidden hidden // ereturn hidden requires v12+

	Assert e(tss)<., msg("within tss is missing")
	Assert `tss'<., msg("overall tss is missing")
	Assert e(N)<., msg("# obs. missing in e()")

	* Why is this here and not right after FixVarnames?
	* Because of some Stata black magic, if I repost *before* the restore this will not work
	ereturn repost b=`coefnames', rename

	if ("`weightvar'"!="") {
		qui su `weightvar', mean
		ereturn scalar sumweights = r(sum)
	}

* Absorbed-specific returns
	* e(N_hdfe) e(N_hdfe_extended) e(mobility)==M e(df_a)==K-M
	* e(M#) e(K#) e(M#_exact) e(M#_nested) -> for #=1/e(N_hdfe_extended)
	mata: map_ereturn_dof(HDFE_S)
	local N_hdfe = e(N_hdfe)
	Assert e(df_r)<. , msg("e(df_r) is missing")

* MAIN LOCALS
	ereturn local cmd = "reghdfe"
	ereturn local cmdline `"`cmdline'"'
	ereturn local subcmd = cond(inlist("`stage'", "none", "iv"), "`subcmd'", "regress")
	
	ereturn local model = cond("`model'"=="iv" & "`estimator'"!="2sls", "`estimator'", "`model'")
	Assert inlist("`e(model)'", "ols", "iv", "gmm2s", "cue", "liml"), msg("tried to save invalid model: `e(model)'")

	ereturn local dofadjustments = "`dofadjustments'"
	ereturn local title = "HDFE " + e(title)
	ereturn local title2 =  "Absorbing `N_hdfe' HDFE " + plural(`N_hdfe', "group")
	ereturn local predict = "reghdfe_p"
	ereturn local estat_cmd = "reghdfe_estat"
	ereturn local footnote = "reghdfe_footnote"
	ereturn `hidden' local equation_d "`equation_d'" // The equation used to construct -d- (used to predict)
	ereturn local absvars "`original_absvars'"
	ereturn `hidden' local extended_absvars "`extended_absvars'"
	

	ereturn `hidden' local diopts = "`diopts'"
	ereturn `hidden' local subpredict = "`subpredict'"

* CLUSTER AND VCE
	
	ereturn local vcesuite = "`vcesuite'"
	if ("`e(subcmd)'"=="ivreg2") local vcesuite = "avar" // This is what ivreg2 uses
	if ("`e(subcmd)'"=="ivregress") local vcesuite = "default"

	* Replace __CL#__ and __ID#__ from cluster subtitles

	if ("`e(clustvar)'"!="") {
		if ("`e(subcmd)'"=="ivreg2") local subtitle = "`e(hacsubtitleV)'"
		if (`num_clusters'>1) {
			local rest `clustervars'
			forval i = 1/`num_clusters' {
				gettoken token rest : rest
				if ("`e(subcmd)'"=="ivreg2" & strpos("`e(clustvar`i')'", "__")==1) {
					local subtitle = subinstr("`subtitle'", "`e(clustvar`i')'", "`token'", 1)
				}
				ereturn local clustvar`i' `token'
			}
		}
		else {
			local subtitle = subinstr("`subtitle'", "`e(clustvar)'", "`clustervars'", 1)
		}
		ereturn scalar N_clustervars = `num_clusters'
		ereturn local clustvar `clustervars'
		if ("`e(subcmd)'"=="ivreg2") ereturn local hacsubtitleV = "`subtitle'"
	}
	if (`dkraay'>1) {
		ereturn local clustvar `timevar'
		ereturn scalar N_clustervars = 1
	}

	
	* Stata uses e(vcetype) for the SE column headers
	* In the default option, leave it empty.
	* In the cluster and robust options, set it as "Robust"
	ereturn local vcetype = proper("`vcetype'") //
	if (e(vcetype)=="Cluster") ereturn local vcetype = "Robust"
	if (e(vcetype)=="Unadjusted") ereturn local vcetype
	if ("`e(vce)'"=="." | "`e(vce)'"=="") ereturn local vce = "`vcetype'" // +-+-
	Assert inlist("`e(vcetype)'", "", "Robust", "Jackknife", "Bootstrap")

* STAGE
	if ("`stage'"!="none") ereturn local iv_depvar = "`backup_original_depvar'"

* VARLISTS
	* Besides each cmd's naming style (e.g. exogr, exexog, etc.) keep one common one
	foreach cat in indepvars endogvars instruments {
		if ("`original_`cat''"=="") continue
		ereturn local `cat' "`original_`cat''"
	}

* MAIN NUMERICS
	ereturn `hidden' scalar tss_within = e(tss)
	ereturn scalar tss = `tss'
	ereturn scalar mss = e(tss) - e(rss)
	ereturn scalar ll   = -0.5 * (e(N)*ln(2*_pi) + e(N)*ln(e(rss)       /e(N)) + e(N))
	ereturn scalar ll_0 = -0.5 * (e(N)*ln(2*_pi) + e(N)*ln(e(tss_within)/e(N)) + e(N))
	ereturn scalar r2 = 1 - e(rss) / e(tss)
	ereturn scalar r2_within = 1 - e(rss) / e(tss_within)

	* ivreg2 uses e(r2c) and e(r2u) for centered/uncetered R2; overwrite first and discard second
	if (e(r2c)!=.) {
		ereturn scalar r2c = e(r2)
		ereturn scalar r2u = .
	}

	* Computing Adj R2 with clustered SEs is tricky because it doesn't use the adjusted inputs:
	* 1) It uses N instead of N_clust
	* 2) For the DoFs, it uses N - Parameters instead of N_clust-1
	* 3) Further, to compute the parameters, it includes those nested within clusters
	
	* Note that this adjustment is NOT PERFECT because we won't compute the mobility groups just for improving the r2a
	* (when a FE is nested within a cluster, we don't need to compute mobilty groups; but to get the same R2a as other estimators we may want to do it)
	* Instead, you can set by hand the dof() argument and remove -cluster- from the list

	if ("`model'"=="ols" & `num_clusters'>0) Assert e(unclustered_df_r)<., msg("wtf-`vcesuite'")
	local used_df_r = cond(e(unclustered_df_r)<., e(unclustered_df_r), e(df_r)) - e(M_due_to_nested)
	ereturn scalar r2_a = 1 - (e(rss)/`used_df_r') / ( e(tss) / (e(N)-`has_intercept') )
	ereturn scalar rmse = sqrt( e(rss) / `used_df_r' )
	ereturn scalar r2_a_within = 1 - (e(rss)/`used_df_r') / ( e(tss_within) / (`used_df_r'+e(df_m)) )

	if (e(N_clust)<.) Assert e(df_r) == e(N_clust) - 1, msg("Error, `wrapper' should have made sure that N_clust-1==df_r")
	*if (e(N_clust)<.) ereturn scalar df_r = e(N_clust) - 1

	if ("`model'"=="ols" & inlist("`vcetype'", "unadjusted", "ols")) {
		 // -1 b/c we exclude constant for this
		 ereturn scalar F_absorb = (e(r2)-`r2c') / (1-e(r2)) * e(df_r) / (e(df_a)-1)

		//if (`nested') {
		//	local rss`N_hdfe' = e(rss)
		//	local temp_dof = e(N) - e(df_m) // What if there are absorbed collinear with the other RHS vars?
		//	local j 0
		//	ereturn `hidden' scalar rss0 = `rss0'
		//	forv g=1/`N_hdfe' {
		//		local temp_dof = `temp_dof' - e(K`g') + e(M`g')
		//		*di in red "g=`g' RSS=`rss`g'' and was `rss`j''.  dof=`temp_dof'"
		//		ereturn `hidden' scalar rss`g' = `rss`g''
		//		ereturn `hidden' scalar df_a`g' = e(K`g') - e(M`g')
		//		local df_a_g = e(df_a`g') - (`g'==1)
		//		ereturn scalar F_absorb`g' = (`rss`j''-`rss`g'') / `rss`g'' * `temp_dof' / `df_a_g'
		//		ereturn `hidden' scalar df_r`g' = `temp_dof'
		//		local j `g'
		//	}   
		//}
	}

	if ("`savestages'"!="") ereturn `hidden' scalar savestages = `savestages'

	* We have to replace -unadjusted- or else subsequent calls to -suest- will fail
	Subtitle `vceoption' // will set title2, etc. Run after e(bw) and all the others are set!
	if (e(vce)=="unadjusted") ereturn local vce = "ols"

	if ("`stages'"!="none") {
		ereturn local stage = "`stage'"
		ereturn `hidden' local stages = "`stages'"
	}

	* List of stored estimates
	if ("`e(savestages)'"=="1" & "`e(model)'"=="iv") {
		local stages = "`e(stages)'"
		local endogvars "`e(endogvars)'"
		foreach stage of local stages {
			if ("`stage'"=="first") {
				local i 0
				foreach endogvar of local endogvars {
					local stored_estimates `stored_estimates' reghdfe_`stage'`++i'
				}
			}
			else if ("`stage'"!="iv"){
				local stored_estimates `stored_estimates' reghdfe_`stage'
			}
		}

	}

	* Add e(first) (first stage STATISTICS, from ffirst option) to each first stage
	* For that we require 3 things: ffirst, that we save stages, and that first is in the stage list
	cap conf matrix e(first)
	if (c(rc)==0 & "`e(savestages)'"=="1" & strpos("`e(stages)'", "first")) {
		tempname firststats hold
		matrix `firststats' = e(first)
		local rownames : rownames `firststats'
		local colnames : colnames `firststats'
		local endogvars "`e(endogvars)'"

		estimates store `hold'
		local i 0
		ereturn clear
		foreach endogvar of local endogvars {
			local est reghdfe_first`++i'
			qui estimates restore `est'
			gettoken colname colnames : colnames
			Assert "`endogvar'"=="`colname'", msg("expected `endogvar'==`colname' from e(first)")
			Assert "`endogvar'"=="`e(depvar)'", msg("expected `endogvar'==`e(depvar)' from e(depvar)")

			local j 0
			foreach stat of local rownames {
				Assert "`e(first_`stat')'"=="", msg("expected e(first_`stat') to be empty")
				ereturn scalar first_`stat' = `firststats'[`++j', `i']
			}
			estimates store `est', nocopy
		}
		ereturn clear // Need this because -estimates restore- behaves oddly
		qui estimates restore `hold'
		assert e(cmd)=="reghdfe"
		estimates drop `hold'
	}

		ereturn local stored_estimates "`stored_estimates'"

	if ("`e(model)'"=="iv") {
		if ("`e(stage)'"=="first") estimates title: First-stage regression: `e(depvar)'
		if ("`e(stage)'"=="ols") estimates title: OLS regression
		if ("`e(stage)'"=="reduced") estimates title: Reduced-form regression
		if ("`e(stage)'"=="acid") estimates title: Acid regression
	}
end

		
//------------------------------------------------------------------------------
// Name tempvars into e.g. L.x i1.y i2.y AvgE:z , etc.
//------------------------------------------------------------------------------

program define FixVarnames, rclass
local vars `0'

	foreach var of local vars {
		* Note: -var- can be <o.var>
		_ms_parse_parts `var'
		local is_omitted = r(omit)
		local name = r(name)

		local is_temp = substr("`name'",1,2)=="__"
		local newname : char `name'[name]
		*local label : var label `basevar'

		* Stata requires all parts of an omitted interaction to have an o.
		if (`is_omitted' & `is_temp') {
			while regexm("`newname'", "^(.*[^bo])\.(.*)$") {
				local newname = regexs(1) + "o." + regexs(2)
			}
		}
		else if (`is_omitted') {
			local newname "o.`name'" // same as initial `var'!
		}

		Assert ("`newname'"!=""), msg("var=<`var'> --> new=<`newname'>")
		local newnames `newnames' `newname'
	}

	local A : word count `vars'
	local B : word count `newnames'
	Assert `A'==`B', msg("`A' vars but `B' newnames")
	return local newnames "`newnames'"
end

program define Subtitle, eclass
	* Fill e(title3/4/5) based on the info of the other e(..)

	if (inlist("`e(vcetype)'", "Robust", "Cluster")) local hacsubtitle1 "heteroskedasticity"
	if ("`e(kernel)'"!="" & "`e(clustvar)'"=="") local hacsubtitle3 "autocorrelation"
	if ("`e(kiefer)'"!="") local hacsubtitle3 "within-cluster autocorrelation (Kiefer)"
	if ("`hacsubtitle1'"!="" & "`hacsubtitle3'" != "") local hacsubtitle2 " and "
	local hacsubtitle "`hacsubtitle1'`hacsubtitle2'`hacsubtitle3'"
	if strlen("`hacsubtitle'")>30 {
		local hacsubtitle : subinstr local hacsubtitle "heteroskedasticity" "heterosk.", all word
		local hacsubtitle : subinstr local hacsubtitle "autocorrelation" "autocorr.", all word
	}
	if ("`hacsubtitle'"!="") {
		ereturn local title3 = "Statistics robust to `hacsubtitle'"
		
		if ("`e(kernel)'"!="") local notes " `notes' kernel=`e(kernel)'"
		if ("`e(bw)'"!="") local notes " `notes' bw=`e(bw)'"
		if ("`e(dkraay)'"!="") local notes " `notes' dkraay=`e(dkraay)'"
		local notes `notes' // remove initial space
		if ("`notes'"!="") ereturn local title4 = " (`notes')"
		if ("`notes'"!="") {
			if ("`_dta[_TSpanel]'"!="") local tsset panel=`_dta[_TSpanel]'
			if ("`_dta[_TStvar]'"!="") local tsset `tsset' time=`_dta[_TStvar]'
			local tsset `tsset'
			ereturn local title5 = " (`tsset')"
		}
	}
end

program define Attach, eclass
	syntax, [NOTES(string)] [statsmatrix(string)] summarize_quietly(integer)
	
	* Summarize
	* This needs to happen after all the missing obs. have been dropped and the only obs. are those that *WILL* be in the regression
	if ("`statsmatrix'"!="") {
		* Update beta vector
		* ...

		ereturn matrix summarize = `statsmatrix', copy // If we move instead of copy, stages() will fail
		if (!`summarize_quietly' & "`statsmatrix'"!="") {
			di as text _n "{sf:Regression Summary Statistics:}" _c
			matlist e(summarize)', border(top bottom) twidth(18) rowtitle(Variable)
		}
	}

	* Parse key=value options and append to ereturn as hidden
	mata: st_local("notes", strtrim(`"`notes'"')) // trim (supports large strings)
	local keys
	while (`"`notes'"'!="") {
		gettoken key notes : notes, parse(" =")
		Assert !inlist("`key'","sample","time"), msg("Key cannot be -sample- or -time-") // Else -estimates- will fail
		gettoken _ notes : notes, parse("=")
		gettoken value notes : notes, quotes
		local keys `keys' `key'
		ereturn hidden local `key' `value'
	}
	if ("`keys'"!="") ereturn hidden local keys `keys'

end


// -------------------------------------------------------------
// Display Regression Table
// -------------------------------------------------------------

 program define Replay, eclass
	syntax , [stored] [*]
	Assert e(cmd)=="reghdfe"
	local subcmd = e(subcmd)
	Assert "`subcmd'"!="" , msg("e(subcmd) is empty")
	if (`c(version)'>=12) local hidden hidden

	if ("`stored'"!="" & "`e(stored_estimates)'"!="" & "`e(stage)'"=="iv") {
		local est_list "`e(stored_estimates)'"
		tempname hold
		estimates store `hold'
		foreach est of local est_list {
			cap estimates restore `est'
			if (!c(rc)) Replay
		}
		ereturn clear // Need this because -estimates restore- behaves oddly
		qui estimates restore `hold'
		assert e(cmd)=="reghdfe"
		estimates drop `hold'
	}

	if ("`e(stage)'"=="first") local first_depvar " - `e(depvar)'"
	if ("`e(stage)'"!="") di as text _n "{inp}{title:Stage: `e(stage)'`first_depvar'}"

	local diopts = "`e(diopts)'"
	if ("`options'"!="") { // Override
		_get_diopts diopts /* options */, `options'
	}

	if ("`subcmd'"=="ivregress") {
		* Don't want to display anova table or footnote
		_coef_table_header
		_coef_table, `diopts'
	}
	else if ("`subcmd'"=="ivreg2") {
		cap conf matrix e(first)
		if (c(rc)==0) local ffirst ffirst
		ereturn local cmd = "`subcmd'"
		`subcmd' , `diopts' `ffirst'
		ereturn local cmd = "reghdfe"
	}
	else {

		* Regress-specific code, because it doesn't play nice with ereturn
		sreturn clear 

		if "`e(prefix)'" != "" {
			_prefix_display, `diopts'
			exit
		}
		
		Header // _coef_table_header

		di
		local cond ("`e(model)'"=="ols" & inlist("`e(vce)'","unadjusted","ols") & e(df_a)>1)
		local plus = cond(`cond', "plus", "")
		_coef_table, `plus' `diopts'
	}
	reghdfe_footnote
end

	
* (Modified from _coef_table_header.ado)

program define Header
	if !c(noisily) exit

	tempname left right
	.`left' = {}
	.`right' = {}

	local width 78
	local colwidths 1 30 51 67
	local i 0
	foreach c of local colwidths {
		local ++i
		local c`i' `c'
		local C`i' _col(`c')
	}

	local c2wfmt 10
	local c4wfmt 10
	local max_len_title = `c3' - 2
	local c4wfmt1 = `c4wfmt' + 1
	local title  `"`e(title)'"'
	local title2 `"`e(title2)'"'
	local title3 `"`e(title3)'"'
	local title4 `"`e(title4)'"'
	local title5 `"`e(title5)'"'

	// Right hand header ************************************************

	*N obs
	.`right'.Arrpush `C3' "Number of obs" `C4' "= " as res %`c4wfmt'.0fc e(N)

	* Ftest
	if `"`e(chi2)'"' != "" | "`e(df_r)'" == "" {
		Chi2test `right' `C3' `C4' `c4wfmt'
	}
	else {
		Ftest `right' `C3' `C4' `c4wfmt'
	}

	* display R-squared
	if !missing(e(r2)) {
		.`right'.Arrpush `C3' "R-squared" `C4' "= " as res %`c4wfmt'.4f e(r2)
	}
	*if !missing(e(r2_p)) {
	*	.`right'.Arrpush `C3' "Pseudo R2" `C4' "= " as res %`c4wfmt'.4f e(r2_p)
	*}
	if !missing(e(r2_a)) {
		.`right'.Arrpush `C3' "Adj R-squared" `C4' "= " as res %`c4wfmt'.4f e(r2_a)
	}
	if !missing(e(r2_within)) {
		.`right'.Arrpush `C3' "Within R-sq." `C4' "= " as res %`c4wfmt'.4f e(r2_within)
	}
	if !missing(e(rmse)) {
		.`right'.Arrpush `C3' "Root MSE" `C4' "= " as res %`c4wfmt'.4f e(rmse)
	}

	// Left hand header *************************************************

	* make title line part of the header if it fits
	local len_title : length local title
	forv i=2/5 {
		if (`"`title`i''"'!="") {
			local len_title = max(`len_title',`:length local title`i'')
		}
	}
	
	if `len_title' < `max_len_title' {
		.`left'.Arrpush `"`"`title'"'"'
		local title
		forv i=2/5 {
			if `"`title`i''"' != "" {
					.`left'.Arrpush `"`"`title`i''"'"'
					local title`i'
			}
		}
		.`left'.Arrpush "" // Empty
	}

	* Clusters
	local kr = `.`right'.arrnels' // number of elements in the right header
	local kl = `.`left'.arrnels' // number of elements in the left header
	local N_clustervars = e(N_clustervars)
	if (`N_clustervars'==.) local N_clustervars 0
	local space = `kr' - `kl' - `N_clustervars'
	local clustvar = e(clustvar)
	forv i=1/`space' {
		.`left'.Arrpush ""
	}
	forval i = 1/`N_clustervars' {
		gettoken cluster clustvar : clustvar
		local num = e(N_clust`i')
		.`left'.Arrpush `C1' "Number of clusters (" as res "`cluster'" as text  ") " `C2' as text "= " as res %`c2wfmt'.0fc `num'
	}
	
	HeaderDisplay `left' `right' `"`title'"' `"`title2'"' `"`title3'"' `"`title4'"' `"`title5'"'
end

program define HeaderDisplay
		args left right title1 title2 title3 title4 title5

		local nl = `.`left'.arrnels'
		local nr = `.`right'.arrnels'
		local K = max(`nl',`nr')

		di
		if `"`title1'"' != "" {
				di as txt `"`title'"'
				forval i = 2/5 {
					if `"`title`i''"' != "" {
							di as txt `"`title`i''"'
					}
				}
				if `K' {
						di
				}
		}

		local c _c
		forval i = 1/`K' {
				di as txt `.`left'[`i']' as txt `.`right'[`i']'
		}
end

program define Ftest
		args right C3 C4 c4wfmt is_svy

		local df = e(df_r)
		if !missing(e(F)) {
				.`right'.Arrpush                                ///
						 `C3' "F("                              ///
				   as res %4.0f e(df_m)                         ///
				   as txt ","                                   ///
				   as res %7.0f `df' as txt ")" `C4' "= "       ///
				   as res %`c4wfmt'.2f e(F)
				.`right'.Arrpush                                ///
						 `C3' "Prob > F" `C4' "= "              ///
				   as res %`c4wfmt'.4f Ftail(e(df_m),`df',e(F))
		}
		else {
				local dfm_l : di %4.0f e(df_m)
				local dfm_l2: di %7.0f `df'
				local j_robust "{help j_robustsingular##|_new:F(`dfm_l',`dfm_l2')}"
				.`right'.Arrpush                                ///
						  `C3' "`j_robust'"                     ///
				   as txt `C4' "= " as result %`c4wfmt's "."
				.`right'.Arrpush                                ///
						  `C3' "Prob > F" `C4' "= " as res %`c4wfmt's "."
		}
end

program define Chi2test

		args right C3 C4 c4wfmt

		local type `e(chi2type)'
		if `"`type'"' == "" {
				local type Wald
		}
		if !missing(e(chi2)) {
				.`right'.Arrpush                                ///
						  `C3' "`type' chi2("                   ///
				   as res e(df_m)                               ///
				   as txt ")" `C4' "= "                         ///
				   as res %`c4wfmt'.2f e(chi2)
				.`right'.Arrpush                                ///
						  `C3' "Prob > chi2" `C4' "= "          ///
				   as res %`c4wfmt'.4f chi2tail(e(df_m),e(chi2))
		}
		else {
				local j_robust                                  ///
				"{help j_robustsingular##|_new:`type' chi2(`e(df_m)')}"
				.`right'.Arrpush                                ///
						  `C3' "`j_robust'"                     ///
				   as txt `C4' "= " as res %`c4wfmt's "."
				.`right'.Arrpush                                ///
						  `C3' "Prob > chi2" `C4' "= "          ///
				   as res %`c4wfmt's "."
		}
end

program define InnerSaveCache, eclass
* (note: based on Inner.ado)

* INITIAL CLEANUP
	ereturn clear // Clear previous results and drops e(sample)

* PARSE - inject opts with c_local, create Mata structure HDFE_S (use verbose>2 for details)
	Parse `0'
	assert `savecache'
	Assert !`will_save_fe', msg("savecache disallows saving FEs")

* PROBLEM:
	* I can translate L(1/2).x into __L__x __L2__x
	* But how can I translate i.x if I don't have the original anymore?

* SOLUTION
	* The cache option of ExpandFactorVariables (called from Compact.ado)

* COMPACT - Expand time and factor variables, and drop unused variables and obs.
	Compact, basevars(`basevars') depvar(`depvar' `indepvars') uid(`uid') timevar(`timevar') panelvar(`panelvar') weightvar(`weightvar') weighttype(`weighttype') ///
		absorb_keepvars(`absorb_keepvars') clustervars(`clustervars') ///
		if(`if') in(`in') verbose(`verbose') vceextra(`vceextra') savecache(1) more_keepvars(`keepvars')
	// Injects locals: depvar indepvars endogvars instruments expandedvars cachevars

* PRECOMPUTE MATA OBJECTS (means, counts, etc.)
	mata: map_init_keepvars(HDFE_S, "`expandedvars' `uid' `cachevars' `keepvars'") 	// Non-essential vars will be deleted (e.g. interactions of a clustervar)
	mata: map_precompute(HDFE_S)
	global updated_clustervars = "`r(updated_clustervars)'"
	
* PREPARE - Compute untransformed tss *OF ALL THE VARIABLES*
	mata: tss_cache = asarray_create()
	mata: asarray_notfound(tss_cache, .)
	local tmpweightexp = subinstr("`weightexp'", "[pweight=", "[aweight=", 1)
	foreach var of local expandedvars {
		qui su `var' `tmpweightexp' // BUGBUG: Is this correct?!
		local tss = r(Var)*(r(N)-1)
		if (!`has_intercept') local tss = `tss' + r(sum)^2 / (r(N))
		mata: asarray(tss_cache, "`var'", "`tss'")
	}
	*NOTE: r2c is too slow and thus won't be saved
	*ALTERNATIVE: Allow a varlist of the form (depvars) (indepvars) and only compute for those

* COMPUTE e(stats) - Summary statistics for the all the regression variables
	if ("`stats'"!="") {
		Stats `expandedvars', weightexp(`weightexp') stats(`stats') statsmatrix(reghdfe_statsmatrix)
	}

* COMPUTE DOF
	if (`timeit') Tic, n(62)
	mata: map_estimate_dof(HDFE_S, "`dofadjustments'", "`groupvar'") // requires the IDs
	if (`timeit') Toc, n(62) msg(estimate dof)
	assert e(df_a)<. // estimate_dof() only sets e(df_a); map_ereturn_dof() is for setting everything aferwards
	local kk = e(df_a) // we need this for the regression step

* MAP_SOLVE() - WITHIN TRANFORMATION (note: overwrites variables)
	qui ds `expandedvars'
	local NUM_VARS : word count `r(varlist)'
	Debug, msg("(computing residuals for `NUM_VARS' variables)")
	mata: map_solve(HDFE_S, "`expandedvars'")

* This was in -parse- but we are dropping observations through the code
	char _dta[cache_obs] `c(N)'

end

program define InnerUseCache, eclass

* INITIAL CLEANUP
	ereturn clear // Clear previous results and drops e(sample)
	cap estimates drop reghdfe_*

* PARSE - inject opts with c_local, create Mata structure HDFE_S (use verbose>2 for details)
	Parse `0'
	assert `usecache'
	if (`timeit') Tic, n(50)

	foreach cat in depvar indepvars endogvars instruments {
		local original_`cat' "``cat''"
	}

* Match "L.price" --> __L__price
* Expand factor and time-series variables
* (based on part of Compact.ado)
	if (`timeit') Tic, n(52)
	local expandedvars
	local sets depvar indepvars endogvars instruments // depvar MUST be first
	Debug, level(4) newline
	Debug, level(4) msg("{title:Expanding factor and time-series variables:}")
	foreach set of local sets {
		local varlist ``set''
		local `set' // empty
		if ("`varlist'"=="") continue
		fvunab factors : `varlist', name("error parsing `set'")
		foreach factor of local factors {
			mata: st_local("var", asarray(varlist_cache, "`factor'"))
			Assert "`var'"!="", msg("couldn't find the match of {res}`factor'{error} in the cache (details: set=`set'; factors=`factors')")
			local `set' ``set'' `var'
		}
		local expandedvars `expandedvars' ``set''
	}
	if (`timeit') Toc, n(52) msg(fix names)

* Replace vceoption with the correct cluster names (e.g. if it's a FE or a new variable)
	if (`num_clusters'>0) {
		assert "$updated_clustervars"!=""
		local vceoption : subinstr local vceoption "<CLUSTERVARS>" "$updated_clustervars"
	}

* PREPARE - Compute untransformed tss, R2 of eqn w/out FEs
	if (`timeit') Tic, n(54)
	mata: st_local("tss", asarray(tss_cache, "`depvar'"))
	Assert `tss'<., msg("tss of depvar `depvar' not found in cache")
	foreach var of local endogvars {
		mata: st_local("tss_`var'", asarray(tss_cache, "`var'"))
	}
	local r2c = . // BUGBUG!!!
	if (`timeit') Toc, n(54) msg(use cached tss)

 * COMPUTE DOF - Already precomputed in InnerSaveCache.ado
	if (`timeit') Tic, n(62)
	mata: map_ereturn_dof(HDFE_S) // this gives us e(df_a)==`kk', which we need
	assert e(df_a)<.
	local kk = e(df_a) // we need this for the regression step
	if (`timeit') Toc, n(62) msg(load dof estimates)

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
	local opts /// cond // BUGUBG: Add by() (cond) options
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
		// No need to store in Mata
	}

* (optional) Save mobility groups (note: group vector will stay on HDFE_S)
	if ("`groupvar'"!="") mata: groupvar2dta(HDFE_S, 0)

* FIX VARNAMES - Replace tempnames in the coefs table (run AFTER regress)
	* (e.g. __00001 -> L.somevar)
	if (`timeit') Tic, n(68)
	tempname b
	matrix `b' = e(b)
	local backup_colnames : colnames `b'
	FixVarnames `backup_colnames'
	local newnames "`r(newnames)'"
	matrix colnames `b' = `newnames'
	ereturn local depvar = "`original_depvar'" // Run after SaveFE
	if (`timeit') Toc, n(68) msg(fix varnames)

* POST ERETURN - Add e(...) (besides e(sample) and those added by the wrappers)	
	local opt_list
	local opts dofadjustments subpredict model stage stages subcmd cmdline vceoption equation_d original_absvars extended_absvars vcetype vcesuite tss r2c savestages diopts weightvar estimator dkraay by level num_clusters clustervars timevar backup_original_depvar original_indepvars original_endogvars original_instruments has_intercept
	foreach opt of local opts {
		local opt_list `opt_list' `opt'(``opt'')
	}
	if (`timeit') Tic, n(69)
	Post, `opt_list' coefnames(`b')
	if (`timeit') Toc, n(69) msg(Post)

* REPLAY - Show the regression table	
	Replay

* ATTACH - Add e(stats) and e(notes)
	if ("`stats'"!="") {
		if (`timeit') Tic, n(71)
		tempname statsmatrix
		Stats `expandedvars', weightexp(`weightexp') stats(`stats') statsmatrix(`statsmatrix') usecache
		// stats() will be ignored
		if (`timeit') Toc, n(71) msg(Stats.ado)
	}
	if (`timeit') Tic, n(72)
	Attach, notes(`notes') statsmatrix(`statsmatrix') summarize_quietly(`summarize_quietly') // Attach only once, not per stage
	if (`timeit') Toc, n(72) msg(Attach.ado)

* Store stage result
	if (!inlist("`stage'","none", "iv") & `savestages') estimates store reghdfe_`stage'`i_endogvar', nocopy

} // lhs_endogvar
} // stage

	if (`timeit') Toc, n(50) msg([TOTAL])
end

// -------------------------------------------------------------------------------------------------
