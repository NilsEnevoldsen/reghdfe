// -------------------------------------------------------------------------------------------------
// Mata Code: Method of Alternating Projections with Acceleration
// -------------------------------------------------------------------------------------------------
	// To debug the mata code, uncomment this three lines, and then -do- the file
	//discard
	//pr drop _all
	//clear all

* Type Aliases
	local Boolean 		real scalar
	local Integer 		real scalar
	local Real 			real scalar
	local Vector		real colvector
	local Matrix		real matrix
	local Series		real colvector // Should be N*1
	local Group			real matrix // Should be N*K
	local String 		string scalar
	local Varname 		string scalar
	local Varlist 		string rowvector // rowvector so they match tokens()
	local Problem		struct MapProblem scalar
	local FE			struct FixedEffect scalar
	local FunctionPointer pointer(`Group' function) scalar // Used for the Accelerate & Transform fns

// -------------------------------------------------------------------------------------------------
	
mata:
mata set matastrict on
	void assert_msg(real scalar t, | string scalar msg)
	{
		if (args()<2 | msg=="") msg = "assertion is false"
	        if (t==0) _error(msg)
	}
	
// -------------------------------------------------------------------------------------------------
// Structure of a Fixed Effect
// -------------------------------------------------------------------------------------------------

	struct FixedEffect {
		`Integer'	order 			// "g", the position in varlist
		`Varname'	varlabel		// Original label of this absvar
		`Integer'	num_slopes
		`Integer'	has_intercept
		`Integer'	levels			// Number of categories spanned by the ivars
		`Varlist'	ivars			// number of i.var elements
		`Varlist'	cvars			// number of c.var elements or slopes
		`Boolean'	is_sortedby		// 1 if the dataset is sorted by the ivars of this FE
		`Varname'	idvarname		// (optional) Name of variable with the absvar categories
		`Varlist'	target			// Name of the variable that will hold the estimates for the FE
		
		`Series'	p 				// Permutation vector
		`Series'	inv_p 			// Precompute invorder(p) because we'll use it a lot

		`Vector'	offsets			// Pos. of last obs. with that category (when sorted)
		`Vector'	counts			// number of obs. (weighted) with that value
		`Group'		x				// Vector/Matrix of (optionally demeaned) cvars
		`Matrix'	inv_xx			// Blocks of the inv(x'x) matrix; size KL*K (k=num_slopes, L=levels)
		`Matrix'	xmeans

		`Boolean'	is_clustervar, in_clustervar
		`Integer'	nesting_clustervar // Clustervar that nests this FE, if any

		// Temporary matrices for the stored FEs
		`Matrix'	alphas
		`Matrix'	tmp_alphas
	}
	
// -------------------------------------------------------------------------------------------------
// Structure of the MAP Problem
// -------------------------------------------------------------------------------------------------

struct MapProblem {
	struct FixedEffect vector fes	// The G*1 vector of FE structures
	`Integer'		G 				// Number of FEs when bunching slopes
	`Boolean'		has_intercept   // 1 if the model is not a pure-slope one
	`Varname'		weightvar 		// Name variable contaning the fw/pw/aw
	`String'		weighttype 		// fw/pw/aw
	`String'		weights 		// "[weighttype=weightvar]"
	`Series'		w 				// Contents of variable contaning the fw/pw/aw
	`Integer'		verbose			// Number of debug messages to show (0=None, 1=A little, 4=A *lot*)			
	`Integer'		N				// Number of obs; after map_precompute() the dataset CANNOT CHANGE!
	`Varlist'		keepvars		// By default we drop cvars and ivars ASAP; this prevents it (useful for clustervars and for timevar+panelvar under HAC errors)

	`Boolean'		will_save_fe	// True if at least one FE will be saved
	`Boolean'		keepsingletons	// If set to 1, it will not drop singletons (do not touch this!)

	`Integer'		C				// Number of cluster variables
	`Varlist'		clustervars
	`Varlist'		clustervars_original // Note: need to apply tokens()
	`Varname'		panelvar
	`Varname'		timevar
	`Boolean'		vce_is_hac

	`Boolean'		timeit
	`Varlist'		sortedby		// Variables on which the dataset is sorted (if anything)
	
	// Optimization parameters	
	`Integer'		poolsize 		// Group variables when demeaning (more is faster but uses more memory)
	`Real'			tolerance
	`Integer'		maxiterations
	`String'		transform		// Kaczmarz Cimmino Symmetric_kaczmarz (k c s)
	`String'		acceleration	// Acceleration method. None/No/Empty is none\
	`Integer'		accel_start		// Iteration where we start to accelerate // set it at 6? 2?3?
	
	// Specific to Aitken's acceleration
	`Integer'		accel_freq		
	`Integer'		stuck_threshold	// Call the improvement "slow" when it's less than e.g. 1%
	`Integer'		bad_loop_threshold	// If acceleration seems stuck X times in a row, pause it
	`Integer'		pause_length	// This is in terms of candidate accelerations, not iterations (i.e. x3)?

	// Temporary
	`Boolean'		storing_betas
	`Varname'		groupvar		// Name of the variable that will hold the mobility group
	`Varname'		grouptype		// Long, double, etc.
	`Varname'		grouplabel
	`Series'		groupseries		// The actual data of the mobility group variable
	`Series'		uid
	`Series'		resid
	`Varname'		residname
	`Integer'		num_iters_last_run
	`Integer'		num_iters_max

	// Temporary storage for DoFs
	`Integer'		dof_M
	`Integer'		dof_M_due_to_nested
	`Integer'		dof_KminusM
	`Integer'		dof_N_hdfe_extended
	`Vector'		doflist_M
	`Vector'		doflist_M_is_exact
	`Vector'		doflist_M_is_nested
	`Vector'		dof_SubGs
}
	
real rowvector safe_divide(real rowvector numerator, real rowvector denominator, | real scalar epsi) {
	 // If the denominator goes below machine precision, the division explodes
	 if (args()<3) epsi = epsilon(1)
	return( numerator :/ colmax(denominator \ J(1,cols(denominator),epsi)) )
}

// -------------------------------------------------------------------------------------------------

void verbose2local(`Problem' S, string scalar loc) {
	st_local(loc, strofreal(S.verbose))
}

// -------------------------------------------------------------------------------------------------

void function store_uid(`Problem' S, `Varname' varname) {
	S.uid = st_data(., varname)
	assert_msg(rows(S.uid)==S.N, "assertion failed: rows(S.uid)==S.N")
}

void function drop_uid(`Problem' S) {
	S.uid = J(0,0,.)
}

// -------------------------------------------------------------------------------------------------

void function store_resid(`Problem' S, `Varname' varname) {
	S.resid = st_data(., varname)
	S.residname = varname
	assert_msg(rows(S.resid)==S.N, "assertion failed: rows(S.resid)==S.N")
}

void function resid2dta(`Problem' S, `Boolean' original_dta, `Boolean' cleanup) {
	if (original_dta) {
		st_store(S.uid, st_addvar("double", S.residname), S.resid)
	}
	else {
		st_store(., st_addvar("double", S.residname), S.resid)
	}

	if (cleanup) {
		S.resid = J(0,0,.)
		S.residname = ""
	}	
}

// -------------------------------------------------------------------------------------------------

void function groupvar2dta(`Problem' S, | `Boolean' original_dta) {
	if (args()<2) original_dta = 1
	
	// If grouptype has not been set, that's because there was no need to
	// EG: Only one FE, or two FEs but one is the clustervar
	if (S.grouptype!="") {
		if (S.verbose>2) printf("{txt}    - Saving identifier for the first mobility group: {res}%s\n", S.groupvar)
		
		if (original_dta) {
			st_store(S.uid, st_addvar(S.grouptype, S.groupvar), S.groupseries)
			S.groupseries = J(0,0,0)
		}
		else {
			st_store(., st_addvar(S.grouptype, S.groupvar), S.groupseries)
		}

		st_varlabel(S.groupvar, S.grouplabel)
	}
	else {
		if (S.verbose>=0) printf("{txt}Note: mobility group not saved as there was no need to compute it (e.g. there are less than two absvars not nested within a cluster)\n")
	}
}

// -------------------------------------------------------------------------------------------------

void function drop_ids(`Problem' S) {
	`Integer' g
	for (g=1;g<=S.G;g++) {
		if (!S.fes[g].is_clustervar & S.fes[g].target=="") st_dropvar(S.fes[g].idvarname)
	}
}

// -------------------------------------------------------------------------------------------------

void function esample2dta(`Problem' S, `Varname' esample) {
	assert(length(S.uid)>0)
	st_store(S.uid, st_addvar("byte", esample), J(rows(S.uid),1,1) )
}

// -------------------------------------------------------------------------------------------------

// Copy the fixed effect estimates (the alphas back into the original dataset)
void function alphas2dta(`Problem' S) {
	`Integer' g, i
	`Varlist' target
	`String' varlabel
	assert(S.will_save_fe==1)
	if (S.verbose>1) printf("{txt}    - Storing fixed effects in the original dataset\n")
	for (g=1; g<=S.G; g++) {
		target = S.fes[g].target
		if (length(target)>0) {
			st_store(S.uid, st_addvar("double", target), S.fes[g].alphas)
			S.fes[g].alphas = J(0,0,0)
			for (i=1; i<=length(target);i++) {
				varlabel = invtokens(S.fes[g].ivars, "#")
				if (i>1 | !S.fes[g].has_intercept) varlabel = varlabel + "#c." + S.fes[g].cvars[i-S.fes[g].has_intercept]
				st_varlabel(target[i], sprintf("[FE] %s", varlabel))
			}
		}
	}
}
	
