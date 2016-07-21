cap pr drop Parse
pr Parse
* This should parse and perform as many sanity checks as possible,
* but without modifying the dataset!

* Create new Mata object
	mata: REGHDFE = reghdfe_solver()
	InitMataOptions // default solver options

* Trim whitespace (caused by "///" line continuations; aesthetic only)
	mata: st_local("0", stritrim(`"`0'"') )
	mata: REGHDFE.out.cmdline = `"reghdfe `0'"'

* Main syntax

	#d;
	syntax anything(id=varlist equalok)
		[if] [in] [aw pw fw/] , [

		/* Model */

		Absorb(string)
		NOAbsorb
		RESiduals(name)
		SUmmarize SUmmarize2(string asis) /* simulate implicit options */
		SUBOPTions(string) /* gets passed to the e.g regress or ivreg2 */

		/* Standard Errors */

		VCE(string)
		CLuster(string) /* undocumented alternative to vce(cluster ...) */

		/* IV/2SLS/GMM */

		ESTimator(string) /* 2SLS GMM2s CUE LIML */
		STAGEs(string) /* iv (always on) first reduced ols acid (and all) */
		FFirst /* save first-stage stats (only with ivreg2) */
		IVsuite(string) /* ivreg2 ivregress */

		/* Diagnostic */

		Verbose(numlist min=1 max=1 >=0 <=5 integer)
		TIMEit

		/* Optimization (defaults are handled within Mata) */

		TOLerance(real 1e-8)
		MAXITerations(real 1e4)
		POOLsize(integer 10) /* process variables in batches of # */
		ACCELeration(string)
		TRAnsform(string)

		/* Speedup Tricks */

		CACHE(string)
		FAST

		/* Degrees-of-freedom Adjustments */

		DOFadjustments(string)
		GROUPVar(name) /*var with the first connected group between FEs*/

		/* Undocumented */

		KEEPSINgletons
		NOTES(string) /* NOTES(key=value ...), will be stored on e() */
		] [*] /* capture display options, etc. */
		;
	#d cr

