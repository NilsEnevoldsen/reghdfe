// --------------------------------------------------------------------------
// Mata Code: Method of Alternating Projections with Acceleration
// --------------------------------------------------------------------------
// To debug mata code, uncomment these lines, and then -do- the file:
 discard
 pr drop _all
 clear all
 version `=clip(c(version), 11.2, 14.1)'

clear mata
include mata/reghdfe.mata

cap pr drop reghdfe_mata
pr reghdfe_mata
	mata: st_local("cmd", strproper(`"`1'"') )
	_assert inlist("`cmd'", "New", "Inspect", "Get")
	`cmd'
end

cap pr drop New
pr New
	mata: REGHDFE = reghdfe_solver()
end

cap pr drop Inspect
pr Inspect
	mata: REGHDFE.e.cmdline  = "asd"
	mata: REGHDFE.opt.fast = 1

	di as smcl "{txt}{title:Contents of REGHDFE}"
	InspectCat opt : fast
	InspectCat e   : cmdline
end

cap pr drop InspectCat
pr InspectCat
	_on_colon_parse `0'
	local cat `s(before)'
	local keys `s(after)'
	
	di as smcl "{txt}{bf:  REGHDFE.`cat'}"
	foreach key of local keys {
		cap mata: st_local("value", REGHDFE.`cat'.`key')
		local rc = c(rc)
		_assert inlist(`rc', 0, 3254)
		if (`rc'==3254) {
			mata: st_local("value", strofreal(REGHDFE.`cat'.`key'))
			di as smcl "{txt}    `key' = {res}`value'"
		}
		else if ("`value'" != "") {
			di as smcl `"{txt}    `key' = "{res}`value'{txt}""'
		}
	}	
end

cap pr drop Get
pr Get
	* reghdfe_mata get xyz abc foo bar -> retrieves into locals

end
