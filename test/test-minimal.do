* Test that it doesn't crash
set varabbrev on

*cscript "minimal test" adofile reghdfe

* Setup
	cap cls
	discard
	clear all
	set more off
	*qui adopath + "D:/Github/reghdfe/test"
	set more off


set trace off
pr drop _all
	
* Convenience
	cap pr drop TrimMatrix
	pr TrimMatrix, eclass
	args size
		assert `size'>0
		matrix trim_b = e(b)
		matrix trim_V = e(V)
		matrix trim_b = trim_b[1, 1..`size']
		matrix trim_V = trim_V[1..`size',1..`size']
		ereturn matrix trim_b = trim_b
		ereturn matrix trim_V = trim_V
	end
	
* Dataset
	sysuse auto
	drop if missing(rep)

	replace length = 0 if rep==3
	replace length = 5 if rep==1

bys turn: gen t = _n
tsset turn t
gen byte one = 1

* Testing regress+avar
set trace off


* Testing regress+default
reghdfe price weight gear length, a(foreign) vce(unadjusted, suite(default))
reghdfe price weight gear length, a(foreign) vce(robust, suite(default))
reghdfe price weight gear length, a(foreign) vce(cluster turn, suite(default))
reghdfe price weight gear length, a(foreign) vce(cluster foreign, suite(default))
cap reghdfe price weight gear length, a(foreign) vce(cluster foreign turn, suite(default))
assert _rc!=0



exit
* BUGS

* I Need to add a test suite for singleton cases
gen byte singleton = _n==10
gen cl = _n
ivreg2 price weight gear singleton foreign, cluster(cl) small
areg price weight gear singleton, absorb(foreign) vce(cluster cl)
reghdfe price weight gear singleton, a(foreign) vce(cluster cl, suite(avar))
reghdfe price weight gear singleton, a(foreign) vce(cluster cl)

asd

ivreg2 price weight gear foreign, cluster(rep turn) small
reghdfe price weight gear, a(foreign) vce(cluster foreign turn, suite(avar)) nocons // verbose(3)
--> error en VCV... DoF cagado??

reghdfe price weight gear, a(turn t) vce(cluster turn t, bw(2)) verbose(3)
--> el tsset se mantiene con renames.. bajarme a las tsvars


asd





asd

areg price weight gear [fw=one], abs(rep) cluster(turn)
*xtreg price weight gear [fw=one], cluster(turn) fe

matrix list e(V)
local F1 = e(F)
test weight gear
local F2 = r(F)
reghdfe price weight gear [fw=one], a(rep) vce(cluster turn, suite(avar)) // verbose(3)
matrix list e(V)
local F3 = e(F)

di `F1'/`F3'
di `F2'/`F3'


asd
* Testing ivreg2
*reghdfe price weight (disp=gear), a(rep#foreign##c.length turn) vce(cluster foreign t, bw(2) kernel(tru))
*reghdfe price weight (displacement=gear_ratio), a(rep78#foreign##c.length turn) vce(, kernel(par))
*reghdfe price weight (displacement=gear_ratio), a(rep78#foreign##c.length turn) vce(, dkraay(3))
*reghdfe price weight (displacement=gear_ratio), a(rep78#foreign##c.length turn) vce(, kiefer)
*reghdfe price weight (displacement=gear_ratio), a(foreign) vce(cluster t, dkraay(2))

*reghdfe price weight (displacement=gear_ratio), a(foreign) vce(cluster t, dkraay(2)) ivsuite(ivregress)
*reghdfe price weight (displacement=gear_ratio), a(foreign) vce(cluster t) ivsuite(ivregress)


asd
set varabbrev off
set trace off
reghdfe price weight (displacement=gear_ratio), a(rep78#foreign##c.length turn) vce(, kernel(par)) verbose(3)
set varabbrev on
asd
reghdfe price weight (disp=gear), a(rep#foreign##c.length turn) vce(cluster foreign t, bw(2) kernel(tru))
reghdfe price weight (disp=gear), a(rep#foreign##c.length turn) vce(cluster foreign t, bw(2) kernel(tru))

asd
	
*reghdfe price weight disp, a(foreign#rep turn#rep) tol(1e-10) vce(cluster rep#foreign) verbose(3) dof(all)	
*reghdfe price weight disp, a(rep#i.turn##c.length foreign) tol(1e-10) vce(cluster turn) verbose(3) dof(all)
reghdfe price weight (disp=gear), a(rep#foreign##c.length turn) ///
	vce(cluster turn foreign#head, bw(2) kernel(tru)) ///
	tol(1e-10) verbose(3) dof(all)
	
ahora_con_bw_y_avar_y_default_y_todo
reghdfe price weight disp, a(rep foreign) tol(1e-10) vce(cluster turn#rep turn) verbose(3) dof(all)

asd
	
* [TEST] Verify that it gives the same results as -areg- with one-way-clustering
	reghdfe price weight disp, a(rep) tol(1e-10) vce(cluster turn#rep) verbose(3)
	reghdfe price weight (disp=length), a(rep) tol(1e-10) vce(cluster turn foreign) verbose(3)
	reghdfe price weight (disp=length), a(rep) tol(1e-10) vce(robust, bw(2)) // not passing it
	asd
	reghdfe price weight disp, a(rep) tol(1e-10) vce(cluster turn foreign) verbose(3)
	reghdfe price weight disp, a(rep) tol(1e-10) vce(cluster turn rep) verbose(3)

	
exit

* TODO
* Fix EstimateDoF
* Fix Estimate -> the call to the wrappers
* Fix ivreg2 wrapper
* Fix regress wrapper, with calls depending on the situation
* Create the custom mwc