//  Parse absvars and initialize the almost empty MapProblem struct
`Problem' function map_init()
{
	`Integer'		g, G, num_slopes, has_intercept, i, H, j
	`Problem' 		S
	`Boolean'		auto_target // Automatically assign target names to all FEs
	`Varname'		basetarget
	`Varlist'		target, original_absvars, extended_absvars
	`String'		equation_d
	`Boolean'		equation_d_valid
	pointer(`FE') 	fe

	S.weightvar = S.weighttype = S.weights = ""
	S.verbose = 0
	S.transform = "symmetric_kaczmarz" // cimmino ?
	S.acceleration = "conjugate_gradient"
	S.tolerance = 1e-8
	S.maxiterations = 1e4
	S.accel_start = 6
	S.poolsize = 10

	// If clustering by timevar or panelvar and VCE is HAC, we CANNOT touch the clustervars to create compact ids!
	S.timevar = ""
	S.panelvar = ""
	S.vce_is_hac = 0

	// Specific to Aitken:
	S.accel_freq = 3
	S.pause_length = 20
	S.bad_loop_threshold = 1
	S.stuck_threshold = 5e-3
	S.N = .

	S.groupvar = "" // Initialize as empty
	S.grouptype = "" // Initialize as empty
	S.sortedby = "" // Initialize as empty (prevents bugs if we change the dataset before map_precompute)


	S.keepsingletons = 0
	S.G = G = st_numscalar("r(G)")
	S.has_intercept = st_numscalar("r(has_intercept)")
	S.C = 0
	S.clustervars = S.clustervars_original = J(0,0,"")
	S.fes = FixedEffect(G)
	S.will_save_fe = 0
	auto_target = st_numscalar("r(savefe)")
	assert(auto_target==1 | auto_target==0)
	if (auto_target) stata(sprintf("cap drop __hdfe*__*"))

	original_absvars = extended_absvars = J(1, G, "")

	for (g=1; g<=G; g++) {
		fe = &(S.fes[g])
		// recall a->b is the same as (*a).b
		num_slopes = st_numscalar(sprintf("r(num_slopes%f)",g))
		has_intercept = st_numscalar(sprintf("r(has_intercept%1.0f)",g))

		fe->order = g
		fe->num_slopes = num_slopes
		fe->has_intercept = has_intercept
		fe->varlabel = st_global(sprintf("r(varlabel%f)",g))
		fe->ivars = tokens(st_global( sprintf("r(ivars%f)",g) ))
		fe->cvars = tokens(st_global( sprintf("r(cvars%f)",g) ))
		fe->idvarname = sprintf("__ID%f__", g)
		fe->levels = .
		fe->target = J(0,0,"")
		fe->is_clustervar = 0
		fe->in_clustervar = 0
		fe->nesting_clustervar = .

		extended_absvars[g] = original_absvars[g] = invtokens(fe->ivars, "#")
		if (num_slopes>0) {
			original_absvars[g] = original_absvars[g] + (has_intercept ? "##c." : "#c.")
			original_absvars[g] = original_absvars[g] + (num_slopes==1 ? (fe->cvars) : "("+invtokens(fe->cvars)+")")
			
			extended_absvars[g] = (has_intercept ? extended_absvars[g] + " " : "") + invtokens(extended_absvars[g] + "#c." :+ (fe->cvars))
		}
			
		basetarget = st_global(sprintf("r(target%f)",g))
		if (basetarget=="" & auto_target) basetarget = sprintf("__hdfe%f__", g)
		if (basetarget!="") {
			S.will_save_fe = 1
			target = J(1, has_intercept + num_slopes, basetarget)
			if (has_intercept) stata(sprintf("confirm new variable %s", target[1]))
			for (i=1+has_intercept; i<=length(target); i++) {
				target[i] = target[i] + sprintf("_Slope%f", i-has_intercept)
				stata(sprintf("confirm new variable %s", target[i]))
			}
			fe->target = target
		}
	}

	equation_d_valid = 1
	equation_d = ""
	for (g=1; g<=S.G; g++) {
		H = S.fes[g].has_intercept + S.fes[g].num_slopes
		if (length(S.fes[g].target)==0) {
			equation_d_valid = 0
			break
		}
		assert(length(S.fes[g].target==H))

		j = 0
		for (i=1; i<=H;i++) {
			equation_d = equation_d + sprintf("%s%s", equation_d=="" ? "" : " + ", S.fes[g].target[i])
			if (i>1 | !S.fes[g].has_intercept) j++ // j is the cvar counter
			if (j>0) equation_d = equation_d + sprintf(" * %s", S.fes[g].cvars[j])
		}
	}
	if (equation_d_valid) st_global("r(equation_d)", invtokens(equation_d) )
	
	st_numscalar("r(will_save_fe)", S.will_save_fe)
	st_global("r(original_absvars)", invtokens(original_absvars) )
	st_global("r(extended_absvars)", invtokens(extended_absvars) )
	return(S)
}

void function map_init_clustervars(`Problem' S, `String' clustervars) {
	S.clustervars = S.clustervars_original = tokens(clustervars)
	S.C = length(S.clustervars)
}

void function map_init_weights(`Problem' S, `Varname' weightvar, `String' weighttype) {
	assert_msg(weightvar!="" & weighttype!="", "map_init_weights() requires weight var and type")
	stata(sprintf("confirm numeric variable %s, exact", weightvar))
	assert_msg(anyof(("fweight", "pweight", "aweight"), weighttype), "wrong weight type")
	S.weightvar = weightvar
	S.weighttype = weighttype
	S.weights = sprintf("[%s=%s]", weighttype, weightvar)
}

void function map_init_keepvars(`Problem' S, `Varname' keepvars) {
	//if (keepvars!="") stata(sprintf("confirm numeric variable %s, exact", keepvars))
	S.keepvars = tokens(keepvars)
}

void function map_init_transform(`Problem' S, `String' transform) {
	transform = strlower(transform)
	// Convert abbreviations
	if (strpos("cimmino", transform)==1) transform = "cimmino"
	if (strpos("kaczmarz", transform)==1) transform = "kaczmarz"
	if (strpos("symmetric_kaczmarz", transform)==1) transform = "symmetric_kaczmarz"
	if (strpos("rand_kaczmarz", transform)==1) transform = "random_kaczmarz" // experimental
	if (strpos("random_kaczmarz", transform)==1) transform = "random_kaczmarz" // experimental
	assert_msg(anyof(("cimmino","kaczmarz","symmetric_kaczmarz", "random_kaczmarz"),transform), "invalid transform")
	S.transform = transform
}

void function map_init_verbose(`Problem' S, `Integer' verbose) {
	assert_msg(round(verbose)==verbose, "verbose must be an integer")
	assert_msg(0<=verbose & verbose<=5, "verbose must be between 0 and 5")
	S.verbose = verbose
}

void function map_init_timeit(`Problem' S, `Integer' timeit) {
	assert_msg(timeit==0 | timeit==1, "timeit must be 0 or 1")
	S.timeit = timeit
}

void function map_init_poolsize(`Problem' S, `Integer' poolsize) {
	assert_msg(round(poolsize)==poolsize & poolsize>0, "poolsize must be a positive integer")
	S.poolsize = poolsize
}

void function map_init_panelvar(`Problem' S, `Varname' panelvar) {
	S.panelvar = panelvar
}

void function map_init_timevar(`Problem' S, `Varname' timevar) {
	S.timevar = timevar
}

void function map_init_groupvar(`Problem' S, `Varname' groupvar) {
	S.groupvar = groupvar
}

void function map_init_acceleration(`Problem' S, `String' acceleration) {
	acceleration = strlower(acceleration)
	// Convert abbreviations
	if (strpos("conjugate_gradient", acceleration)==1 | acceleration=="cg") acceleration = "conjugate_gradient"
	if (strpos("steepest_descent", acceleration)==1 | acceleration=="sd") acceleration = "steepest_descent"
	if (strpos("aitken", acceleration)==1) acceleration = "aitken"
	if (strpos("hybrid", acceleration)==1) acceleration = "hybrid" // experimental
	if (acceleration=="no" | acceleration=="none" | acceleration=="off") acceleration = "none"
	assert_msg(anyof(("conjugate_gradient","steepest_descent", "aitken", "none", "hybrid"),acceleration), "invalid acceleration")
	S.acceleration = acceleration
}

void function map_init_tolerance(`Problem' S, `Real' tolerance) {
	assert_msg(1e-16<=tolerance & tolerance<1, "tolerance must be in the range [1e-16, 1).")
	S.tolerance = tolerance
}

void function map_init_maxiterations(`Problem' S, `Integer' maxiterations) {
	assert_msg(round(maxiterations)==maxiterations, "maxiterations must be an integer")
	assert_msg(maxiterations>0, "maxiterations must be positive")
	S.maxiterations = maxiterations
}

void function map_init_keepsingletons(`Problem' S, `Boolean' keepsingletons) {
	assert_msg(keepsingletons==0 | keepsingletons==1, "keepsingletons must be 0 or 1")
	S.keepsingletons = keepsingletons
}

void function map_init_vce_is_hac(`Problem' S, `Boolean' vce_is_hac) {
	assert_msg(vce_is_hac==0 | vce_is_hac==1, "vce_is_hac must be 0 or 1")
	S.vce_is_hac = vce_is_hac
}
	
