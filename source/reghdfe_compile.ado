// This file is just used to compile reghdfe.mlib

cap pr drop reghdfe_compile
pr reghdfe_compile
	args flavor
	if ("`flavor'" == "") loc flavor check

	* Check if we need to recompile
	if ("`flavor'" == "check") {
		cap mata: mata drop reghdfe_stata_version()
		loc compiled_with 0
		cap mata: st_local("compiled_with", reghdfe_stata_version())
		_assert inlist(`c(rc)', 0, 3499), msg("reghdfe check: unexpected error")
		if (`compiled_with' == c(stata_version)) exit
		* If we reach this point, we need to recompile
		local flavor compile
	}

	loc version = c(stata_version)
	clear mata

	* Delete previous versions; based on David Roodman's -boottest-
	loc mlib "lreghdfe.mlib"
	cap findfile "`mlib'"
	while !_rc {
	        erase "`r(fn)'"
	        cap findfile "`mlib'"
	}

	di as text "(compiling lreghdfe.mlib for Stata `version')"
	qui findfile "reghdfe.mata"
	loc fn "`r(fn)'"
	run "`fn'"
	loc path = c(sysdir_plus) + c(dirsep) + "l"
	cap {
		qui mata: mata mlib create lreghdfe  , dir("`path'") replace
		qui mata: mata mlib add lreghdfe *() , dir("`path'") complete
	}
	if (c(rc)) {
		// Exit with error but still save the file somewhere
		di as error `"could not save file in "`path'"; saving it in ".""'
		qui mata: mata mlib create lreghdfe  , dir(.) replace
		qui mata: mata mlib add lreghdfe *() , dir(.) complete
		qui findfile lreghdfe.mlib
		loc fn `r(fn)'
		di as text `"(library saved in `fn')"'
		exit 603
	}

	* Verify
	qui findfile lreghdfe.mlib
	loc fn `r(fn)'
	//mata: mata describe using lreghdfe
	qui mata: mata mlib index
	di as text `"(library saved in `fn')"'
end
