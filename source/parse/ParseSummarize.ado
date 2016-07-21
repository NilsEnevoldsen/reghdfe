cap pr drop ParseSummarize
pr ParseSummarize, sclass
	sreturn clear
	syntax [namelist(name=stats)] , [QUIetly]
	local quietly = ("`quietly'"!="")
	sreturn loc stats "`stats'"
	sreturn loc quietly = `quietly'
end
