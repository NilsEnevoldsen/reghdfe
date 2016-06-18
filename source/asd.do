clear all
cls
set more off

pr drop _all

set trace on
set matadebug on
set tracedepth 4

*do mata/reghdfe.mata
do reghdfe_mata.ado


reghdfe_mata       init 
mata: mata desc
do internal\Parse.ado
Parse
mata: display(REGHDFE.e.cmdline + ">")
exit
