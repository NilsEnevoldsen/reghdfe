cap pr drop Inject
pr Inject
	syntax anything(everything equalok name=names), [from(string)]
	if ("`from'"=="") loc from REGHDFE.opt
	foreach name of local names {
		gettoken target rest : name, parse("=")
		if ("`rest'" != "") {
			gettoken eqsign name : rest, parse("=")
			assert "`eqsign'" == "="
		}
		loc val // ensure its empty
		cap mata: st_local("val", `from'.`name')
		if (c(rc)==3254) {
			cap mata: st_local("val", strofreal(`from'.`name'))
		}
		c_local `target' `val'
	}
end
