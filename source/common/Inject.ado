cap pr drop Inject
pr Inject
	syntax namelist, [from(string)]
	if ("`from'"=="") loc from REGHDFE.opt
	foreach name of local namelist {
		cap mata: st_local("val", `from'.`name')
		if (c(rc)==3254) {
			cap mata: st_local("val", strofreal(`from'.`name'))
		}
		c_local `name' `val'
	}
end