void function map_precompute(`Problem' S) {
	`Integer' i, g, h, value
	`Varlist' keepvars, cl_ivars
	transmorphic counter, loc
	`Varname' key
	`String' all_clustervars
	`Boolean' has_intercept
	if (S.verbose>0) printf("\n{txt}{bf:mata: map_precompute()}\n")

	// Warn if there are no fixed intercepts (i.e. heterogeneous intercepts)
	has_intercept = 0
	for (g=1; g<=S.G; g++) {
		if (S.fes[g].has_intercept) has_intercept = 1
	}
	if (has_intercept==0) printf("{txt}(WARNING: no intercepts terms in absorb(); regression lacks constant term)\n")

	// Count how many times each var is used, so we can drop them when the counter reaches zero
	counter = asarray_create()
	asarray_notfound(counter, 0)
	// Variables passed through map_init_keepvars()
	keepvars = S.keepvars
	// ivars and cvars of the FEs
	for (g=1; g<=S.G; g++) {
		keepvars = keepvars, S.fes[g].ivars , S.fes[g].cvars
	}
	// Weight var
	if (S.weightvar!="") keepvars = keepvars, S.weightvar
	// Cluster vars
	for (h=1; h<=S.C; h++) {
		cl_ivars = tokens(S.clustervars[h], "#")
		cl_ivars = select(cl_ivars, cl_ivars:!="#")
		keepvars = keepvars, cl_ivars
	}
	// Time and panel vars
	if (S.vce_is_hac & S.timevar!="") keepvars = keepvars, S.timevar
	if (S.vce_is_hac & S.panelvar!="") keepvars = keepvars, S.panelvar

	// Fill
	for (i=1; i<=length(keepvars); i++) {
		asarray(counter, keepvars[i], asarray(counter, keepvars[i])+1)
	}

	// Report
	if (S.verbose>3) printf("{txt}{bf: 0. Usage count of each variable (dropped if it reaches zero)}\n")
	for (i=1; i<=asarray_elements(counter); i++) {
		if (S.verbose>3) printf("{txt}    - key=%s {col 30}count=%f\n", keepvars[i], asarray(counter,keepvars[i]))
	}

	// 0. Store sort order (used in steps 1 and 3)
	S.sortedby = tokens(st_macroexpand("`" + ": sortedby" + "'"))

	// 1. Store permutation vectors and their invorder, generate ID variables, drop singletons
	if (S.verbose>0) printf("{txt}{bf: 1. Storing permutation vectors, generating ids, dropping singletons}\n")
	if (S.timeit) timer_on(21)
	map_precompute_part1(S, counter)
	if (S.timeit) {
		timer_off(21)
		printf("{res}{col 20}%6.3f{txt}{col 30}precompute 1 (sorts, ids, drop singletons)\n", timer_value(21)[1])
		timer_clear(21)
	} 

	// 2. Store group offsets, group counters; demeaned(x), inv(xx) if num_slopes>0; weightvars
	if (S.verbose>0) printf("{txt}{bf: 2. Storing counters and offsets; processing cvars}\n")
	if (S.timeit) timer_on(22)
	map_precompute_part2(S, counter)
	if (S.timeit) {
		timer_off(22)
		printf("{res}{col 20}%6.3f{txt}{col 30}precompute 2 (counters, offsets, cvars)\n", timer_value(22)[1])
		timer_clear(22)
	} 

	// 3. Create cluster IDs, report whether is/in/nested wrt cluster; store precomputed inv(p)
	if (S.verbose>0) printf("{txt}{bf: 3. Storing reverse permutation vectors, creating cluster IDs}\n")
	if (S.timeit) timer_on(23)
	map_precompute_part3(S, counter)
	if (S.timeit) {
		timer_off(23)
		printf("{res}{col 20}%6.3f{txt}{col 30}precompute 3 (reverse permutations, cluster ids)\n", timer_value(23)[1])
		timer_clear(23)
	} 

	// 4. Keep only the essential variables
	keepvars  = J(1,0,"")
	for (loc=asarray_first(counter); loc!=NULL; loc=asarray_next(counter, loc)) {
		key = asarray_key(counter, loc)
		value = asarray_contents(counter, loc)
		if (value>0) keepvars = keepvars, key
	}
	if (S.verbose>3) printf("{txt}{bf: 4. Keeping the following variables}")
	st_keepvar(keepvars)
	// if (S.verbose>3) printf("\n{txt}    %s\n", invtokens(keepvars))
	if (S.verbose>3) stata("describe _all, numbers") // This resets r(..)!
	if (S.verbose>3) printf("\n")

	// Store N (todo: add other details) to ensure the dataset doesn't change from now on
	S.N = st_nobs()

	// Store updated clustervars (run after describe!)
	for (h=1; h<=S.C;h++) {
		all_clustervars = all_clustervars, S.clustervars[h]
	}
	st_rclear()
	st_global("r(updated_clustervars)", invtokens(all_clustervars))
}
	
void map_precompute_part1(`Problem' S, transmorphic counter) {

	`Integer' G, i, j, n, g, h, i_last_singleton, num_singletons, initial_N
	`Boolean' sortedby
	`Group' id
	`Series' singleton, sum_singleton, inv_p
	`Varlist' idvarnames
	string scalar vartype
	pointer(`Series') scalar pp // Just to shorten code

	G = length(S.fes)
	i = i_last_singleton = g = 1

	// Give huge warning if keeping singletons
	if (S.keepsingletons) printf(`"{txt}(WARNING: singletons are not dropped; statistical significance might be biased {browse "http://scorreia.com/reghdfe/nested_within_cluster.pdf":[link]})\n"')

	initial_N = st_nobs()

	// Loop until we stop discovering singletons (and then a bit more to be sure; G-1 to be exact)
	while (i<i_last_singleton+G) {
		if (g>G) g = 1
		if (S.verbose>1) printf("{txt}    - i=%f (g=%f/%f)\t(N=%f)\t", i, g, G, st_nobs())

		idvarnames = i<=G ? S.fes[g].ivars : S.fes[g].idvarname
		id = st_data(., idvarnames) // 2% of runtime
		if (i<=G) {
			for (j=1; j<=length(idvarnames); j++) {
				n = asarray(counter, idvarnames[j]) - 1
				asarray(counter, idvarnames[j], n)
				if (n==0) {
					st_dropvar(idvarnames[j])
				}
			}
		}
		if (i<=G) S.fes[g].is_sortedby = already_sorted(S, idvarnames)
		sortedby = S.fes[g].is_sortedby
		if (i<=G & !sortedby) {
			if (S.timeit) timer_on(31)
			S.fes[g].p = order( id , 1..length(idvarnames) ) // 55% of function time
			if (S.timeit) {
				timer_off(31)
				printf("{res}{col 30}%6.3f{txt}{col 40}mata order()\n", timer_value(31)[1])
				timer_clear(31)
			} 
		}

		if (!sortedby) {
			_collate(id, S.fes[g].p) // sort id by p // 12% of function time
			inv_p = invorder(S.fes[g].p) // construct inv(p) that we'll use later
		}

		// Note that the lhs is actually the deltas, as in "bys id: gen delta = _n==1"
		id = rows_that_change(id) // 7% of function time
		if (!S.keepsingletons) singleton = select_singletons(id) // 5% of function time

		// Save IDs in dataset before dropping observations
		id = S.keepsingletons ? runningsum(id) : runningsum(id :* !singleton) // this is the ID now, not the deltas anymore
		S.fes[g].levels = id[length(id)]
		vartype = S.fes[g].levels<=100 ? "byte" : (S.fes[g].levels<=32740? "int" : "long")
		if (i<=G) {
			st_store(., st_addvar(vartype, S.fes[g].idvarname), sortedby? id : id[inv_p])
		}
		else {
			st_store(., S.fes[g].idvarname, sortedby? id : id[inv_p])
		}

		num_singletons = S.keepsingletons ? 0 : sum(singleton)
		if (num_singletons>0) {
			if (S.verbose>1) printf("{txt}(%f singletons)", num_singletons)
			i_last_singleton = i

			// Sort -singleton- as in the dataset, and use it to drop observations
			// 5% of function time
			singleton = sortedby? singleton : singleton[inv_p]
			st_dropobsif(singleton)
			if (!st_nobs()) {
				printf("{err}\nno observations left after dropping singletons (%f obs. dropped)\n", initial_N)
				exit(error(2001))
			}

			// But now our precious sort orders (the p's) are useless! Fix them
			sum_singleton = runningsum(singleton)
			for (h=1;h<=G & h<=i; h++) { // 6% of function time
				if (S.fes[h].is_sortedby) continue
				pp = &(S.fes[h].p)
				(*pp) = select(*pp - sum_singleton[*pp] , !singleton[*pp] )
			}
		}

		if (S.verbose>1) printf("{txt}\n")
		i++
		g++
	}

	if (initial_N>st_nobs()) printf("{txt}(dropped %f singleton observations)\n", initial_N-st_nobs())
}

// -------------------------------------------------------------
// ALREADY_SORTED:
// -------------------------------------------------------------
`Integer' already_sorted(`Problem' S, string vector vars) {
	return(length(vars) > length(S.sortedby) ? 0 : vars==S.sortedby[1..length(vars)])
}

// -------------------------------------------------------------
// ROWS_THAT_CHANGE: Return a 0/1 vector indicating what are diff from the previous row
// -------------------------------------------------------------
	// Idea: compromise between doing the operation in one go (uses lots of memory) vs doing loops (2x slower)
	// Other alternatives: loop row-by-row (slower), loop col-by-col and take max() (slower)
`Vector' rows_that_change(`Matrix' input) {
	`Vector' ans
	`Integer' i, j, K, N, stepsize
	
	// Size of blocks of matrices used (larger=faster smaller=less memory)
	// Benchmarks with 3 unsorted ivars showed 1e4 was fastest, followed by 1e3 and then 1e5
	stepsize = 1e4

	N = rows(input)
	K = cols(input)
	ans = J(N,1,0)
	ans[1] = 1
	for (i=2; i<=N;i=i+stepsize) {
		j = min((i+stepsize-1, N))
		ans[|i\j|] = rowmax(input[|i-1,1\j-1,K|] :!= input[|i,1\j,K|])
	}
	return(ans)
}

