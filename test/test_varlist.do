// --------------------------------------------------------------------------
// Test valid varlists
// --------------------------------------------------------------------------
sysuse auto, clear
set more off
bys turn: gen t = _n
xtset turn t
cap cls
// --------------------------------------------------------------------------
local vars1 price
local depvar1 price
local indepvars1
local endogvars1
local instruments1

local vars2 pri
local depvar2 price
local indepvars2
local endogvars2
local instruments2

local vars3 price weight 
local depvar3 price
local indepvars3 weight
local endogvars3
local instruments3

local vars4 price weight i.turn turn#trunk#c.gea
local depvar4 price
local indepvars4 weight i.turn turn#trunk#c.gear_ratio
local endogvars4
local instruments4

local vars5 pri L.wei F2.weig L(1/2).(head fore)
local depvar5 price
local indepvars5 L.weight F2.weight L(1/2).(headroom foreign)
local endogvars5
local instruments5

local vars6 pri L.wei F2.weig (head = L(0/1).(fore gear_ratio))
local depvar6 price
local indepvars6 L.weight F2.weight
local endogvars6 headroom
local instruments6 L(0/1).(foreign gear_ratio)

local vars7 pri L.wei F2.weig (head = L(0/1).(fore gear_ratio) mpg)
local depvar7 price
local indepvars7 L.weight F2.weight
local endogvars7 headroom
local instruments7 L(0/1).(foreign gear_ratio) mpg

local vars8 pri L.wei F2.weig (head = L(0/1).(fore gear_ratio) mpg)
local depvar8 price
local indepvars8 L.weight F2.weight
local endogvars8 headroom
local instruments8 L(0/1).(foreign gear_ratio) mpg

local vars9 pri (head = L(0/1).(fore gear_ratio) mpg)
local depvar9 price
local indepvars9
local endogvars9 headroom
local instruments9 L(0/1).(foreign gear_ratio) mpg

local vars10 pri (= L(0/1).(fore gear_ratio) mpg)
local depvar10 price
local indepvars10
local endogvars10
local instruments10 L(0/1).(foreign gear_ratio) mpg

local vars11 pri (= fore gear_ratio mpg)
local depvar11 price
local indepvars11
local endogvars11
local instruments11 foreign gear_ratio mpg

local vars12 1.fore (= i.turn gear_ratio mpg)
local depvar12 1.foreign
local indepvars12
local endogvars12
local instruments12 i.turn gear_ratio mpg


// --------------------------------------------------------------------------
pr drop _all
adopath + "../source/internal"
adopath + "../source/common"
cls
// --------------------------------------------------------------------------
local i 1
while ("`vars`i''" != "") {
	di as text _dup(64) "-" _n "[i=`i'] " as result "`vars`i''"

	local varlist `vars`i''
	_fvunab `varlist'
	sreturn list
	*local basevars `s(basevars)'
	ParseVarlist `s(varlist)' // , estimator(`estimator') ivsuite(`ivsuite')
	sreturn list
	foreach cat in depvar indepvars endogvars instruments {
		_assert "`s(`cat')'" == "``cat'`i''"
	}
	*reghdfe `vars1', noabsorb
	local ++i
}
exit
