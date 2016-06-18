pr drop _all
clear all
sysuse auto
set trace off
cls

cd "C:\Git\reghdfe\source\"
adopath + "internal"
adopath + "mata"
adopath + "common"

reghdfe_mata init
reghdfe_mata inspect

exit
do internal/Parse.ado


