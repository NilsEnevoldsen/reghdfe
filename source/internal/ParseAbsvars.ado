capture program drop ParseAbsvars
pr ParseAbsvars, sclass
	sreturn clear
	syntax anything(id="absvars" name=absvars equalok everything), [SAVEfe]

* Special case: noconstant
	if ("`absvars'" == "_cons") {
		* ...
		exit
	}
	
* Unabbreviate variables and trim spaces
	_fvunab `absvars', `noisily' target
	loc absvars `s(varlist)'
	loc base_absvars `s(basevars)'

* Count the number of absvars and initialize Mata vector
	loc G 0
	loc absvars_copy `absvars'
	while ("`absvars_copy'" != "") {
		loc ++G
		gettoken absvar absvars_copy : absvars_copy, bind
	}
	mata: REGHDFE.fes = reghdfe_fe(`G')

* For each absvar, get the ivars and cvars (slopes),
* and whether the absvar has an intercept (or only slopes)
	loc g 0
	loc any_has_intercept 0
	while ("`absvars'" != "") {
		loc ++g
		gettoken absvar absvars : absvars, bind

		* Optionally extract the name of the new target variable
		ParseTarget `absvar' // modifies `target' and `absvar'

		* Create a name for the target variable, if required
		...

		* Build the absvar equation
		...

		* Extract the intercept and slope elements of the absvar
		ParseAbsvar `absvar' // modifies `ivars' `cvars' `has_intercept'
		if (`has_intercept') loc any_has_intercept 1
		loc num_slopes : word count `cvars'

		* Create a nice canonical label for the absvar
		loc baselabel : subinstr loc ivars " " "#", all
		loc sep = cond(`has_intercept', "##", "#")
		if (`num_slopes' == 1) {
			loc label `baselabel'`sep'c.`cvars'
		}
		else {
			loc label `baselabel'`sep'c.(`cvars')
		}

		* Create an "extended" label that separates the cvars
		loc extended
		if (`has_intercept') loc extended `baselabel'
		foreach cvar of local cvars {
			loc extended `extended' `baselabel'#c.`cvar'
		}

		loc fe "mata: REGHDFE.fes[`g']"
		`fe'.order = `g'
		`fe'.num_slopes = `num_slopes'
		`fe'.has_intercept = `has_intercept'
		`fe'.varlabel = "`label'"
		`fe'.ivars = tokens("`ivars'")
		`fe'.cvars = tokens("`cvars'")
		`fe'.idvarname = sprintf("__ID%f__", `g')
		`fe'.extended_label = "`extended'"
		

		`fe'.levels = .
		`fe'.target = J(0,0,"")
		`fe'.is_clustervar = 0
		`fe'.in_clustervar = 0
		`fe'.nesting_clustervar = .
	}

	sreturn loc N_hdfe = `G'
	sreturn loc equation_d = "`equation_d'"
	sreturn loc save_fe = ("`savefe'"!="")
	sreturn loc has_intercept = `any_has_intercept'
end


cap pr drop ParseTarget
pr ParseTarget
	if strpos("`0'", "=") {
		gettoken target 0 : 0, parse("=")
		_assert ("`target'" != "")
		conf new var `target'
		gettoken eqsign 0 : 0, parse("=")
	}
	c_local absvar `0'
	c_local target `target'
end


cap pr drop ParseAbsvar
pr ParseAbsvar
	* Add i. prefix in case there is none
	loc hasdot = strpos("`0'", ".")
	loc haspound = strpos("`0'", "#")
	if (!`hasdot' & !`haspound') loc 0 i.`0'

	* Expand absvar:
	* x#c.z			--->							i.x#c.z
	* x##c.z		--->	i.x			z			i.x#c.z
	* x##c.(z w) 	--->	i.x			z		w 	i.x#c.z		i.x#c.w
	* x#y##c.z		--->	i.x#i.y 	z			i.x#i.y#c.z
	* x#y##c.(z w)	--->	i.x#i.y 	z		w	i.x#i.y#c.z	i.x#i.y#c.w
	syntax varlist(numeric fv)

	* Iterate over every factor of the expanded absvar
	loc has_intercept 0 // 1 if there is a "factor" w/out a "c." part
	foreach factor of loc varlist {
		if (!strpos("`factor'", ".")) continue // ignore the "z", "w" cases
		ParseFactor `factor' // modifies `factor_ivars' `factor_cvars'
		loc ivars `ivars' `factor_ivars'
		loc cvars `cvars' `factor_cvars'
		if ("`factor_cvars'" != "") loc has_intercept 1
	}

	loc ivars : list uniq ivars
	loc unique_cvars : list uniq cvars
	_assert ("`ivars'" != ""), ///
		msg("no indicator variables in absvar <`0'> (expanded to `varlist')")
	_assert (`: list unique_cvars == cvars'), ///
		msg("duplicated c. variable in absvar <`0'> (expanded to `varlist')")

	c_local ivars `ivars'
	c_local ivars `ivars'
	c_local cvars `cvars'
	c_local has_intercept `has_intercept'
end


cap pr drop ParseFactor
pr ParseFactor
	loc 0 : subinstr loc 0 "#" " ", all
	foreach part of loc 0 {
		_assert strpos("`part'", ".")
		loc first_char = substr("`part'", 1, 1)
		_assert inlist("`first_char'", "c", "i")
		gettoken prefix part : part, parse(".")
		gettoken dot part : part, parse(".")
		_assert ("`dot'" == ".")
		if ("`first_char'" == "c") {
			loc cvars `cvars' `part'
		}
		else {
			loc ivars `ivars' `part'
		}
	}
	c_local factor_ivars `ivars'
	c_local factor_cvars `cvars'
end