// -------------------------------------------------------------
// SELECT_SINGLETONS: 
// -------------------------------------------------------------
`Vector' select_singletons(`Vector' input) {
	// Code modified from <rows_that_change>
	`Vector' ans
	`Integer' i, j, N, stepsize

	// Size of blocks of matrices used (larger= hopefully faster, but smaller=less memory)
	// Benchmarks with 3 unsorted ivars showed 1e4 was fastest, followed by 1e3 and then 1e5
	stepsize = 1e4

	N = rows(input)
	ans = J(N,1,0)
	for (i=1; i<=N-1;i=i+stepsize) {
		j = min((i+stepsize-1, N-1))
		// We need that ans[i]==1 and ans[i+1]==1
		// Since ans is either 0 or 1, this is equivalent to
		ans[|i\j|] = (input[|i\j|] + input[|i+1\j+1|] :== 2) 
	}
	ans[N] = (input[N]==1) // Special case, last obs is singleton if it's the first obs in the group
	return(ans)
}
	
void map_precompute_part2(`Problem' S, transmorphic counter) {
	`Integer' G, g, k, K, n
	real scalar stdev
	`Boolean' sortedby
	`Series' id

	G = length(S.fes)
	if (S.weightvar!="") S.w = st_data(., S.weightvar)

	for (g=1; g<=G; g++) {
		sortedby = S.fes[g].is_sortedby
		K = S.fes[g].num_slopes
		assert(K==length(S.fes[g].cvars))
		if (S.verbose>1) printf("{txt}    - g=%f/%f\t\t(K=%f)\n", g, G, K)
		
		id = st_data(., S.fes[g].idvarname)
		if (!sortedby) id = id[S.fes[g].p]

		// Store offsets, counts (optionally weighted)
		S.fes[g].counts = count_by_group(id) // this line accounts for 95% of the runtime of map_precompute_part2()
		S.fes[g].offsets = runningsum(S.fes[g].counts)
		if (S.weightvar!="") S.fes[g].counts = count_by_group(id, sortedby? S.w : S.w[S.fes[g].p])

		// Store cvars and related structures
		if (K>0) {

			// Store the cvars
			S.fes[g].x = st_data(., S.fes[g].cvars)

			// Drop cvars from dataset if not needed anymore
			for (k=1; k<=K; k++) {
				n = asarray(counter, S.fes[g].cvars[k]) - 1
				asarray(counter, S.fes[g].cvars[k], n)
				if (n==0) {
					st_dropvar(S.fes[g].cvars[k])
				}
			}

			// Sort the cvars if needed
			if (!sortedby) S.fes[g].x = S.fes[g].x[S.fes[g].p,]

			// Standardize
			// BUGBUG: Check that results don't change; specially on corner cases
			// EG: weights, no intercept, intercept, only one slope, etc.
			for (k=1; k<=K; k++) {
				// BUGBUG
				stdev = 1 // sqrt(quadvariance(S.fes[g].x[., k]))
				if (stdev<1e-5) stdev = 1e-5 // Reduce accuracy errors
				S.fes[g].x[., k] = S.fes[g].x[., k] :/ stdev
			}

			// Demean X and precompute inv(X'X) (where X excludes the constant due to demeaning, if applicable)
			// Note that the demeaning is done directly in the S. structure
			S.fes[g].inv_xx = demean_and_compute_invxx(S, g)
		} // end of slope part
	
	} // next g
}

