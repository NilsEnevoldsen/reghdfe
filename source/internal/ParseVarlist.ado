cap pr drop ParseVarlist
pr ParseVarlist, sclass
	sreturn clear
	syntax anything(id="varlist" name=0 equalok)

	* SYNTAX: depvar indepvars [(endogvars = instruments)]
		 * depvar		: 	dependent variable
		 * indepvars	: 	included exogenous regressors
		 * endogvars	: 	included endogenous regressors
		 * instruments	: 	excluded exogenous regressors

	* NOTE: 
		* This must be run AFTER _fvunab

	ParseDepvar `0'
		* STORE: s(depvar) s(fe_format)
		* ALSO: s(rest)
	
	ParseIndepvars `s(rest)'
		* STORE: s(indepvars)
		* CLEAR: s(rest)
		* ALSO: s(parens)

	ParseEndogAndInstruments `s(parens)'
		* STORE: s(endogvars) s(instruments)
		* CLEAR: s(parens)
end

cap pr drop ParseDepvar
pr ParseDepvar, sclass
	gettoken depvar 0 : 0, bind
	fvexpand `depvar'
	local depvar `r(varlist)'
	local n : word count `depvar'
	_assert (`n'==1), msg("more than one depvar specified: `depvar'")
	sreturn local depvar `depvar'
	sreturn local rest `0'

* Extract format of depvar so we can format FEs like this
	fvrevar `depvar', list
	local fe_format : format `r(varlist)' // The format of the FEs that will be saved
	sreturn local fe_format `fe_format'
end

cap pr drop ParseIndepvars
pr ParseIndepvars, sclass
	while ("`0'" != "") {
		gettoken _ 0 : 0, bind match(parens)
		if ("`parens'" == "") {
			local indepvars `indepvars' `_'
		}
		else {
			continue, break
		}
	}
	sreturn local indepvars `indepvars'
	if ("`parens'" != "") sreturn local parens "`_'"
	_assert "`0'" == "", msg("couldn't parse the end of the varlist: <`0'>")
	sreturn local rest // clear
end

cap pr drop ParseEndogAndInstruments
pr ParseEndogAndInstruments, sclass
	if ("`0'" == "") exit
	gettoken _ 0 : 0, bind parse("=")
	if ("`_'" != "=") {
		sreturn local endogvars `_'
		gettoken equalsign 0 : 0, bind parse("=")
	}
	sreturn local instruments `0'
	sreturn local parens // clear
end
