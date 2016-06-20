capture program drop ParseAbsvars
pr ParseAbsvars, sclass
	sreturn clear
	syntax anything(id="absvars" name=absvars equalok everything), ///
		[SAVEfe NOIsily]
	
* STEPS

	* 1. Split absvars
	* 2. Expand each into factors
	* 3. Split each into parts

* Unabbreviate and trim spaces

	_fvunab `absvars', noi target
	loc absvars `s(varlist)'
	sreturn list

* Count and parse each absvar

	loc g 0
	loc all_cvars
	loc all_ivars
	loc any_has_intercept 0
	
	while ("`absvars'" != "") {
		loc ++g
		gettoken absvar absvars : absvars, bind

		* Parse target variable
		loc target
		if strpos("`absvar'", "=") {
			gettoken target absvar : absvar, parse("=")
			_assert ("`target'" != "")
			conf new var `target'
			gettoken eqsign absvar : absvar, parse("=")
		}

		* Add i. prefix in case there is none
		loc hasdot = strpos("`absvar'", ".")
		loc haspound = strpos("`absvar'", "#")
		if (!`hasdot' & !`haspound') loc absvar i.`absvar'

		* Expand x##c.(y z) into i.x i.x#c.y i.x#c.z
		local 0 `absvar'
		syntax varlist(numeric fv)
		
		loc ivars // vars prefixed with i. (or "ib40.", etc. with fvset)
		loc cvars // vars prefixed with c.
		loc has_intercept 0 // is there a factor without c.?

		foreach factor of loc varlist {
			loc factor : subinstr loc factor "#" " ", all
			loc hascvars 0
			foreach part of loc factor {
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
		}
		
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
