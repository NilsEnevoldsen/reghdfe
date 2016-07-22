pr drop _all
clear all
sysuse auto
set trace off
set more off
cls

cd "C:\Git\reghdfe\source\"
adopath + "parse"
adopath + "mata"
adopath + "common"

do mata/reghdfe.mata
do parse/Parse.ado

set trace off
set tracedepth 3


Parse price weight [aw=gear], verbose(5) ///
	a(A=turn trunk x = turn#tru#i.for#c.(gea disp) foreign##c.gear turn##c.(price weight), savefe)

Parse price weight [fw=turn], a(make turn) v(3)

Parse price weight [fw=turn], a(turn trunk turn#tru#i.for#c.(gea disp)) v(2)