// -------------------------------------------------------------
// COUNT_BY_GROUP: alternative to mm_freq(group) (~10% of runtime)
// -------------------------------------------------------------
// Assume -id- (groups) and -w- (the weights) are sorted by id!
`Vector' function count_by_group(`Series' id, | `Series' w)
{
	`Integer' i, j, obs, levels, count
	`Boolean' has_weights
	`Vector' ans

	obs = rows(id)
	levels = id[length(id)]
	assert_msg(obs>levels, "Error: more levels of FE than observations!")
	has_weights = args()>1

	ans = J(levels, 1, 0)
	count = 0

	// Avoid conditional op. within loop as it gets *really* slow
	// <i> indexes observations, <j> indexes groups
	if (has_weights) {
		for (i=j=1; i<=obs; i++) {
			if (id[i]>j) {
				ans[j++] = count
				count = 0
			}
			count = count + w[i]
		}
	}
	else {
		for (i=j=1; i<=obs; i++) {
			if (id[i]>j) {
				ans[j++] = count
				count = 0
			}
			++count
		}
	}

	ans[j] = count // Last group
	assert( all(ans) ) // Counts *must* be positive for all levels
	return(ans)
}

// -------------------------------------------------------------
// DEMEAN_AND_COMPUTE_INVXX
// -------------------------------------------------------------
`Matrix' function demean_and_compute_invxx(`Problem' S, `Integer' g) {

	// j iterates over LEVELS; i iterates over OBS
	`Integer'	K, L, j, i_lower, i_upper
	`Boolean'	has_weights, sortedby, has_intercept
	`Matrix'	ans, tmp_x
	`Vector'	w, tmp_w
	real scalar	tmp_count
	K = S.fes[g].num_slopes // Exclude intercept
	L = S.fes[g].levels
	ans = J(L*K, K, 0)
	has_weights = S.weightvar !=""
	sortedby = S.fes[g].is_sortedby
	has_intercept = S.fes[g].has_intercept

	if (has_weights) {
		w = sortedby ? S.w : S.w[S.fes[g].p]
		assert(rows(w)==rows(S.fes[g].x))
	}

	if (has_intercept) S.fes[g].xmeans = J(L, K, .)
	
	i_lower = 1
	for (j=1; j<=L; j++) {
		i_upper = S.fes[g].offsets[j]
		tmp_count = S.fes[g].counts[j]
		tmp_w = has_weights ? w[| i_lower \ i_upper |] : 1
		tmp_x = S.fes[g].x[| i_lower , 1 \ i_upper , . |]
		if (has_intercept) {
			S.fes[g].xmeans[j, .] = quadcolsum(has_weights ? tmp_x :* tmp_w : tmp_x) / tmp_count
			S.fes[g].x[| i_lower , 1 \ i_upper , . |] = tmp_x = tmp_x :- S.fes[g].xmeans[j, .]
		}
		ans[| 1+(j-1)*K , 1 \ j*K , . |] = invsym(quadcross(tmp_x, tmp_w, tmp_x))
		i_lower = i_upper + 1

		// BUGBUG: quadcolsum???? quadcross????
		// use crossdev(x,means,w,x,means) if we don't demean beforehand
	}
	return(ans)
}
	
void map_precompute_part3(`Problem' S, transmorphic counter) {
	`Integer' g, h, i, j, n, L, i_lower, i_upper
	`Varname' var
	`Boolean' done, is_nested, sortedby, hac_exception
	`Vector' need_to_create_clustervar, range
	`Varlist' sorted_fe_ivars, sorted_cl_ivars, cl_ivars
	`String' vartype
	`Group' id
	`Series' p, sorted_cl_id

	need_to_create_clustervar = J(S.C, 1, 1)

	for (g=1;g<=S.G;g++) {
		S.fes[g].inv_p = invorder(S.fes[g].p)
		var = S.fes[g].idvarname
		st_varlabel(var, sprintf("[ID] %s", S.fes[g].varlabel))
		asarray(counter, var, asarray(counter, var)+1)

		done = 0
		sorted_fe_ivars = sort(S.fes[g].ivars', 1)'

		// 1. Check if the FE has the same ivars as a cluster (is_clustervar=1)
		for (h=1; h<=S.C;h++) {
			sorted_cl_ivars = tokens(S.clustervars[h], "#")
			sorted_cl_ivars = sort(select(sorted_cl_ivars, sorted_cl_ivars:!="#")', 1)'
			hac_exception = (sorted_cl_ivars==S.panelvar | sorted_cl_ivars==S.timevar) & S.vce_is_hac
			if (sorted_fe_ivars==sorted_cl_ivars & !hac_exception) {
				need_to_create_clustervar[h] = 0
				S.clustervars[h] = var
				st_varlabel(var, sprintf("[CLUSTER] %s", st_varlabel(var)))
				S.fes[g].is_clustervar = 1
				done = 1
				break
			}
		}
	}

	// Create the cluster IDs if needed
	for (h=1; h<=S.C;h++) {
		cl_ivars = tokens(S.clustervars_original[h], "#")
		cl_ivars = select(cl_ivars, cl_ivars:!="#")
		
		
		for (j=1; j<=length(cl_ivars); j++) {
			n = asarray(counter, cl_ivars[j]) - 1
			assert_msg(n>=0, sprintf("counter[%s] was negative", cl_ivars[j]))
			asarray(counter, cl_ivars[j], n)
		}
		
		if (!need_to_create_clustervar[h]) continue
		if (cl_ivars==S.panelvar & S.vce_is_hac) continue
		if (cl_ivars==S.timevar  & S.vce_is_hac) continue

		id = st_data(., cl_ivars)

		// Construct and save cluster ID
		sortedby = already_sorted(S, cl_ivars)
		p = order( id , 1..length(cl_ivars) )
		if (!sortedby) {
			_collate(id, p) // sort id by p // 12% of function time
		}
		id = runningsum(rows_that_change(id))
		L = id[rows(id)]
		vartype = L<=100 ? "byte" : (L<=32740? "int" : "long")
		S.clustervars[h] = sprintf("__CL%f__", h)
		asarray(counter, S.clustervars[h], asarray(counter, S.clustervars[h])+1)
		st_store(., st_addvar(vartype, S.clustervars[h]), sortedby ? id : id[invorder(p)])
		st_varlabel(S.clustervars[h], sprintf("[CLUSTER] %s", S.clustervars_original[h]))
	}

	for (g=1;g<=S.G;g++) {
		var = S.fes[g].idvarname
		if (S.fes[g].is_clustervar) continue
		done = 0
		sorted_fe_ivars = sort(S.fes[g].ivars', 1)'

		// 2. Check if the FE ivars are a superset of those of the cluster (in_clustervar=1)
		for (h=1; h<=S.C;h++) {
			sorted_cl_ivars = tokens(S.clustervars_original[h], "#")
			sorted_cl_ivars = sort(select(sorted_cl_ivars, sorted_cl_ivars:!="#"), 1)
			if (length(sorted_cl_ivars)>=length(sorted_fe_ivars)) continue
			is_nested = 1
			for (i=1;i<=length(sorted_cl_ivars);i++) {
				if (!anyof(sorted_fe_ivars, sorted_cl_ivars[i])) {
					is_nested = 0
					break
				}
			}
			if (is_nested) {
				S.fes[g].in_clustervar = 1
				S.fes[g].nesting_clustervar = h
				done = 1
				break
			}
		}
		if (done) continue

		// 3. Check if the FE is nested within a cluster (e.g. cluster=state FE=zipcode)
		L = S.fes[g].levels
		for (h=1; h<=S.C; h++) {
			sorted_cl_id = st_data(., S.clustervars[h])
			if (!S.fes[g].is_sortedby) sorted_cl_id = sorted_cl_id[S.fes[g].p]
			i_lower = 1
			is_nested = 1
			for (j=1; j<=L; j++) {
				i_upper = S.fes[g].offsets[j]
				range = minmax(sorted_cl_id[| i_lower , 1 \ i_upper , . |])
				i_lower = i_upper + 1
				if (range[1]!=range[2]) {
					is_nested = 0
					break
				}
			}
			if (is_nested) {
				S.fes[g].in_clustervar = 1
				S.fes[g].nesting_clustervar = h
				break
			}
		}
	}
}
	
`Group' function map_projection(`Problem' S, `Integer' g, `Group' y) {
	`Integer' 	K, L, Q // Q is the number of depvars
	`Integer' 	j, i_lower, i_upper // j loops over levels, i loops over observations
	`Boolean' 	has_weights, sortedby, has_intercept, storing_betas
	`Series'	sorted_w
	`Group'		ans
	`Vector'	tmp_w, tmp_count
	real rowvector b
	real rowvector ymean, alpha // 1*Q
	real rowvector zero // 1*K
	`Matrix'	tmp_y, tmp_x
	pointer(`Series') scalar p_sorted_w
	pragma unset sorted_w // If we just set the pointer, what happens to the underlying data?

	// PROFILE TO SEE IF THIS HELPS OR NOT AT ALL
	//pointer(`Vector') scalar p_offset
	//p_offset = &(S.fes[g].offsets)

	has_weights = S.weightvar !=""
	sortedby = S.fes[g].is_sortedby
	has_intercept = S.fes[g].has_intercept
	K = S.fes[g].num_slopes
	Q = cols(y)
	L = S.fes[g].levels
	tmp_w = 1 // Harmless value for when there are no weights

	// Minimize copy+order operations on y
	if (has_weights) p_sorted_w = sortedby ? &(S.w) : &(sorted_w = S.w[S.fes[g].p, .])
	if (K>0) zero = J(1,K,0)

	ans = sortedby ? y : y[S.fes[g].p, .]

	i_lower = 1
	storing_betas = S.storing_betas & length(S.fes[g].target)>0
	for (j=1; j<=L; j++) {
		i_upper = S.fes[g].offsets[j]
		tmp_count = S.fes[g].counts[j]
		
		if (has_weights) tmp_w = (*p_sorted_w)[| i_lower \ i_upper |]
		tmp_y = ans[| i_lower , 1 \ i_upper , . |]
		// BUGBUG: quadcolsum or colsum ? Depends if there are dense FEs. Maybe condition it on L??
		if (has_weights) {
			ymean = has_intercept ? (quadcolsum(tmp_y :* tmp_w) / tmp_count) : 0
		}
		else {
			ymean = has_intercept ? (quadcolsum(tmp_y) / tmp_count) : 0
		}

		if (K>0) {
			tmp_x = S.fes[g].x[| i_lower , 1 \ i_upper , . |]
			// BUGBUG crossdev/cross or their quad version?
			if (has_intercept) {
				b = S.fes[g].inv_xx[| 1+(j-1)*K , 1 \ j*K , . |] * quadcrossdev(tmp_x, zero, tmp_w, tmp_y, ymean)
				alpha = ymean - S.fes[g].xmeans[j, .] * b
			}
			else {
				b = S.fes[g].inv_xx[| 1+(j-1)*K , 1 \ j*K , . |] * quadcross(tmp_x, tmp_w, tmp_y)
			}
		}
		
		if (storing_betas) {
			if (has_intercept) S.fes[g].tmp_alphas[j, 1] = K==0 ? ymean : alpha
			if (K>0) S.fes[g].tmp_alphas[j, (has_intercept+1)..(has_intercept+K) ] = b'
		}

		// BUGBUG if we split this ternary will it be faster?
		//ans[| i_lower , 1 \ i_upper , . |] = K>0 ? (ymean :+ tmp_x*b) : (ymean :+ J(i_upper-i_lower+1,Q,0))
		if (K==0) {
			ans[| i_lower , 1 \ i_upper , . |] = ymean :+ J(i_upper-i_lower+1,Q,0)
		}
		else if (has_intercept) {
			ans[| i_lower , 1 \ i_upper , . |] = ymean :+ tmp_x*b
		}
		else {
			ans[| i_lower , 1 \ i_upper , . |] = tmp_x*b
		}


		i_lower = i_upper + 1
	}
		
	return(sortedby ? ans : ans[S.fes[g].inv_p, .])
}
	
void function map_solve(`Problem' S, `Varlist' vars, | `Varlist' newvars, `Boolean' restore_dta) {

	`Integer' i, j, h, Q
	`Group' y, residuals
	`Varlist'	chars
	real rowvector stdevs
	`FunctionPointer' transform, accelerate

	if (S.verbose>0) printf("{txt}{bf:mata: map_solve()}\n")
	assert_msg(S.N!=., "map_solve() needs to be run after map_precompute()")
	assert_msg(S.N==st_nobs(), "dataset cannot change after map_precompute()")
	S.storing_betas = 0

	if (S.verbose>0) printf("{txt} - Loading variables into Mata\n")
	vars = tokens(vars)
	Q = cols(vars)

	// Store chars var[name] that contain the original varname (e.g. L.var)
	chars = J(1, Q, "")
	for (i=1;i<=Q;i++) {
		chars[i] = st_global(sprintf("%s[name]", vars[i]))
	}

	// Optional arguments
	newvars = (args()<3 | newvars=="") ? vars : tokens(newvars)
	assert_msg(length(vars)==length(newvars), "map_solve error: newvars must have the same size as vars")
	if (args()<4) restore_dta = 0 // restore dataset (only for hdfe.ado)
	assert_msg(restore_dta==0 | restore_dta==1, "restore_dta must be 0 or 1")
	
	// Solver Warnings
	if (S.transform=="kaczmarz" & S.acceleration=="conjugate_gradient") {
		printf("{err}(WARNING: convergence is {bf:unlikely} with transform=kaczmarz and accel=CG)\n")
	}

	// Load transform pointer
	if (S.transform=="cimmino") transform = &transform_cimmino()
	if (S.transform=="kaczmarz") transform = &transform_kaczmarz()
	if (S.transform=="symmetric_kaczmarz") transform = &transform_sym_kaczmarz()
	if (S.transform=="random_kaczmarz") transform = &transform_rand_kaczmarz()

	// Pointer to acceleration routine
	if (S.acceleration=="none") accelerate = &accelerate_none()
	if (S.acceleration=="conjugate_gradient") accelerate = &accelerate_cg()
	if (S.acceleration=="steepest_descent") accelerate = &accelerate_sd()
	if (S.acceleration=="aitken") accelerate = &accelerate_aitken()
	if (S.acceleration=="hybrid") accelerate = &accelerate_hybrid()

	// Shortcut for trivial case (1 FE)
	if (S.G==1) accelerate = &accelerate_none()

	// Iterate on variables grouped by poolsize: subset = data[i..j]
	S.num_iters_max = 0
	if (restore_dta) residuals = J(S.N, 0, .)

	for (i=1; i<=Q; i=i+S.poolsize) {
		
		j = i + S.poolsize - 1
		if (j>Q) j = Q

		// Load data
		y = st_data(., vars[i..j])
		
		// Drop loaded vars as quickly as possible (also they might not even be -double-)
		st_dropvar(vars[i..j])
		
		// Standardize variables
		if (S.verbose>0) printf("{txt} - Standardizing variables\n")
		stdevs = J(1, cols(y), .)
		for (h=1; h<=cols(y); h++) {
			stdevs[h] = max((  sqrt(quadvariance(y[., h])) , sqrt(epsilon(1)) ))
		}
		y = y :/ stdevs

		// Solve!		
		if (S.verbose>0) printf("{txt} - Solving problem (acceleration={res}%s{txt}, transform={res}%s{txt} tol={res}%-1.0e{txt} poolsize={res}%f{txt} varsize={res}%f{txt})\n", S.acceleration, S.transform, S.tolerance, S.poolsize, cols(y))
		if (S.verbose>1) printf("{txt} - Variables: {res}" + invtokens(vars[i..j])+"{txt}\n")
		y = (*accelerate)(S, y, transform) :* stdevs
		if (S.num_iters_last_run>S.num_iters_max) S.num_iters_max = S.num_iters_last_run
		
		// Return residuals
		if (restore_dta) {
			residuals = residuals , y
		}
		else {
			if (S.verbose>1) printf("{txt} - Saving transformed variables\n")
			st_store(., st_addvar("double", newvars[i..j]), y)
		}
		y = J(0,0,.) // clear space (not really needed)

	}

	// this is max(iter) across all vars
	if (S.verbose==0) printf("{txt}(converged in %g iterations)\n", S.num_iters_max)

	// Restore dataset; used by hdfe.ado with generate() instead of clear
	if (restore_dta) {
		stata("restore")
		st_store(S.uid, st_addvar("double", newvars), residuals)
		residuals = J(0,0,.) // clear space (not really needed)
	}

	// Add chars with original names to new variables
	for (i=1;i<=Q;i++) {
		st_global(sprintf("%s[name]", newvars[i]), chars[i])
	}

}
	
void function map_save_fe(`Problem' S, `Varname' sum_fe) {

	// Storing FEs and returning them requires 6 changes
	// 1) Extend the S and FE structures (add S.storing_betas, FE.alphas FE.tmp_alphas)
	// 2) Allocate them here
	// 3) Return results at the end of this function
	// 4) Within the accelerators, modify the SD to update the alphas
	// 5) Within map_projection, add a conditional to update tmp_alphas if needed

	`Integer' 	g
	`Vector' 	y
	`Varlist'	target

	if (S.verbose>0) printf("{txt}{bf:mata: map_save_fe()}\n")
	assert_msg(S.N!=., "map_save_fe() needs to be run after map_precompute()")
	assert_msg(S.N==st_nobs(), "dataset cannot change after map_precompute()")

	if (S.verbose>0) printf("{txt} - Loading variable into Mata\n")
	assert_msg(length(tokens(sum_fe))==1, "sum_fe should be a varname, not a varlist")
	y = st_data(., sum_fe)
	
	st_dropvar(sum_fe)
	
	if (S.verbose>0) printf("{txt} - Allocating objects to save the fixed effect estimates\n")
	S.storing_betas = 1
	for (g=1; g<=S.G; g++) {
		if (length(S.fes[g].target)>0) {
			S.fes[g].alphas = S.fes[g].tmp_alphas = 
				J(S.fes[g].levels, S.fes[g].has_intercept + S.fes[g].num_slopes, 0)
		}
	}

	// No need to standardize b/c it's only one variable
	if (S.verbose>0) printf("{txt} - Solving problem (acceleration={res}%s{txt}, transform={res}%s{txt} tol={res}%-1.0e{txt} poolsize={res}%f{txt} varsize={res}%f{txt})\n", "steepest_descent", "kaczmarz", S.tolerance, S.poolsize, 1)

	y = accelerate_sd(S, y, &transform_kaczmarz())
	if (S.verbose==0) printf("{txt}(converged in %g iterations)\n", S.num_iters_last_run)
	
	if (S.verbose>1) printf("{txt} - Saving transformed variable\n")
	st_store(., st_addvar("double", sum_fe), y)
	y = J(0,0,.) // clear space

	// Store FEs
	if (S.verbose>1) printf("{txt} - Saving fixed effects\n")
	for (g=1; g<=S.G; g++) {
		target = S.fes[g].target
		if (length(target)>0) {
			S.fes[g].tmp_alphas = J(0,0,.)
			S.fes[g].alphas = S.fes[g].alphas[ st_data(., S.fes[g].idvarname) , . ]
		}
	}
}
	
// -------------------------------------------------------------------------------------------------
// Acceleration Schemes
// -------------------------------------------------------------------------------------------------

`Group' function accelerate_none(`Problem' S, `Group' y, `FunctionPointer' T) {
	`Integer'	iter
	`Group'		resid
	pragma unset resid

	for (iter=1; iter<=S.maxiterations; iter++) {
		(*T)(S, y, resid) // Faster version of "resid = S.T(y)"
		if (check_convergence(S, iter, resid, y)) break
		y = resid
	}
	return(resid)
}
// -------------------------------------------------------------------------------------------------

// Start w/out acceleration, then switch to CG
`Group' function accelerate_hybrid(`Problem' S, `Group' y, `FunctionPointer' T) {
	`Integer' iter, accel_start
	`Group' resid
	pragma unset resid

	accel_start = 3

	for (iter=1; iter<=accel_start; iter++) {
		(*T)(S, y, resid) // Faster version of "resid = S.T(y)"
		if (check_convergence(S, iter, resid, y)) break
		y = resid
	}

	return(accelerate_cg(S, y, T))
}

// -------------------------------------------------------------------------------------------------
// Memory cost is approx = 4*size(y) (actually 3 since y is already there)
// But we need to add maybe 1 more due to u:*v
// And I also need to check how much does project and T use..
// Double check with a call to memory

// For discussion on the stopping criteria, see the following presentation:
// Arioli & Gratton, "Least-squares problems, normal equations, and stopping criteria for the conjugate gradient method". URL: https://www.stfc.ac.uk/SCD/resources/talks/Arioli-NAday2008.pdf

// Basically, we will use the Hestenes and Stiefel rule

`Group' function accelerate_cg(`Problem' S, `Group' y, `FunctionPointer' T) {
	// BUGBUG iterate the first 6? without acceleration??
	`Integer'	iter, d, Q
	`Group'		r, u, v
	real rowvector alpha, beta, ssr, ssr_old, improvement_potential
	`Matrix' recent_ssr
	pragma unset r
	pragma unset v

	Q = cols(y)
	
	d = 2 // BUGBUG Set it to 2/3 // Number of recent SSR values to use for convergence criteria (lower=faster & riskier)
	// A discussion on the stopping criteria used is described in
	// http://scicomp.stackexchange.com/questions/582/stopping-criteria-for-iterative-linear-solvers-applied-to-nearly-singular-system/585#585

	improvement_potential = weighted_quadcolsum(S, y, y)
	recent_ssr = J(d, Q, .)
	
	(*T)(S, y, r, 1)
	ssr = weighted_quadcolsum(S, r, r) // cross(r,r) when cols(y)==1 // BUGBUG maybe diag(quadcross()) is faster?
	u = r

	for (iter=1; iter<=S.maxiterations; iter++) {
		(*T)(S, u, v, 1) // This is the hottest loop in the entire program
		alpha = safe_divide( ssr , weighted_quadcolsum(S, u, v) )
		recent_ssr[1 + mod(iter-1, d), .] = alpha :* ssr
		improvement_potential = improvement_potential - alpha :* ssr
		y = y - alpha :* u
		r = r - alpha :* v
		ssr_old = ssr
		ssr = weighted_quadcolsum(S, r, r)
		beta = safe_divide( ssr , ssr_old) // Fletcher-Reeves formula, but it shouldn't matter in our problem
		u = r + beta :* u
		// Convergence if sum(recent_ssr) > tol^2 * improvement_potential
		if ( check_convergence(S, iter, colsum(recent_ssr), improvement_potential, "hestenes") ) break
	}
	return(y)
}

// -------------------------------------------------------------------------------------------------

`Group' function accelerate_sd(`Problem' S, `Group' y, `FunctionPointer' T) {
	`Integer'	iter, g
	`Group' proj
	real rowvector t
	pragma unset proj

	for (iter=1; iter<=S.maxiterations; iter++) {
		(*T)(S, y, proj, 1)
		if (check_convergence(S, iter, y-proj, y)) break
		t = safe_divide( weighted_quadcolsum(S, y, proj) , weighted_quadcolsum(S, proj, proj) )
		if (uniform(1,1)<0.1) t = 1 // BUGBUG: Does this help to randomly unstuck an iteration?
		y = y - t :* proj
		
		if (S.storing_betas) {
			for (g=1; g<=S.G; g++) {
				if (length(S.fes[g].target)>0) {
					S.fes[g].alphas = S.fes[g].alphas + t :* S.fes[g].tmp_alphas
				}
			}
		}
	}
	return(y-proj)
}

// -------------------------------------------------------------------------------------------------
// This is method 3 of Macleod (1986), a vector generalization of the Aitken-Steffensen method
// Also: "when numerically computing the sequence.. stop..  when rounding errors become too 
// important in the denominator, where the ^2 operation may cancel too many significant digits"
// Note: Sometimes the iteration gets "stuck"; can we unstuck it with adding randomness
// in the accelerate decision? There should be a better way.. (maybe symmetric kacz instead of standard one?)

`Group' function accelerate_aitken(`Problem' S, `Group' y, `FunctionPointer' T) {
	`Integer'	iter
	`Group'		resid, y_old, delta_sq
	`Boolean'	accelerate
	real rowvector t
	pragma unset resid

	//S.pause_length = 20
	//S.bad_loop_threshold = 1
	//S.stuck_threshold = 5e-3
	// old_error = oldest_error = bad_loop = acceleration_countdown = 0

	y_old = J(rows(y), cols(y), .)

	for (iter=1; iter<=S.maxiterations; iter++) {
		
		(*T)(S, y, resid)
		accelerate = iter>=S.accel_start & !mod(iter,S.accel_freq)

		// Accelerate
		if (accelerate) {
			delta_sq = resid - 2 * y + y_old // = (resid - y) - (y - y_old) // Equivalent to D2.resid
			// t is just (d'd2) / (d2'd2)
			t = safe_divide( weighted_quadcolsum(S,  (resid - y) , delta_sq) ,  weighted_quadcolsum(S, delta_sq , delta_sq) )
			resid = resid - t :*  (resid - y)
		}

		// Only check converge on non-accelerated iterations
		// BUGBUG: Do we need to disable the check when accelerating?
		// if (check_convergence(S, iter, accelerate? resid :* .  : resid, y)) break
		if (check_convergence(S, iter, resid, y)) break
		
		// Experimental: Pause acceleration
		//if (accelerate) {
		//	improvement = max(( (old_error-update_error)/update_error , (oldest_error-update_error)/update_error ))
		//	bad_loop = improvement < stuck_threshold ? bad_loop+1 : 0
		//	// bad_loop, improvement, update_error, old_error, oldest_error
		//	// Tolerate two problems (i.e. 6+2=8 iters) and then try to unstuck
		//	if (bad_loop>bad_loop_threshold) {
		//		bad_loop = 0
		//		if (VERBOSE==3) printf(" Fixed point iteration seems stuck, acceleration paused\n")
		//		acceleration_countdown = pause_length
		//	}
		//	assert(bad_loop<=3)	
		//	oldest_error = old_error
		//	old_error = update_error
		//}
		//
		y_old = y // y_old is resid[iter-2]
		y = resid // y is resid[iter-1]
	}
	return(resid)
}

// -------------------------------------------------------------------------------------------------

`Boolean' check_convergence(`Problem' S, `Integer' iter, `Group' y_new, `Group' y_old,| `String' method) {
	`Boolean'	done, is_last_iter
	`Real'		update_error

	// max() ensures that the result when bunching vars is at least as good as when not bunching
	if (args()<5) method = "vectors" 

	if (S.G==1 & !S.storing_betas) {
		// Shortcut for trivial case (1 FE)
		update_error = 0
	}
	else if (method=="vectors") {
		update_error = max(mean(reldif(y_new, y_old)))
	}
	else if (method=="hestenes") {
		// If the regressor is perfectly explained by the absvars, we can have SSR very close to zero but negative
		// (so sqrt is missing)
		update_error = max(safe_divide( sqrt(y_new) , editmissing(sqrt(y_old), sqrt(epsilon(1)) ) , sqrt(epsilon(1)) ))
	}
	else {
		exit(error(100))
	}

	done = update_error <= S.tolerance
	is_last_iter = iter==S.maxiterations
	
	if (done) {
		S.num_iters_last_run = iter
		if (S.verbose==1) printf("{txt} converged in %g iterations last error =%3.1e)\n", iter, update_error)
		if (S.verbose>1) printf("\n{txt} - Converged in %g iterations (last error =%3.1e)\n", iter, update_error)
	}
	else if (is_last_iter) {
		printf("\n{err}convergence not achieved in %g iterations (last error=%e); try increasing maxiter() or decreasing tol().\n", S.maxiterations, update_error)
		exit(430)
	}
	else {
		if ((S.verbose>=2 & S.verbose<=3 & mod(iter,1)==0) | (S.verbose==1 & mod(iter,10)==0)) {
			printf("{txt}.")
			displayflush()
		}
		if ( (S.verbose>=2 & S.verbose<=3 & mod(iter,100)==0) | (S.verbose==1 & mod(iter,1000)==0) ) printf("{txt}%9.1f\n", update_error/S.tolerance)

		if (S.verbose==4 & method!="hestenes") printf("{txt} iter={res}%4.0f{txt}\tupdate_error={res}%-9.6e\n", iter, update_error)
		if (S.verbose==4 & method=="hestenes") printf("{txt} iter={res}%4.0f{txt}\tupdate_error={res}%-9.6e  {txt}norm(ssr)={res}%g\n", iter, update_error, norm(y_new))
		
		if (S.verbose==5) {
			printf("\n{txt} iter={res}%4.0f{txt}\tupdate_error={res}%-9.6e{txt}\tmethod={res}%s\n", iter, update_error, method)
			"old:"
			y_old
			"new:"
			y_new
		}
	}
	return(done)
}

