*! version 4.1.1 20mar2017

program reghdfe, eclass
	* Intercept old+version
	cap syntax, version old
	if !c(rc) {
		reghdfe_old, version
		exit
	}

	* Intercept old
	cap syntax anything(everything) [fw aw pw/], [*] old
	if !c(rc) {
		di as error "(running historical version of reghdfe)"
		if ("`weight'"!="") local weightexp [`weight'=`exp']
		reghdfe_old `anything' `weightexp', `options'
		exit
	}

	* Aux. subcommands
	cap syntax, [*]
	if inlist("`options'", "check", "compile", "reload", "update", "version", "requirements") {
		if ("`options'"=="compile") loc args force
		if ("`options'"=="check") loc options compile
		if ("`options'"=="update") {
			loc args 1
			loc options reload
		}
		loc subcmd = proper("`options'")
		`subcmd' `args'
	}
	else if replay() {
		Replay `0'
	}
	else {
		Cleanup 0
		Compile // takes 0.01s to run this useful check (ensures .mlib exists)
		cap noi Estimate `0'
		Cleanup `c(rc)'
	}
end


program Compile
	args force
	ftools, check // in case lftools.mlib does not exist or is outdated
	ms_get_version reghdfe // from moresyntax package; save local package_version

	loc list_objects "FixedEffects() fixed_effects() BipartiteGraph()"
	loc list_functions "reghdfe_*() transform_*() accelerate_*() panelmean() panelsolve_*() lsmr()"
	loc list_misc "weighted_quadcolsum() safe_divide() check_convergence()"
	// TODO: prefix everything with reghdfe_*

	ms_compile_mata, ///
		package(reghdfe) ///
		version(`package_version') ///
		fun("`list_objects' `list_functions' `list_misc'") ///
		verbose ///
		`force'
end


program Reload
	* Internal debugging tool.
	* Updates dependencies and reghdfe from local path or from github
	* Usage:
	* 	reghdfe, update // from c:\git\..
	* 	reghdfe, reload // from github

	args online
	if ("`online'" == "") loc online 0

	di as text _n "{bf:reghdfe: updating required packages}"
	di as text "{hline 64}"

	* -moresyntax- https://github.com/sergiocorreia/moresyntax/
	cap ado uninstall moresyntax
	if (`online') net install moresyntax, from("https://github.com/sergiocorreia/moresyntax/raw/master/src/")
	if (!`online') net install moresyntax, from("c:\git\moresyntax\src")
	di as text "{hline 64}"

	* -ftools- https://github.com/sergiocorreia/ftools/
	cap ado uninstall ftools
	if (`online') net install ftools, from("https://github.com/sergiocorreia/ftools/raw/master/src/")
	if (!`online') net install ftools, from("c:\git\ftools\src")
	di as text "{hline 64}"
	ftools, compile // requires moresyntax
	di as text "{hline 64}"

	* Update -reghdfe-
	di as text _n  _n "{bf:reghdfe: updating self}"
	di as text "{hline 64}"
	qui ado uninstall reghdfe
	if (`online') net install reghdfe, from("https://github.com/sergiocorreia/reghdfe/raw/version-4/src/")
	if (!`online') net install reghdfe, from("c:\git\reghdfe\src")
	qui which reghdfe
	di as text "{hline 64}"
	reghdfe, compile
	di as text "{hline 64}"

	* Cleaning up
	di as text _n "{bf:Note:} You need to run {stata program drop _all} now."
end


program Version
	which reghdfe
	Requirements
end


program Requirements
	di as text _n "Required packages installed?"
	loc reqs moresyntax ftools
	// ivreg2 avar tuples group3hdfe
	if (c(version)<13) loc reqs `reqs' boottest

	loc ftools_github "https://github.com/sergiocorreia/ftools/raw/master/src/"
	loc moresyntax_github "https://github.com/sergiocorreia/moresyntax/raw/master/src/"

	loc error 0

	foreach req of local reqs {
		loc fn `req'.ado
		if ("`req'"=="moresyntax") loc fn ms_get_version.ado
		cap findfile `fn'
		if (_rc) {
			loc error 1
			di as text "{lalign 20:- `req'}" as error "not" _c
			di as text "    {stata ssc install `req':install from SSC}" _c
			if inlist("`req'", "ftools", "moresyntax") {
				loc github ``req'_github'
				di as text `"    {stata `"net install `req', from(`"`github'"')"':install from github}"'
			}
			else {
				di as text // newline
			}
		}
		else {
			di as text "{lalign 20:- `req'}" as text "yes"
		}
	}

	if (`error') exit 601
end


program Cleanup
	args rc
	cap mata: mata drop HDFE
	cap mata: mata drop hdfe_*
	cap drop __temp_reghdfe_resid__
	cap matrix drop reghdfe_statsmatrix
	if (`rc') exit `rc'
end


program Parse
	* Trim whitespace (caused by "///" line continuations; aesthetic only)
	mata: st_local("0", stritrim(st_local("0")))

	* Main syntax
	#d;
	syntax anything(id=varlist equalok) [if] [in] [aw pw fw/] , [

		/* Model */
		Absorb(string) NOAbsorb
		RESiduals(name) RESiduals2 /* use _reghdfe_resid */
		SUmmarize SUmmarize2(string asis) /* simulate implicit options */

		/* Standard Errors */
		VCE(string) CLuster(string)

		/* Diagnostic */
		Verbose(numlist min=1 max=1 >=-1 <=5 integer)
		TIMEit

		/* Speedup and memory Tricks */
		NOSAMPle /* do not save e(sample) */

		/* Undocumented */
		KEEPSINgletons
		OLD /* use latest v3 */
		NOTES(string) /* NOTES(key=value ...), will be stored on e() */
		
		] [*] /* capture optimization options, display options, etc. */
		;
	#d cr

	* Unused
	* SAVEcache
	* USEcache
	* CLEARcache
	* COMPACT /* use as little memory as possible but is slower */

	* Convert options to boolean
	if ("`verbose'" == "") loc verbose 0
	loc timeit = ("`timeit'"!="")
	loc drop_singletons = ("`keepsingletons'"=="")

	if (`timeit') timer on 29

	* Sanity checks
	if (`verbose'>-1 & "`keepsingletons'"!="") {
		loc url "http://scorreia.com/reghdfe/nested_within_cluster.pdf"
		loc msg "WARNING: Singleton observations not dropped; statistical significance is biased"
		di as error `"`msg' {browse "`url'":(link)}"'
	}
	if ("`cluster'"!="") {
		_assert ("`vce'"==""), msg("cannot specify both cluster() and vce()")
		loc vce cluster `cluster'
		loc cluster // clear it to avoid bugs in subsequent lines
	}

	* Parse Varlist
	ms_fvunab `anything'
	ms_parse_varlist `s(varlist)'
	loc base_varlist "`s(basevars)'"
	foreach cat in depvar indepvars endogvars instruments {
		loc original_`cat' "`s(`cat')'"
	}
	loc model = cond("`s(instruments)'" == "", "ols", "iv")
	loc original_varlist = "`s(varlist)'" // no parens or equal

	* Parse Weights
	if ("`weight'"!="") {
		unab exp : `exp', min(1) max(1) // simple weights only
	}

	* Parse VCE
	ms_parse_vce, vce(`vce') weighttype(`weight')
	loc vcetype = "`s(vcetype)'"
	loc num_clusters = `s(num_clusters)'
	loc clustervars = "`s(clustervars)'"
	loc base_clustervars = "`s(base_clustervars)'"
	loc vceextra = "`s(vceextra)'"

	* Select sample (except for absvars)
	loc varlist `original_varlist' `base_clustervars'
	tempvar touse
	marksample touse, strok // based on varlist + cluster + if + in + weight

	* Parse noabsorb
	_assert  ("`absorb'`noabsorb'" != ""), msg("option {bf:absorb()} or {bf:noabsorb} required")
	if ("`noabsorb'" != "") {
		_assert ("`absorb'" == ""), msg("{bf:absorb()} and {bf:noabsorb} are mutually exclusive")
		tempvar c
		gen byte `c' = 1
		loc absorb `c'
	}

	if (`timeit') timer off 29

	* Construct HDFE object
	// SYNTAX: fixed_effects(absvars | , touse, wtype, wtvar, dropsing, verbose)
	mata: st_local("comma", strpos(`"`absorb'"', ",") ? "" : ",")
	if (`timeit') timer on 20
	mata: HDFE = fixed_effects(`"`absorb' `comma' `options'"', "`touse'", "`weight'", "`exp'", `drop_singletons', `verbose')
	if (`timeit') timer off 20
	mata: HDFE.cmdline = "reghdfe " + st_local("0")
	loc options `s(options)'

	mata: st_local("N", strofreal(HDFE.N))
	if (`N' == 0) error 2000

	* Fill out HDFE object
	mata: HDFE.varlist = "`base_varlist'"
	mata: HDFE.original_depvar = "`original_depvar'"
	mata: HDFE.original_indepvars = "`original_indepvars'"
	mata: HDFE.original_endogvars = "`original_endogvars'"
	mata: HDFE.original_instruments = "`original_instruments'"
	mata: HDFE.original_varlist = "`original_varlist'"
	mata: HDFE.model = "`model'"

	mata: HDFE.vcetype = "`vcetype'"
	mata: HDFE.num_clusters = `num_clusters'
	mata: HDFE.clustervars = tokens("`clustervars'")
	mata: HDFE.base_clustervars = tokens("`base_clustervars'")
	mata: HDFE.vceextra = "`vceextra'"


	* Parse summarize
	if ("`summarize'" != "") {
		_assert ("`summarize2'" == ""), msg("summarize() syntax error")
		loc summarize2 mean min max  // default values
	}
	ParseSummarize `summarize2'
	mata: HDFE.summarize_stats = "`s(stats)'"
	mata: HDFE.summarize_quietly = `s(quietly)'


	* Parse residuals
	if ("`residuals2'" != "") {
		_assert ("`residuals'" == ""), msg("residuals() syntax error")
		loc residuals _reghdfe_resid
		cap drop `residuals' // destructive!
	}
	else if ("`residuals'"!="") {
		conf new var `residuals'
	}
	mata: HDFE.residuals = "`residuals'"


	* Parse misc options
	mata: HDFE.notes = `"`notes'"'
	mata: HDFE.store_sample = ("`nosample'"=="")
	mata: HDFE.timeit = `timeit'


	* Parse Coef Table Options (do this last!)
	_get_diopts diopts options, `options' // store in `diopts', and the rest back to `options'
	_assert (`"`options'"'==""), msg(`"invalid options: `options'"')
	if ("`hascons'"!="") di in ye "(option ignored: `hascons')"
	if ("`tsscons'"!="") di in ye "(option ignored: `tsscons')"
	mata: HDFE.diopts = `"`diopts'"'
end


program ParseSummarize, sclass
	sreturn clear
	syntax [namelist(name=stats)] , [QUIetly]
	local quietly = ("`quietly'"!="")
	sreturn loc stats "`stats'"
	sreturn loc quietly = `quietly'
end

// --------------------------------------------------------------------------

program Estimate, eclass
	ereturn clear

	* Parse and fill out HDFE object
	Parse `0'
	mata: st_local("timeit", strofreal(HDFE.timeit))

	* Compute degrees-of-freedom
	if (`timeit') timer on 21
	mata: HDFE.estimate_dof()
	if (`timeit') timer off 21

	* Save updated e(sample) (singletons reduce sample);
	* required to parse factor variables to partial out
	if (`timeit') timer on 29
	tempvar touse
	mata: HDFE.save_touse("`touse'")
	if (`timeit') timer off 29

	* Expand varlists
	if (`timeit') timer on 22
	// BUGBUG: do we really need HDFE.varlist ? or can we create it by concatenating the others?
	loc varlist
	foreach cat in /*varlist*/ depvar indepvars endogvars instruments {
		mata: st_local("vars", HDFE.original_`cat')
		if ("`vars'" == "") continue
		// HACK: addbn replaces 0.foreign with 0bn.foreign , to prevent st_data() from loading a bunch of zeros
		ms_fvstrip "`vars'" if `touse', expand dropomit addbn onebyone
		// If we don't use onebyone, then 1.x 2.x ends up as 2.x
		loc vars "`r(varlist)'"
		loc varlist `varlist' `vars'
		mata: HDFE.`cat' = "`vars'"
	}
	mata: HDFE.varlist = "`varlist'"
	if (`timeit') timer off 22

	* Stats
	mata: st_local("stats", HDFE.summarize_stats)
	if ("`stats'" != "") Stats

	* Condition number
	mata: HDFE.estimate_cond()

	* Partial out; save TSS of depvar
	if (`timeit') timer on 23
	mata: hdfe_variables = HDFE.partial_out(HDFE.varlist, 1) // 1=Save TSS of first var if HDFE.tss is missing
	if (`timeit') timer off 23

	* Regress
	mata: assert(HDFE.model=="ols")
	if (`timeit') timer on 24
	RegressOLS `touse'
	if (`timeit') timer off 24


	* (optional) Store FEs
	if (`timeit') timer on 29
	mata: st_local("save_any_fe", strofreal(HDFE.save_any_fe))
	assert inlist(`save_any_fe', 0, 1)
	if (`save_any_fe') {
		_assert e(depvar) != "", msg("e(depvar) is empty")
		_assert e(resid) != "", msg("e(resid) is empty")
		confirm numeric var `e(depvar)', exact
		confirm numeric var `e(resid)', exact
		tempvar d
		if (e(rank)) {
			qui _predict double `d' if e(sample), xb
		}
		else {
			gen double `d' = 0
		}
		qui replace `d' = `e(depvar)' - `d' - `e(resid)' if e(sample)
		mata: HDFE.store_alphas("`d'")
		drop `d'

		// Drop resid if we don't want to save it; and update e(resid)
		cap drop __temp_reghdfe_resid__
		if (!c(rc)) ereturn local resid
	}
	if (`timeit') timer off 29

	* View estimation tables
	mata: st_local("diopts", HDFE.diopts)
	Replay, `diopts'

	// ~~ Preserve relevant dataset ~~-
	// 
	// if (`compact') {
	// 	preserve
	// 	keep `varlist' `absorb'
	// 	loc N = c(N)
	// }
	// else {
	// 	qui cou if `touse'
	// 	loc N = r(N)
	// }

	if (`timeit') {
		di as text _n "{bf: Timer results:}"
		timer list
		di as text "Legend: 20: Create HDFE object; 21: Estimate DoF; 22: expand varlists; 23: partial out; 24: regress; 29: rest"
		di
	}
end


program RegressOLS, eclass
	args touse

	tempname b V N rank df_r
	mata: reghdfe_post_ols(HDFE, hdfe_variables, "`b'", "`V'", "`N'", "`rank'", "`df_r'")
	mata: st_local("indepvars", HDFE.indepvars)
	mata: hdfe_variables = .

	loc esample
	mata: st_local("store_sample", strofreal(HDFE.store_sample))
	if (`store_sample') loc esample "esample(`touse')"
	
	if ("`indepvars'" != "") {
		matrix colnames `b' = `indepvars'
		matrix colnames `V' = `indepvars'
		matrix rownames `V' = `indepvars'
		ereturn post `b' `V', `esample' buildfvinfo depname(`depvar') 
	}
	else {
		ereturn post, `esample' buildfvinfo depname(`depvar')
	}

	ereturn scalar N       = `N'
	ereturn scalar rank    = `rank'
	ereturn scalar df_r    = `df_r'
	ereturn local  cmd     "reghdfe"
	mata: HDFE.post(HDFE)

	* Post stats
	cap conf matrix reghdfe_statsmatrix
	if (!c(rc)) {
		ereturn matrix summarize = reghdfe_statsmatrix
		mata: st_local("summarize_quietly", strofreal(HDFE.summarize_quietly))
		ereturn scalar summarize_quietly = `summarize_quietly'
	}
end


program Replay, rclass
	syntax [, *]
	_get_diopts options, `options'
	reghdfe_header // _coef_table_header
	di ""
	_coef_table, `options' // ereturn display, `options'
	return add // adds r(level), r(table), etc. to ereturn (before the footnote deletes them)
	reghdfe_footnote

	* Replay stats
	if (e(summarize_quietly)==0) {
		di as text _n "{sf:Regression Summary Statistics:}" _c
		matlist e(summarize)', border(top bottom) rowtitle(Variable) // twidth(18) 
	}
end


program Stats
	* Optional weights
	mata: st_local("weight", sprintf("[%s=%s]", HDFE.weight_type, HDFE.weight_var))
	assert "`weight'" != ""
	if ("`weight'" == "[=]") loc weight
	loc weight : subinstr local weight "[pweight" "[aweight"

	mata: st_local("stats", HDFE.summarize_stats)
	mata: st_local("varlist", HDFE.varlist)
	mata: st_local("cvars", invtokens(HDFE.cvars))
	loc full_varlist `varlist' `cvars'

	qui tabstat `full_varlist' `weight' , stat(`stats') col(stat) save
	matrix reghdfe_statsmatrix = r(StatTotal)
end
