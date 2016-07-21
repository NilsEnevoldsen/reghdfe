* Config
	log close _all
	pr drop _all
	clear all
	discard
	cap cls
	set more off
	set trace off
	cd "C:/Git/reghdfe/test"
	cap cls
	
	cap ado uninstall reghdfe
	rebuild_git reghdfe

* Run scripts
	adopath + "C:\Git\reghdfe\source\internal"
	adopath + "C:\Git\reghdfe\source\common"
*	adopath - "C:\Git\reghdfe\source\internal"
*	adopath - "C:\Git\reghdfe\source\common"
	
* Test
	sysuse auto
	reghdfe price, a(turn)
