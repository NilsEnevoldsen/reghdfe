cap pr drop LoadOptions
pr LoadOptions
	syntax namelist
	foreach key of local namelist {
		loc k REGHDFE.opt.`key'
		mata: st_local("val", isreal(`k') ? strofreal(`k') : `k')
		c_local `key' `val'
	}
end
