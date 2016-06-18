capture program drop Tic
pr Tic
syntax, n(integer)
	timer clear `n'
	timer on `n'
end
