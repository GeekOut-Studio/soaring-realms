return function(n: number): { number }
	local range = {}
	for number = 1, n do
		table.insert(range, number)
	end
	return range
end
