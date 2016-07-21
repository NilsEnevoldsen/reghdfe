capture program drop ParseCache
pr ParseCache, sclass
	syntax, [CACHE(string) IFIN(string) ABSORB(string) VCE(string)] 
	if ("`cache'"!="") {
		local 0 `cache'
		syntax name(name=opt id="cache option"), [KEEPvars(varlist)]
		* Use keepvars with clustervars or timevar+panelvar under HAC errors
		_assert inlist("`opt'", "save", "use"), ///
			msg("invalid cache() option: `opt'")
		* -clear- is also a valid option but it's intercepted earlier
	}

	local savecache = ("`opt'"=="save")
	local usecache = ("`opt'"=="use")
	local is_cache : char _dta[reghdfe_cache]
	local is_cache = ("`is_cache'" == "1")

	* Sanity checks on usecache
	if (`usecache') {
		local cache_obs : char _dta[cache_obs]
		local cache_absorb : char _dta[absorb]
		local cache_vce : char _dta[vce]

		_assert `is_cache', ///
			msg("cache(use) requires a previous cache(save) operation")
		_assert `cache_obs'==`c(N)', ///
			msg("dataset cannot change after cache(save)")
		_assert "`cache_absorb'"=="`absorb'", ///
			msg("cached dataset has different absorb()")
		_assert "`ifin'"=="", ///
			msg("cannot use if/in with cache(use)")
		_assert "`cache_vce'"=="`vce'", ///
			msg("cached dataset has a different vce()")
		_assert "`keepvars'"=="", ///
			msg("{bf:keepvars()} suboption requires {bf:cache(save)}")
	}

	if (`savecache') {
		_assert !`is_cache', ///
			msg("data already cached, did you meant cache(use)?")
	}

	local keys savecache keepvars usecache
	foreach key of local keys {
		sreturn local `key' ``key''
	}
end
