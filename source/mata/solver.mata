// Main reghdfe solver object
mata:
mata set matastrict on

class solver {
	`ereturn'			e
	`solver_options' opt
}

struct opt {
	real scalar fast
}

end

