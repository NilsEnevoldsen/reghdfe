cap pr drop ParseEstimator
pr ParseEstimator, sclass
	sreturn clear
	syntax, has_instruments(string) [ivsuite(string) estimator(string)]
	if (`has_instruments') {
		if ("`ivsuite'"=="") local ivsuite ivreg2 // Set default
		_assert inlist("`ivsuite'","ivreg2","ivregress") , ///
			msg("error: wrong IV routine (`ivsuite'), valid options are -ivreg2- and -ivregress-")
		cap findfile `ivsuite'.ado
		_assert !_rc , msg("error: -`ivsuite'- not installed, please run {stata ssc install `ivsuite'} or change the option 	-ivsuite-")
		local subcmd `ivsuite'

		if ("`estimator'"=="") local estimator 2sls // Set default
		if (substr("`estimator'", 1, 3)=="gmm") local estimator gmm2s
		_assert inlist("`estimator'", "2sls", "gmm2s", "liml", "cue"), ///
			msg("reghdfe error: invalid estimator `estimator'")
		if ("`estimator'"=="cue") Assert "`ivsuite'"=="ivreg2", ///
			msg("reghdfe error: estimator `estimator' only available with the ivreg2 command, not ivregress")
		if ("`estimator'"=="cue") di as text "(WARNING: -cue- estimator is not exact, see help file)"
	}
	else {
		local subcmd regress
		_assert "`estimator'"=="", msg("estimator() requires an instrumental-variable regression")
	}

	sreturn local ivsuite `ivsuite'
	sreturn local subcmd `subcmd'
	sreturn local estimator `estimator'
end
