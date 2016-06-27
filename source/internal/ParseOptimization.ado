cap pr drop ParseOptimization
pr ParseOptimization
	syntax, poolsize(integer) tolerance(string) maxiterations(string) ///
		[transform(string) acceleration(string)]
	
	loc maxiterations = int(`maxiterations')
	if ("`transform'" == "") loc transform symmetric_kaczmarz
	if ("`acceleration'" == "") loc acceleration conjugate_gradient

	_assert `maxiterations' > 0
	_assert `tolerance' > 0
	_assert `poolsize' > 0

	* Abbreviations (cim --> cimmino)
	loc transform = lower("`transform'")
	if ("`transform'"=="cg") loc transform conjugate_gradient
	if ("`transform'"=="sd") loc transform steepest_descent
	loc transforms cimmino kaczmarz symmetric_kaczmarz rand_kaczmarz
	foreach x of local transforms {
		if (strpos("`x'", "`transform'")) loc transform `x'
	}
	_assert (`: list transform in transforms'), ///
		msg("invalid transform")

	loc acceleration = lower("`acceleration'")
	if ("`acceleration'"=="off") loc acceleration none
	loc accelerations conjugate_gradient steepest_descent aitken none hybrid
	foreach x of local accelerations {
		if (strpos("`x'", "`acceleration'")) loc acceleration `x'
	}
	_assert (`: list acceleration in accelerations'), ///
		msg("invalid acceleration")

	* Main options
	loc opt "mata: REGHDFE.opt"
	`opt'.maxiterations = `maxiterations'
	`opt'.tolerance = `tolerance'
	`opt'.poolsize = `poolsize'
	`opt'.transform = "`transform'"
	`opt'.acceleration = "`acceleration'"

	* Additional options
	`opt'.accel_start = 6

	* Specific to Aitken acceleration:
	`opt'.accel_freq = 3
	`opt'.pause_length = 20
	`opt'.bad_loop_threshold = 1
	`opt'.stuck_threshold = 5e-3
end
