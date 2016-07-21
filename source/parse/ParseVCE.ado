capture program drop ParseVCE
pr ParseVCE
	syntax, model(string) [vce(string) weighttype(string) ivsuite(string)]
	loc 0 `vce'
	syntax 	[anything(id="VCE type")] , ///
			[bw(integer 1) KERnel(string) dkraay(integer 1) kiefer] ///
			[suite(string) TWICErobust]

	_assert (`bw'>0), msg("VCE bandwidth must be a positive integer")
	gettoken vcetype clustervars : anything
	* Expand variable abbreviations
	if ("`clustervars'"!="") {
		_fvunab `clustervars', stringok
		loc clustervars `s(varlist)'
	}

	* vcetype abbreviations:
	if (substr("`vcetype'",1,3)=="ols") local vcetype unadjusted
	if (substr("`vcetype'",1,2)=="un") local vcetype unadjusted
	if (substr("`vcetype'",1,1)=="r") local vcetype robust
	if (substr("`vcetype'",1,2)=="cl") local vcetype cluster
	if ("`vcetype'"=="conventional") local vcetype unadjusted // Conventional is the name given in e.g. xtreg
	_assert strpos("`vcetype'",",")==0, msg("Unexpected contents of VCE: <`vcetype'> has a comma")

	* Implicit defaults
	if ("`vcetype'"=="" & "`weighttype'"=="pweight") local vcetype robust
	if ("`vcetype'"=="") local vcetype unadjusted

	* Sanity checks on vcetype
	_assert inlist("`vcetype'", "unadjusted", "robust", "cluster"), ///
		msg("vcetype '`vcetype'' not allowed")

	_assert !("`vcetype'"=="unadjusted" & "`weighttype'"=="pweight"), ///
		msg("pweights do not work with vce(unadjusted), use a different vce()")
	* Recall that [pw] = [aw] + _robust http://www.stata.com/statalist/archive/2007-04/msg00282.html
	
	* Also see: http://www.stata.com/statalist/archive/2004-11/msg00275.html
	* "aweights are for cell means data, i.e. data which have been collapsed through averaging,
	* and pweights are for sampling weights"

	* Cluster vars
	local num_clusters : word count `clustervars'
	_assert inlist( (`num_clusters'>0) + ("`vcetype'"=="cluster") , 0 , 2), msg("Can't specify cluster without clustervars and viceversa") // XOR

	* VCE Suite
	local vcesuite `suite'
	if ("`vcesuite'"=="") local vcesuite default
	if ("`vcesuite'"=="default") {
		if (`bw'>1 | `dkraay'>1 | "`kiefer'"!="" | "`kernel'"!="") {
			local vcesuite avar
		}
		else if (`num_clusters'>1) {
			local vcesuite mwc
		}
	}

	_assert inlist("`vcesuite'", "default", "mwc", "avar"), msg("Wrong vce suite: `vcesuite'")

	if ("`vcesuite'"=="mwc") {
		cap findfile tuples.ado
		_assert !_rc , msg("error: -tuples- not installed, please run {stata ssc install tuples} to estimate multi-way clusters.")
	}
	
	if ("`vcesuite'"=="avar") { 
		cap findfile avar.ado
		_assert !_rc , msg("error: -avar- not installed, please run {stata ssc install avar} or change the option -vcesuite-")
	}

	* Some combinations are not coded
	_assert !("`ivsuite'"=="ivregress" & (`num_clusters'>1 | `bw'>1 | `dkraay'>1 | "`kiefer'"!="" | "`kernel'"!="") ), msg("option vce(`vce') incompatible with ivregress")
	_assert !("`ivsuite'"=="ivreg2" & (`num_clusters'>2) ), msg("ivreg2 doesn't allow more than two cluster variables")
	_assert !("`model'"=="ols" & "`vcesuite'"=="avar" & (`num_clusters'>2) ), msg("avar doesn't allow more than two cluster variables")
	_assert !("`model'"=="ols" & "`vcesuite'"=="default" & (`bw'>1 | `dkraay'>1 | "`kiefer'"!="" | "`kernel'"!="") ), msg("to use those vce options you need to use -avar- as the vce suite")
	if (`num_clusters'>0) local temp_clustervars " <CLUSTERVARS>"
	if (`bw'==1 & `dkraay'==1 & "`kernel'"!="") local kernel // No point in setting kernel here 
	if (`bw'>1 | "`kernel'"!="") local vceextra `vceextra' bw(`bw') 
	if (`dkraay'>1) local vceextra `vceextra' dkraay(`dkraay') 
	if ("`kiefer'"!="") local vceextra `vceextra' kiefer 
	if ("`kernel'"!="") local vceextra `vceextra' kernel(`kernel')
	if ("`kernel'" == "") {
		loc bw 0
		loc dkraay 0
	}
	if ("`vceextra'"!="") local vceextra , `vceextra'
	local vceoption "`vcetype'`temp_clustervars'`vceextra'" // this excludes "vce(", only has the contents

* Parse -twicerobust-
	* If true, will use wmatrix(...) vce(...) instead of wmatrix(...) vce(unadjusted)
	* The former is closer to -ivregress- but not exact, the later matches -ivreg2-
	
	local twicerobust = ("`twicerobust'"!="")
	loc opt "mata: REGHDFE.opt"
	`opt'.vceoption = "`vceoption'"
	`opt'.vcetype = "`vcetype'"
	`opt'.vcesuite = "`vcesuite'"
	`opt'.vceextra = "`vceextra'"
	`opt'.vce_is_hac = "`vceextra'" != ""
	`opt'.num_clusters = `num_clusters'
	`opt'.clustervars = "`clustervars'"
	`opt'.bw = `bw'
	`opt'.kernel = "`kernel'"
	`opt'.dkraay = `dkraay'
	`opt'.twicerobust = `twicerobust'
	`opt'.kiefer = "`kiefer'"
end

/*
- Note: bw=1 *usually* means just do HC instead of HAC
- BUGBUG: It is not correct to ignore the case with "bw(1) kernel(Truncated)"
  but it's too messy to add -if-s everywhere just for this rare case
  (see also Mark Schaffer's email)
*/
