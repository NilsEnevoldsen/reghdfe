
cap pr drop IGNORED
pr IGNORED
* THIS IS TOO AGRESSIVE:
* What if I set a row to missing.. it shouldn't trigger an error
* Maybe delay these checks!??!?! --> MOVE THEM TO WHEN WE CREATE TOUSE!!
		local weightvar `exp'
		local weighttype `weight'
		local weightexp [`weight'=`weightvar']

		* Check that weights are correct (e.g. with fweight they need to be integers)
		local num_type = cond("`weight'"=="fweight", "integers", "reals")
		local basenote "{txt}weight {res}`weightvar'{txt} can only contain strictly positive `num_type', but"
		local if_and "if"
		if ("`if'"!="") local if_and "`if' &"
		qui cou `if_and' `weightvar'<0
		Assert (`r(N)'==0), msg("`basenote' `r(N)' negative values were found!")  rc(402)
		qui cou `if_and' `weightvar'==0
		if (`r(N)'>0) di as text "`basenote' `r(N)' zero values were found (will be dropped)"
		qui cou `if_and' `weightvar'>=.
		if (`r(N)'>0) di as text "`basenote' `r(N)' missing values were found (will be dropped)"
		if ("`weight'"=="fweight") {
			qui cou `if_and' mod(`weightvar',1) & `weightvar'<.
			Assert (`r(N)'==0), msg("`basenote' `r(N)' non-integer values were found!" "{err} Stopping execution") rc(401)
		}
	}
	local allkeys `allkeys' weightvar weighttype weightexp
end
