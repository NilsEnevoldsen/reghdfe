capture program drop reghdfe
pr reghdfe
	version `=clip(c(version), 11.2, 14.1)'

* Intercept -version-
	cap syntax, version [*]
	if !c(rc) {
		Version, `options'
		exit
	}

* Intercept -cache(save)-
	cap syntax anything(everything) [fw aw pw/], [*] CACHE(string)
	if (strpos("`cache'", "save")==1) {
		cap noi InnerSaveCache `0'
		if (c(rc)) {
			local rc = c(rc)
			Cleanup
			exit `rc'
		}
		exit
	}

* Intercept -cache(use)-
	cap syntax anything(everything) [fw aw pw/], [*] CACHE(string)
	if ("`cache'"=="use") {
		InnerUseCache `0'
		exit
	}

* Intercept -cache(clear)-
	cap syntax, CACHE(string)
	if ("`cache'"=="clear") {
		Cleanup
		exit
	}

* Intercept replays; must be at the end
	if replay() {
		if (`"`e(cmd)'"'!="reghdfe") error 301
		if ("`0'"=="") local comma ","
		Replay `comma' `0' stored // also replays stored regressions (first stages, reduced, etc.)
		exit
	}

* Finally, call Inner if not intercepted before
	local is_cache : char _dta[reghdfe_cache]
	Assert ("`is_cache'"!="1"), msg("reghdfe error: data transformed with -savecache- requires option -usecache-")
	Cleanup, estimates
	cap noi Inner `0'
	if (c(rc)) {
		local rc = c(rc)
		Cleanup, estimates
		exit `rc'
	}
end

// --------------------------------------------------------------------------
include "common/Debug.ado"
include "common/Version.ado"
include "common/Tic.ado"
include "common/Toc.ado"

include "internal/Parse.ado"
	include "common/_fvunab.ado"
	include "internal/ParseAbsvars.ado"
	include "internal/ParseCache.ado"
	include "internal/ParseDOF.ado"
	include "internal/ParseEstimator.ado"
	include "internal/ParseOptimization.ado"
	include "internal/ParseStages.ado"
	include "internal/ParseSummarize.ado"
	include "internal/ParseVarlist.ado"
	include "internal/ParseVCE.ado"
	include "internal/ParseWeight.ado"

include "internal/Cleanup.ado"

/*
include "internal/Inner.ado"
	include "internal/GenerateUID.ado"
	include "internal/Compact.ado"
		include "internal/ExpandFactorVariables.ado"
	include "internal/Prepare.ado"
	include "internal/Stats.ado"
	include "internal/JointTest.ado"
	include "internal/Wrapper_regress.ado"
		include "internal/RemoveCollinear.ado"
	include "internal/Wrapper_avar.ado"
	include "internal/Wrapper_mwc.ado"
	include "internal/Wrapper_ivreg2.ado"
	include "internal/Wrapper_ivregress.ado"
		include "internal/GenerateID.ado"
	include "internal/SaveFE.ado"
	include "internal/Post.ado"
		include "internal/FixVarnames.ado"
		include "internal/Subtitle.ado"
	include "internal/Attach.ado"
include "internal/Replay.ado"
	include "internal/Header.ado"
include "internal/InnerSaveCache.ado"
include "internal/InnerUseCache.ado"
// --------------------------------------------------------------------------
*/
