cap pr drop Compact
pr Compact, sclass
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