// -------------------------------------------------------------------------------------------------

`Matrix' weighted_quadcolsum(`Problem' S, `Matrix' x, `Matrix' y) {
	// BUGBUG: colsum or quadcolsum??
		return( quadcolsum(S.weightvar=="" ? (x :* y) : (x :* y :* S.w) ) )
}
	
// -------------------------------------------------------------------------------------------------
// Transformations: Compute RESIDUALS, not projections
// -------------------------------------------------------------------------------------------------

void function transform_cimmino(`Problem' S, `Group' y, `Group' ans,| `Boolean' get_proj) {
	`Integer' 	g, G
	G = S.G
	if (args()<4) get_proj = 0

	ans = map_projection(S, 1, y)
	for (g=2; g<=G; g++) {
		ans = ans + map_projection(S, g, y)
	}
	ans = get_proj ? ans / G : y - ans / G
}

// -------------------------------------------------------------------------------------------------

void function transform_kaczmarz(`Problem' S, `Group' y, `Group' ans,| `Boolean' get_proj) {
	`Integer' 	g, G
	G = S.G
	if (args()<4) get_proj = 0

	ans = y - map_projection(S, 1, y)
	for (g=2; g<=G; g++) {
		ans = ans - map_projection(S, g, ans)
	}
	if (get_proj) ans = y - ans
}

// -------------------------------------------------------------------------------------------------
// This seems slower than kaczmarz (sym kaczmarz!); not used currently
void function transform_rand_kaczmarz(`Problem' S, `Group' y, `Group' ans,| `Boolean' get_proj) {
	`Integer' 	g, G
	G = S.G
	`Vector' rand
	if (args()<4) get_proj = 0
	rand = sort( ( (1::G) , uniform(G,1) ) , 2 )[.,1]

	ans = y - map_projection(S, rand[1], y)
	for (g=2; g<=G; g++) {
		ans = ans - map_projection(S, rand[g], ans)
	}
	for (g=G-1; g>=1; g--) {
		ans = ans - map_projection(S, rand[g], ans)
	}
	if (get_proj) ans = y - ans
}

