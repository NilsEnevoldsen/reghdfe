// --------------------------------------------------------------------------
// Test valid varlists
// --------------------------------------------------------------------------
sysuse auto, clear
set more off
bys turn: gen t = _n
xtset turn t
cap cls
// --------------------------------------------------------------------------

_fvunab price
assert s(varlist) == "price"
assert s(basevars) == "price"

_fvunab pri
assert s(varlist) == "price"
assert s(basevars) == "price"

_fvunab price weight 
assert s(varlist) == "price weight"
assert s(basevars) == "price weight"

*_fvunab price weight i.turn turn#trunk#c.gea
*assert s(varlist) == "price weight i.turn i.turn#i.trunk#c.gear_ratio"
*assert s(basevars) == "price weight turn trunk gear_ratio"

_fvunab pri L.wei F2.weig L(1/2).(head fore)
assert s(varlist) == "price L.weight F2.weight L(1/2).(headroom foreign)"
assert s(basevars) == "price weight headroom foreign"

_fvunab pri L.wei F2.weig (head    = L(0/1).(fore gear_ratio)) 
assert s(varlist) == "price L.weight F2.weight (headroom=L(0/1).(foreign gear_ratio))"
assert s(basevars) == "price weight headroom foreign gear_ratio"

_fvunab pri L.wei F2.weig (head =L(0/1).(fore gear_ratio) mpg)
assert s(varlist) == "price L.weight F2.weight (headroom=L(0/1).(foreign gear_ratio) mpg)"
assert s(basevars) == "price weight headroom foreign gear_ratio mpg"

_fvunab pri (head = L(0/1).(fore gear_ratio) mpg)
assert s(varlist) == "price (headroom=L(0/1).(foreign gear_ratio) mpg)"
assert s(basevars) == "price headroom foreign gear_ratio mpg"

_fvunab price (i.turn i.trunk)#c.(gear mp)
assert s(varlist) == "price (i.turn i.trunk)#c.(gear_ratio mpg)"
assert s(basevars) == "price turn trunk gear_ratio mpg"

_fvunab price i.(turn trunk)#c.(gear mp)
assert s(varlist) == "price i.(turn trunk)#c.(gear_ratio mpg)"
assert s(basevars) == "price turn trunk gear_ratio mpg"

*fvset base 40 turn
*_fvunab price (i.turn i.trunk)#c.(gear mp)
*assert s(varlist) == "price (ib40.turn i.trunk)#c.(gear_ratio mpg)"
*assert s(basevars) == "price turn trunk gear_ratio mpg"
*fvset clear _all

_fvunab pri (= L(0/1).(fore gear_ratio) mpg)
assert s(varlist) == "price (=L(0/1).(foreign gear_ratio) mpg)"
assert s(basevars) == "price foreign gear_ratio mpg"

_fvunab pri (= fore gear_ratio mpg)
assert s(varlist) == "price (=foreign gear_ratio mpg)"
assert s(basevars) == "price foreign gear_ratio mpg"

_fvunab 1.fore (= i.turn gear_ratio mpg)
assert s(varlist) == "1.foreign (=i.turn gear_ratio mpg)"
assert s(basevars) == "foreign turn gear_ratio mpg"

_fvunab turn b=trunk c = turn#fore, target
assert s(varlist) == "turn b=trunk c=turn#foreign"
assert s(basevars) == "turn trunk foreign"


sreturn list
exit
