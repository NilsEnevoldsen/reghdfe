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
	mata: REGHDFE.opt.fast = `fast'
	mata: REGHDFE.opt.ffirst = `ffirst'
	mata: REGHDFE.opt.verbose = `verbose'
	mata: REGHDFE.opt.keepsingletons = ("`keepsingletons'" != "")
	mata: REGHDFE.opt.select_if = `"`if'"'
	mata: REGHDFE.opt.select_in = `"`in'"'
	mata: REGHDFE.opt.suboptions = `"`suboptions'"'
	mata: REGHDFE.opt.notes = `"`notes'"'
	mata: REGHDFE.opt.groupvar = `"`groupvar'"'

* Parse optimization options (stores directly in REGHDFE.opt)

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
	loc has_instruments = "`s(instruments)'" != ""

* Parse Estimaror (picks the estimation subcommand)

	ParseEstimator, has_instruments(`has_instruments') ///
					estimator(`estimator') ///
					ivsuite(`ivsuite')
	mata: REGHDFE.opt.estimator = "`s(estimator)'"
	mata: REGHDFE.opt.ivsuite = "`s(ivsuite)'"
	mata: REGHDFE.out.subcmd = "`s(subcmd)'"

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
	mata: REGHDFE.opt.summarize_quietly = "`s(quietly)'"

* Parse stages

	ParseStages stages(`stages') hasiv("`has_instruments'" != "")
	mataa: REGHDFE.opt.stages "`s(stages)'"
	mataa: REGHDFE.opt.stages_save = `s(savestages)'
	mataa: REGHDFE.opt.stages_opt "`s(stage_suboptions)'"

* Parse VCE 
	if (!`usecache') {
		ParseVCE, vce(`vce') weighttype(`weighttype') ivsuite(`ivsuite') model(`model')
	}


* Store remaining options



asdasd

* TODO:
* 1) finish storing the results of syntax above
* 2) see rest of old Parse file (ParseRem), update what's left

	* extended absvar expands ## and original doesnt??
	* equation_d predicts the sum of FEs with optional slope terms

* Show parsed options
	if (`verbose' > 0) ViewOptions
end


*	`S'.vce_is_hac = 0
* `S'.clustervars = = J(0,0,"")
* `S'.clustervars_original = J(0,0,"")
