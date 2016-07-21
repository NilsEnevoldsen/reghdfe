cap pr drop InitMataOptions
pr InitMataOptions
	loc S "mata: REGHDFE"

	* Time identifier
	local panelvar `_dta[_TSpanel]'
	if ("`panelvar'"!="") {
		cap conf var `panelvar'
		if (c(rc)==111) local panelvar // It might have been deleted
		`S'.panelvar = "`panelvar'"
	}

	* Panel identifier
	local timevar `_dta[_TStvar]'
	if ("`timevar'"!="") {
		cap conf var `timevar'
		if (c(rc)==111) local timevar // It might have been deleted
		`S'.timevar = "`timevar'"
	}

	* Note:
	* If clustering by timevar or panelvar and VCE is HAC,
	* then we CANNOT touch the clustervars to create compact ids!

	`S'.N = . // Number of obs after removing singletons, MVs, etc.
	`S'.C = 0 // Number of cluster vars
	`S'.groupvar = "" // Initialize as empty
	`S'.grouptype = "" // Initialize as empty
	`S'.sortedby = "" // Initialize as empty (prevents bugs if we change the dataset before map_precompute)
end