// -------------------------------------------------------------------------------------------------

 void function transform_sym_kaczmarz(`Problem' S, `Group' y, `Group' ans,| `Boolean' get_proj) {
	`Integer' 	g, G
	// BUGBUG: Streamline and remove all those "ans - .." lines?
	G = S.G
	if (args()<4) get_proj = 0

	ans = y - map_projection(S, 1, y)
	for (g=2; g<=G; g++) {
		ans = ans - map_projection(S, g, ans)
	}
	for (g=G-1; g>=1; g--) {
		ans = ans - map_projection(S, g, ans)
	}
	if (get_proj) ans = y - ans
}
	
void map_estimate_dof(`Problem' S, string rowvector adjustments, 
		| `Varname' groupvar, `String' cond) {
	`Boolean' adj_two, adj_pairwise, adj_clusters, adj_continuous, belongs, already_first_constant
	string rowvector all_adjustments
	`String' adj, label, basestring
	`Integer' i, g, SuperG, h, M_due_to_nested, j, m, sum_levels, m2
	`Vector' M, M_is_exact, M_is_nested, is_slope, solved, i_to_g, SubGs

	// Parse list of adjustments/tricks to do
	if (S.verbose>1) printf("\n")
	if (S.verbose>0) printf("{txt}{bf:mata: map_estimate_dof()}\n")
	if (S.verbose>1) printf("{txt} - Estimating degrees-of-freedom used by the fixed effects\n")
	all_adjustments = "two", "three", "pairwise", "clusters", "continuous"
	adjustments = tokens(adjustments)
	for (i=1; i<=length(adjustments);i++) {
		assert_msg(anyof(all_adjustments, adjustments[i]), 
			sprintf("map_estimate_dof error: adjustment %s invalid", adjustments[i]))
	}
	if (S.verbose>1) printf("{txt} - Adjustments:\n")
	for (i=1;i<=length(all_adjustments);i++) {
		adj = all_adjustments[i]
		belongs = anyof(adjustments, adj)
		if (S.verbose>1) printf("{txt}    - %s:  {col 20}{res} %s\n", adj, belongs ? "yes" : "no")
		if (adj=="two") adj_two = belongs
		if (adj=="three") adj_three = belongs
		if (adj=="pairwise") adj_pairwise = belongs
		if (adj=="clusters") adj_clusters = belongs
		if (adj=="continuous") adj_continuous = belongs
	}

	// Assert that the clustervars exist
	for (i=1;i<=S.C;i++) {
		stata(sprintf("confirm numeric variable %s, exact", S.clustervars[i]))
	}

	// Can only save connected group if two or pairwise are active
	if (args()<3) groupvar = ""
	if (groupvar!="") {
		assert_msg(adj_two | adj_pairwise, "map_estimate_dof error: group option requires 'pairwise' or 'two' adjustments")
	}

	// Count all fixed intercepts and slopes
	SubGs = J(S.G, 1, 0) // Intercept + # of slopes in an absvar
	for (g=1;g<=S.G;g++) {
		SubGs[g] = S.fes[g].has_intercept + S.fes[g].num_slopes
	}
	SuperG = sum(SubGs)
	if (S.verbose>1) printf("{txt} - There are %f fixed intercepts and slopes in the %f absvars\n", SuperG, S.G)

	// Initialize result vectors and scalars
	M = J(SuperG, 1, 1)
	M_is_exact = J(SuperG, 1, 0)
	M_is_nested = J(SuperG, 1, 0)
	is_slope = J(SuperG, 1, .)
	solved = J(SuperG, 1, 0)

	// Initial Fill
	h = 0
	already_first_constant = 0
	for (g=1;g<=S.G;g++) {
		for (i=1;i<=SubGs[g];i++) {
			h++
			if (is_slope[h] = i>S.fes[g].has_intercept) {
				M[h] = 0
			}
			else if (!already_first_constant) {
				already_first_constant = 1
				M[h] = 0
			}

		}
	}

	// (Intercept-Only) Look for absvars that are clustervars or are nested within a clustervar
	h = 1
	M_due_to_nested = 0
	if (adj_clusters) {
		for (g=1;g<=S.G;g++) {
			if (S.fes[g].has_intercept & (S.fes[g].is_clustervar | S.fes[g].in_clustervar)) {
				M[h] = S.fes[g].levels
				M_is_exact[h] = M_is_nested[h] = 1
				M_due_to_nested = M_due_to_nested + M[h]
				solved[h] = 1
				if (S.verbose>1 & S.fes[g].is_clustervar) printf("   {txt}(categorical variable {res}%s{txt} is also a cluster variable, so it doesn't count towards DoF)\n", invtokens(S.fes[g].ivars,"#"))
				if (S.verbose>1 & S.fes[g].in_clustervar) printf("   {txt}(categorical variable {res}%s{txt} is nested within cluster {res}%s{txt}, so it doesn't count towards DoF)\n", invtokens(S.fes[g].ivars,"#"), S.clustervars_original[S.fes[g].nesting_clustervar])
			}
			h = h + SubGs[g]
		}
	}

	// (Intercept-only) Excluding those already solved, the first absvar is exact, and the second can be with pairwise/two

	// Note: I dont't include the FEs that are clusters or are nested within cluster when computing redundant coefs
	// On principle, that would be nice to have. EG: reghdfe .... abs(zipcode state##c.time) vce(zipcode)
	// I know state is collinear with zipcode so I would also want to consider state to be redundant

	// However, the number of states should be much smaller than the number of zipcodes, which in turn is smaller
	// Than the number of observations; so I don't worry much about that case (also, there may be possible 
	// complications with that)

	i = 0 // Different from -g- as it iterates over effective FEs (i<=g)
	h = 1 // Different from -g- as it counts multiple FEs in one g (h>=g)
	m2 = 0 // needed for group3hdfe
	i_to_g = J(S.G, 1, 0)
	for (g=1;g<=S.G;g++) {

		assert( (i <= g) & (g <= h) )

		if (!solved[h] & S.fes[g].has_intercept) {
			i++
			if (i==1) {
				M_is_exact[h] = 1
			}
			else if (i==2 & (adj_pairwise | adj_two | adj_three)) {
				M_is_exact[h] = 1
				m = map_connected_groups(S, i_to_g[1], g, groupvar)
				if (S.verbose>2) printf("{txt}    - Mobility groups between fixed intercept #%f and #%f: {res}%f\n", i_to_g[1], g, m)
				M[h] = m
				m2 = m
			}
			else if (i>2 & adj_pairwise) {
				// Call connected in a LOOP (but I need to save the list of those that I needed to check)
				for (j=1; j<i; j++) {
					m = map_connected_groups(S, i_to_g[j], g)
					if (S.verbose>2) printf("{txt}    - Mobility groups between fixed intercept #%f and #%f: {res}%f\n", i_to_g[j], g, m)
					M[h] = max((M[h], m))
				}
				if (S.verbose>2) printf("{txt}    - Maximum of mobility groups wrt fixed intercept #%f: {res}%f\n", g, M[h])

			}
			else if (i==3 & adj_three) {
				M_is_exact[h] = 1
				cmd = "qui group3hdfe __ID%s__ __ID%s__ __ID%s__"
				cmd = sprintf(cmd, strofreal(i_to_g[i-2]), strofreal(i_to_g[i-1]), strofreal(g))
				stata(cmd)
				m = st_numscalar("r(rest)") - m2
				if (S.verbose>2) printf("{txt}    - Redundant coefs in #%f from previous FEs: {res}%f\n", g, m)
				M[h] = m
			}
			i_to_g[i] = g
		}
		h = h + SubGs[g]
	}

	// See if cvars are zero (w/out intercept) or just constant (w/intercept)
	if (adj_continuous) {
		h = 0
		for (g=1;g<=S.G;g++) {
			for (i=1;i<=SubGs[g];i++) {
				h++
				// If model has intercept, redundant cvars are those that are CONSTANT
				// Without intercept, a cvar has to be zero within a FE for it to be redundant
				// Since S.fes[g].x are already demeaned IF they have intercept, we don't have to worry about the two cases
				if (is_slope[h]) {
					M[h] = count_redundant_cvars(S, g, i)
				}
			}
		}
	}

	// Store results
	S.dof_SubGs = SubGs
	
	S.doflist_M = M
	S.doflist_M_is_exact = M_is_exact
	S.doflist_M_is_nested = M_is_nested

	sum_levels = 0
	for (g=1;g<=S.G;g++) sum_levels = sum_levels + S.fes[g].levels * (S.fes[g].has_intercept + S.fes[g].num_slopes)
	S.dof_M = sum(M)
	S.dof_KminusM = sum_levels - S.dof_M
	S.dof_M_due_to_nested = M_due_to_nested
	S.dof_N_hdfe_extended = SuperG

	st_numscalar("e(df_a)", S.dof_KminusM) // We need this in the regression stage!

	// Report results
	if (S.verbose>=2) {
		printf("{txt} - Degrees-of-freedom used by each fixed effect (K=total levels; M=redundant levels)\n")
		h = 0
		for (g=1;g<=S.G;g++) {
			for (i=1;i<=SubGs[g];i++) {
				h++
				label = invtokens(S.fes[g].ivars, "#")
				if (i>S.fes[g].has_intercept) label = label + "#c." + S.fes[g].cvars[i-S.fes[g].has_intercept]
				basestring = "{txt}   - FE%f ({res}%s{txt}): {col 40}K=%f {col 50}M=%f {col 60}is_exact=%f\n"
				printf(basestring, g, label, S.fes[g].levels, M[h], M_is_exact[h])
			}
		}
	}
	if (S.verbose>0) printf(" - Results: N=%f ; K=%f ; M=%f ; (K-M)==df_a=%f\n", S.N, sum_levels, sum(M), sum_levels-sum(M))
}
// -------------------------------------------------------------------------------------------------