* Quick sanity checks

	if ("`verbose'" == "") loc verbose 0
	loc timeit = ("`timeit'"!="")
	loc fast = ("`fast'"!="")
	loc ffirst = ("`ffirst'"!="")

	if ("`cluster'"!="") {
		_assert ("`vce'"==""), msg("cannot specify both cluster() and vce()")
		loc vce cluster `cluster'
		loc cluster // clear it to avoid bugs in subsequent lines
	}

* Store misc. options

	mata: REGHDFE.opt.timeit = `timeit'
	mata: REGHDFE.opt.ffirst = `ffirst'
	mata: REGHDFE.opt.verbose = `verbose'
	mata: REGHDFE.opt.keepsingletons = ("`keepsingletons'" != "")
	mata: REGHDFE.opt.select_if = `"`if'"'
	mata: REGHDFE.opt.select_in = `"`in'"'
	mata: REGHDFE.opt.suboptions = `"`suboptions'"'
	mata: REGHDFE.opt.notes = `"`notes'"'
	mata: REGHDFE.opt.groupvar = `"`groupvar'"'

* Parse optimization options (stores directly in REGHDFE)

	ParseOptimization, ///
		transform(`transform') acceleration(`acceleration') ///
		tolerance(`tolerance') maxiterations(`maxiterations') ///
		poolsize(`poolsize')

* Parse cache(save ...) and cache(use); run this early!

	ParseCache, cache(`cache') ifin(`if'`in') absorb(`absorb') vce(`vce')
	mata: REGHDFE.opt.savecache = `s(savecache)'
	mata: REGHDFE.opt.usecache = `s(usecache)'
	mata: REGHDFE.opt.keepvars = tokens("`s(keepvars)'")
	loc usecache `s(usecache)'
	loc savecache `s(savecache)'

* Parse varlist

	_fvunab `anything'
	loc base_varlist `s(basevars)'

	ParseVarlist `s(varlist)'
	mata: REGHDFE.opt.depvar = "`s(depvar)'"
	mata: REGHDFE.opt.indepvars = "`s(indepvars)'"
	mata: REGHDFE.opt.endogvars = "`s(endogvars)'"
	mata: REGHDFE.opt.instruments = "`s(instruments)'"
	mata: REGHDFE.opt.fe_format = "`s(fe_format)'"
	loc model = cond("`s(instruments)'" == "", "iv", "ols")

* Parse Estimator (picks the estimation subcommand)

	ParseEstimator, model(`model') ///
					estimator(`estimator') ///
					ivsuite(`ivsuite')
	mata: REGHDFE.opt.estimator = "`s(estimator)'"
	mata: REGHDFE.opt.ivsuite = "`s(ivsuite)'"
	mata: REGHDFE.out.subcmd = "`s(subcmd)'"
	loc ivsuite "`s(ivsuite)'" // used later

* Parse Weights

	ParseWeight, weight(`weight') exp(`exp')
	if (!`usecache') {
		mata: REGHDFE.opt.weight_var = "`s(weight_var)'"
		mata: REGHDFE.opt.weight_type = "`s(weight_type)'"
		mata: REGHDFE.opt.weight_exp = "`s(weight_exp)'"
	}
	else {
		* TODO
	}

* Parse Absvars

	if (`usecache') {
		// move to savecache?
		*mata: REGHDFE.opt.save_any_fe = 0
		*local save_any_fe 0
		*local N_hdfe : char _dta[N_hdfe]
		*local has_intercept : char _dta[has_intercept]
	}
	else if ("`noabsorb'" != "" | "`absorb'" == "_cons") {
		_assert  ("`absorb'" == ""), ///
			msg("{bf:absorb} and {bf:noabsorb} are mutually exclusive")
		mata: REGHDFE.out.N_hdfe = REGHDFE.G = 1
		mata: REGHDFE.opt.has_intercept = 1
		mata: REGHDFE.out.extended_absvars = "_cons"
		mata: REGHDFE.opt.noabsorb = 1
	}
	else {
		ParseAbsvars `absorb'
		* FE-specific results are stored in REGHDFE.fes[] !
		mata: REGHDFE.out.N_hdfe = REGHDFE.G = `s(N_hdfe)'
		mata: REGHDFE.out.equation_d = "`s(equation_d)'"
		mata: REGHDFE.out.extended_absvars = "`s(extended_absvars)'"
		mata: REGHDFE.opt.save_all_fe = `s(save_all_fe)'
		mata: REGHDFE.opt.save_any_fe = `s(save_any_fe)'
		mata: REGHDFE.opt.has_intercept = `s(has_intercept)'
		mata: REGHDFE.opt.noabsorb = 0
		loc base_absvars `s(basevars)'
		loc save_any_fe `s(save_any_fe)'
	}

* Parse summarize

	if ("`summarize'" != "") {
		_assert("`summarize2'" == ""), msg("summarize() syntax error")
		loc summarize2 mean min max  // default values
	}
	ParseSummarize `summarize2'
	mata: REGHDFE.opt.summarize_stats = "`s(stats)'"
	mata: REGHDFE.opt.summarize_quietly = `s(quietly)'

* Parse stages

	ParseStages, stages(`stages') model("`model'")
	mata: REGHDFE.opt.stages = "`s(stages)'"
	mata: REGHDFE.opt.stages_save = `s(savestages)'
	mata: REGHDFE.opt.stages_opt = "`s(stage_suboptions)'"

* Parse VCE

	if (!`usecache') {
		ParseVCE, vce(`vce') weighttype(`weighttype') ivsuite(`ivsuite') model(`model')
		loc ivsuite "`s(ivsuite)'"
	}

* Parse -ffirst- (save first stage statistics)

	if (`ffirst') {
		_assert ("`model'" != "ols"), ///
			msg("ols does not support {cmd}ffirst")
		_assert ("`ivsuite'" == "ivreg2"), ///
			msg("option {bf:ffirst} requires ivreg2")
	}
	mata: REGHDFE.opt.ffirst = `ffirst'
	
* DoF Adjustments

	if ("`dofadjustments'"=="") local dofadjustments all
	ParseDOF , `dofadjustments'
	if ("`groupvar'"!="") conf new var `groupvar'
	mata: REGHDFE.opt.dofadjustments = "`s(dofadjustments)'"
	mata: REGHDFE.opt.groupvar = "`s(groupvar)'"

* Parse residuals

	if ("`residuals'"!="") {
		_assert !`save_any_fe', ///
			msg("option residuals() is mutually exclusive with saving FEs")
		_assert !`savecache', ///
			msg("option residuals() is mutually exclusive with -savecache-")
		conf new var `residuals'
	}
	mata: REGHDFE.opt.residuals = "`residuals'"

* Parse speedups

	if (`fast' & ("`groupvar'"!="" | "`residuals'"!="" | `save_any_fe')) {
		di as error "(warning: option -fast- disabled; not allowed when saving variables such as FEs, mobility groups or residuals)"
		local fast 0
	}
	mata: REGHDFE.opt.fast = `fast'

* With -savecache-, this adds chars (modifies the dta!) so put it close to the end
* BUGBUG
/*	if (`savecache') {
		* Savecache "requires" a previous preserve, so we can directly modify the dataset
		Assert "`endogvars'`instruments'"=="", msg("cache(save) option requires a normal varlist, not an iv varlist")
		char _dta[reghdfe_cache] 1
		local chars absorb N_hdfe has_intercept original_absvars extended_absvars vce vceoption vcetype vcesuite vceextra num_clusters clustervars bw kernel dkraay kiefer twicerobust
		foreach char of local  chars {
			char _dta[`char'] ``char''	
		}
	}*/
* TODO: Store the chars in mata, just store a random hash in the dta!!!

* Parse Coef Table Options (do this last!)
	_get_diopts diopts options, `options' // store in `diopts', and the rest back to `options'
	_assert (`"`options'"'==""), ///
		msg(`"invalid options: `options'"')
	if ("`hascons'"!="") di in ye "(option ignored: `hascons')"
	if ("`tsscons'"!="") di in ye "(option ignored: `tsscons')"
	mata: REGHDFE.opt.diopts = `"`diopts'"'

	if (`verbose' > 0) ViewOptions
end
