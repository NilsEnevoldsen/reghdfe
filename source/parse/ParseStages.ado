capture program drop ParseStages
pr ParseStages, sclass
	syntax, model(string) [stages(string)]
	local 0 `stages'
	syntax [namelist(name=stages)], [noSAVE] [*]
	
	if ("`stages'"=="") local stages none
	if ("`stages'"=="all") local stages iv first ols reduced acid

	if ("`stages'"!="none") {
		_assert ("`model'" == "iv"), ///
			msg("{cmd:stages(`stages')} not allowed with ols")
		local special iv none
		local valid_stages first ols reduced acid
		local stages : list stages - special
		local wrong_stages : list stages - valid_stages
		_assert "`wrong_stages'"=="", msg("Error, invalid stages(): `wrong_stages'")
		* The "iv" stage will be always on for IV-type regressions
		local stages `stages' iv // put it last so it does the restore
	}

	sreturn local stages `stages'
	sreturn local stage_suboptions `options'
	sreturn local savestages = ("`save'"!="nosave" & "`stages'"!="none")
end