void function map_ereturn_dof(`Problem' S) {
	`Integer' h, g, i

	st_numscalar("e(N_hdfe)", S.G)
	st_numscalar("e(N_hdfe_extended)", S.dof_N_hdfe_extended)
	st_numscalar("e(redundant)", S.dof_M)
	st_numscalar("e(M_due_to_nested)", S.dof_M_due_to_nested)
	st_numscalar("e(df_a)", S.dof_KminusM)

	h = 0
	for (g=1;g<=S.G;g++) {
		for (i=1;i<=S.dof_SubGs[g];i++) {
			h++
			st_numscalar( sprintf("e(M%f)",h) , S.doflist_M[h] )
			st_numscalar( sprintf("e(K%f)",h) , S.fes[g].levels )

			st_numscalar( sprintf("e(M%f_exact)",h) , S.doflist_M_is_exact[h])
			st_numscalar( sprintf("e(M%f_nested)",h) , S.doflist_M_is_nested[h])
			st_numscalar( sprintf("e(G%f)",h) , g) // unused?
		}
	}
}

// -------------------------------------------------------------------------------------------------

`Integer' function count_redundant_cvars(`Problem' S, `Integer' g, `Integer' i) {
	`Integer' j, i_lower, i_upper, ans, L, ii
	real rowvector min_max
	`Series' x

	ii = i-S.fes[g].has_intercept
	ans = 0
	L = S.fes[g].levels
	x = S.fes[g].x[., ii]
	
	i_lower = 1
	for (j=1;j<=L; j++) {
		i_upper = S.fes[g].offsets[j]
		min_max = minmax(x[| i_lower \ i_upper |])
		if (sqrt(epsilon(1))>abs(min_max[1]) & sqrt(epsilon(1))>abs(min_max[2])) ans++
		i_lower = i_upper + 1
	}
	if (S.verbose>=2) printf("{txt}    - Fixed slope {res}%s#c.%s {txt}has {res}%f/%f{txt} redundant coefs.\n", invtokens(S.fes[g].ivars,"#"), S.fes[g].cvars[ii], ans, L)
	return(ans)
}
	
`Integer' function map_connected_groups(`Problem' S, `Integer' g1, `Integer' g2, | `Varname' groupvar) {
	`Boolean' changed
	`Series' group, p
	`Integer' gg, g, j, i_lower, i_upper, num_groups, L
	real rowvector min_max

	changed = 1
	group = st_data(., S.fes[g1].idvarname)
	if (args()<4) groupvar = ""
	
	while (changed) {
		changed = 0
		for (gg=1;gg<=2;gg++) {
			g = gg==1 ? g2 : g1
			L = S.fes[g].levels
			if (!S.fes[g].is_sortedby) _collate(group, S.fes[g].p) // Sort it by g1 or g2
			i_lower = 1
			for (j=1;j<=L; j++) {
				i_upper = S.fes[g].offsets[j]
				min_max = minmax(group[| i_lower , 1 \ i_upper , 1 |])
				if (min_max[1]!=min_max[2]) changed = 1
				group[| i_lower , 1 \ i_upper , 1 |] = min_max[1] :* J(i_upper-i_lower+1,1,1)
				i_lower = i_upper + 1
			}
			if (!S.fes[g].is_sortedby) _collate(group, S.fes[g].inv_p) // Sort it back
		}
	}

	// Create compact group id
	p = order(group, 1)
	_collate(group, p)
	group = runningsum(rows_that_change(group))
	num_groups = group[rows(group)]
	_collate(group, invorder(p))
	
	// (optional) save group variable
	// Don't save until back in the main dataset!
	// S.groupvar = groupvar // already saved in map_init_groupvar
	S.grouptype = num_groups<=100 ? "byte" : (num_groups<=32740? "int" : "long")
	S.grouplabel = sprintf("Mobility Group: %s <--> %s", invtokens(S.fes[g1].ivars,"#") , invtokens(S.fes[g2].ivars,"#"))
	S.groupseries = group
	return(num_groups)
}

	// This is not part of the MAP code but for simplicity we'll put it here
	
// -------------------------------------------------------------------------------------------------
// Fix nonpositive VCV; called from Wrapper_mwc.ado 
// -------------------------------------------------------------------------------------------------
void function fix_psd(string scalar Vname) {
	real matrix V, U, lambda

	V = st_matrix(Vname)
	if (!issymmetric(V)) exit(error(505))
	symeigensystem(V, U=., lambda=.)
	st_local("eigenfix", "0")
	if (min(lambda)<0) {
		lambda = lambda :* (lambda :>= 0)
		// V = U * diag(lambda) * U'
		V = quadcross(U', lambda, U')
		st_local("eigenfix", "1")
	}
	st_replacematrix(Vname, V)
}

end
// -------------------------------------------------------------------------------------------------

