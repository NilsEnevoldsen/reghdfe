capture program drop ParseAbsvars
pr ParseAbsvars, sclass
	sreturn clear
	syntax anything(id="absvars" name=absvars equalok everything), [SAVEfe]
	
* Unabbreviate variables and trim spaces
	_fvunab `absvars', `noisily' target
	loc absvars `s(varlist)'
	if ("`noisily'" != "") sreturn list

* For each absvar, get the ivars and cvars (slopes),
* and whether the absvar has an intercept (or only slopes)
	loc g 0
	loc all_cvars
	loc all_ivars
	loc any_has_intercept 0
	
	while ("`absvars'" != "") {
		loc ++g
		gettoken absvar absvars : absvars, bind
		ParseAbsvar `absvar'
	}
end

cap pr drop ParseAbsvar
pr ParseAbsvar
	ParseTarget `0' // writes in `factor' and `0'

	* Add i. prefix in case there is none
	loc hasdot = strpos("`0'", ".")
	loc haspound = strpos("`0'", "#")
	if (!`hasdot' & !`haspound') loc 0 i.`0'

	* Expand x##c.(y z) into i.x i.x#c.y i.x#c.z
	syntax varlist(numeric fv)

	* Iterate over every factor of the expanded absvar
	loc ivars // vars prefixed with i. (or "ib40.", etc. with fvset)
	loc cvars // vars prefixed with c.
	loc has_intercept 0 // 1 for turn and turn##c.gear , 0 for turn#c.gear
	foreach factor of loc varlist {
		ParseFactor `factor'
	}
end

cap pr drop ParseTarget
pr ParseTarget
	if strpos("`0'", "=") {
		gettoken target 0 : 0, parse("=")
		_assert ("`target'" != "")
		conf new var `target'
		gettoken eqsign 0 : 0, parse("=")
	}
	c_local 0 `0'
	c_local target `target'
end

cap pr drop ParseFactor
pr ParseFactor
	loc 0 : subinstr loc 0 "#" " ", all
	loc hascvars 0
	foreach part of loc 0 {
		_assert strpos("`part'", ".")
		loc first_char = substr("`part'", 1, 1)
		_assert inlist("`first_char'", "c", "i")
		gettoken prefix part : part, parse(".")
		gettoken dot part : part, parse(".")
		_assert ("`dot'" == ".")
		if ("`first_char'" == "i") {
			loc hascvars 1
			loc cvars `cvars' `part'
		}
		else {
			loc ivars `ivars' `part'
		}
	}
	if (!`hascvars') {
		loc has_intercept 1
	}

end

		
		
		loc ivars : list uniq ivars
		loc num_slopes : word count `cvars'
		_assert "`ivars'"!="", msg("error parsing absvars: no indicator variables in absvar <`absvar'> (expanded to `varlist')")
		loc unique_cvars : list uniq cvars
		_assert (`: list unique_cvars == cvars'), msg("error parsing absvars: factor interactions such as i.x##i.y not allowed")

		loc all_cvars `all_cvars' `cvars'
		loc all_ivars `all_ivars' `ivars'

		if (`has_intercept') loc any_has_intercept 1

		sreturn loc target`g' `target'
		sreturn loc ivars`g' `ivars'
		sreturn loc cvars`g' `cvars'
		sreturn loc has_intercept`g' = `has_intercept'
		sreturn loc num_slopes`g' = `num_slopes'
	
		loc label : subinstr loc ivars " " "#", all
		if (`num_slopes'==1) {
			loc label `label'#c.`cvars'
		}
		else if (`num_slopes'>1) {
			loc label `label'#c.(`cvars')
		}
		sreturn loc varlabel`g' `label'
	
	}
	
	loc all_ivars : list uniq all_ivars
	loc all_cvars : list uniq all_cvars

	sreturn loc G = `g'
	sreturn loc savefe = ("`savefe'"!="")
	sreturn loc all_ivars `all_ivars'
	sreturn loc all_cvars `all_cvars'
	sreturn loc has_intercept = `any_has_intercept' // 1 if the model is not a pure-slope one
end
