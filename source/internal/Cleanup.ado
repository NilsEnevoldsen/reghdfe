capture program drop Cleanup
pr Cleanup
	syntax , [estimates]
	cap mata: mata drop REGHDFE
	
	// cap mata: mata drop HDFE_S
	// cap mata: mata drop varlist_cache
	// cap mata: mata drop tss_cache
	// cap global updated_clustervars
	// cap matrix drop reghdfe_statsmatrix

	if ("`estimates'" != "") {
		ereturn clear // Clear previous results; drop e(sample)
		cap estimates drop reghdfe_*
	}
end
