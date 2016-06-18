cap pr drop Parse
pr Parse
* This should parse and perform as many sanity checks as possible,
* but without modifying the dataset!

* Initialize mata structure (HDFE object)
	reghdfe_mata init

* Trim whitespace (caused by "///" line continuations; aesthetic only)
	mata: st_local("0", stritrim(`"`0'"') )
	mata: REGHDFE.e.cmdline = `"reghdfe `0'"'

* Main syntax

	#d;
	syntax anything(name=varlist equalok)
		[if] [in] [aw pw fw/] , [

		/* Model */

		Absorb(string)
		NOAbsorb
		RESiduals(name)
		SUmmarize SUmmarize_long /* (trick to simulate implicit options) */
		SUBOPTions(string) /* passed to the e.g regress or ivreg2 */

		/* Standard Errors */

		VCE(string)
		CLuster(string) /* undocumented alternative to vce(cluster ...) */

		/* IV/2SLS/GMM */

		ESTimator(string) /* 2SLS GMM2s CUE LIML */
		STAGEs(string) /* iv (always on) first reduced ols acid (and all) */
		FFirst /* save first-stage stats (only with ivreg2) */
		IVsuite(string) /* ivreg2 ivregress */

		/* Diagnostic */

		Verbose(string)
		TIMEit

		/* Optimization (defaults are handled within Mata) */

		TOLerance(string)
		MAXITerations(string)
		POOLsize(string) /* process variables in batches of # */
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

	local timeit = ("`timeit'"!="")
	local fast = ("`fast'"!="")
	local ffirst = ("`ffirst'"!="")

	mata: REGHDFE.opt.timeit = `timeit'
	mata: REGHDFE.opt.fast = `fast'
	mata: REGHDFE.opt.ffirst = `ffirst'
	mata: REGHDFE.opt.if = `"`if'"'
	mata: REGHDFE.opt.in = `"`in'"'

	if ("`cluster'"!="") {
		_assert ("`vce'"==""), msg("cannot specify both cluster() and vce()")
		local vce cluster `cluster'
		local cluster // clear it to avoid bugs in subsequent lines
	}

* Parse cache(save ...) and cache(use); run this early!

	ParseCache, cache(`cache') ifin(`if'`in') absorb(`absorb') vce(`vce')
	mata: REGHDFE.opt.savecache = "`s(savecache)'"
	mata: REGHDFE.opt.keepvars = "`s(keepvars)'"
	mata: REGHDFE.opt.usecache = "`s(usecache)'"

* Parse varlist

	_fvunab `varlist'
	local basevars `s(basevars)'

	ParseVarlist `s(varlist)'
	mata: REGHDFE.opt.depvar = "`s(depvar)'"
	mata: REGHDFE.opt.indepvars = "`s(indepvars)'"
	mata: REGHDFE.opt.endogvars = "`s(endogvars)'"
	mata: REGHDFE.opt.instruments = "`s(instruments)'"
	mata: REGHDFE.opt.fe_format = "`s(fe_format)'"

	ParseEstimator, has_instruments("`s(instruments)'" != "") ///
					estimator(`estimator') ivsuite(`ivsuite')
	mata: REGHDFE.opt.estimator = "`s(estimator)'"
	mata: REGHDFE.opt.ivsuite = "`s(ivsuite)'"
	mata: REGHDFE.e.subcmd = "`s(subcmd)'"

* Parse Weights
	ParseWeight, weight(`weight') exp(`exp')
	mata: REGHDFE.opt.weight_var = "`s(weight_var)'"
	mata: REGHDFE.opt.weight_type = "`s(weight_type)'"
	mata: REGHDFE.opt.weight_exp = "`s(weight_exp)'"

* Parse Absvars and optimization options
*	_fvunab `absorb' ??

end
