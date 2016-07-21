cap pr drop ParseWeight
pr ParseWeight, sclass
	sreturn clear
	syntax [, weight(string) exp(string)]
	if ("`weight'"!="") {
		local weight_exp [`weight'=`exp']
		unab exp : `exp', min(1) max(1) // simple weights only
	}
	sreturn local weight_var "`exp'"
	sreturn local weight_type "`weight'"
	sreturn local weight_exp "`weight_exp'"
end
