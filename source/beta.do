clear all
cls
set more off
discard

sysuse auto
bys turn: gen t = _n
xtset turn t
set trace off
reghdfe price length i.L.foreign##c.gear , a(turn) vce(cluster trunk#i.tur) v(4)
