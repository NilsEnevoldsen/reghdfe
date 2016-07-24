cap pr drop Compact
pr Compact, sclass

* Mark sample (uses -if-, -in- and -exp-)
* (can't drop vars before this because of -in- and -exp-)
	Inject if=select_if in=select_in exp=weight_exp
	marksample touse, novar

* Only keep required variables
	Inject uid_name panelvar timevar, from(REGHDFE)
	Inject base_varlist base_absvars base_clustervars weight_var keepvars
	keep `uid' `touse' `timevar' `panelvar' `weightvar' `keepvars' ///
		`base_varlist' `base_absvars' `base_clustervars'

* Expand factor and time-series variables
	mata: REGHDFE.opt.base_varlist = ""
	local sets depvar indepvars endogvars instruments // depvar MUST be first
	Debug, level(4) newline
	Debug, level(4) msg("{title:Expanding factor and time-series variables:}")
	foreach set of local sets {
		ExpandFactorVariables `set' if `touse'
	}

* Variables needed for savecache
	Inject new_varlist=base_varlist savecache
	if (`savecache') {
		local _ : list base_varlist - new_varlist
		local cachevars `timevar' `panelvar' `_'
		// BUGGBUG where do we store this??
		if ("`cachevars'"!="") Debug, level(0) msg("(cachevars: {res}`cachevars'{txt})")
	}

* We need to keep them with autocorrelation-robust VCE
	if ("`vceextra'"!="") local tsvars `panelvar' `timevar'

* Only keep required variables (drop unused base_vars and tsset vars)
	keep `uid' `touse' `tsvars' `weightvar' `keepvars' ///
		`new_varlist' `cachevars' `base_absvars' `base_clustervars'

* Convert absvar and clustervar string variables to numeric
* Note that this will still fail if we did absorb(i.somevar)
* BUGBUG: Do this with -ftools-
	*tempvar encoded
	*foreach var of varlist `absorb_keepvars' `cluster_keepvars' {
	*	local vartype : type `var'
	*	local is_string = substr("`vartype'", 1, 3) == "str"
	*	if (`is_string') {
	*		encode `var', gen(`encoded')
	*		drop `var'
	*		rename `encoded' `var'
	*		qui compress `var'
	*	}
	*}

* Mark out obs. with missing values
	markout `touse' `new_varlist' `base_absvars' `base_clustervars'

* Drop observations (make optional?)
	qui keep if `touse'

* Sanity checks
	Inject weight_var
	if ("`weight_var'"!="") assert `weight_var'>0 // marksample should have dropped those // if ("`weight_var'"!="") qui drop if (`weight_var'==0)
	_assert c(N)>0, rc(2000) msg("Empty sample, check for missing values or an always-false if statement")
	if ("`weight_var'"!="") {
		la var `weight_var' "[WEIGHT] `: var label `weight_var''"
	}
end
