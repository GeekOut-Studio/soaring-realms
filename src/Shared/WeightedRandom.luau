--!strict

--[=[
	@class WeightedRandom
	Picks an entry from a list of `{Weight: number, ...}` records with probability
	proportional to `Weight`. The returned value is the original entry, so callers
	can read sibling fields (`Kind`, `Item`, etc.) directly off the result.
]=]

local WeightedRandom = {}

--[=[
	Returns one entry from `entries`, chosen with probability proportional to its
	`Weight` field. Entries with `Weight <= 0` are skipped. Errors when `entries`
	is empty or every weight is non-positive.
	@within WeightedRandom
	@param entries {T} -- Each entry must have a `Weight: number` field.
	@return T
]=]
function WeightedRandom.Pick<T>(entries: { T }): T
	local total = 0
	for _, entry in entries do
		local weight = (entry :: any).Weight :: number
		if weight > 0 then
			total += weight
		end
	end
	assert(total > 0, "WeightedRandom.Pick: entries is empty or all weights non-positive")

	local roll = math.random() * total
	local acc = 0
	for _, entry in entries do
		local weight = (entry :: any).Weight :: number
		if weight <= 0 then
			continue
		end
		acc += weight
		if roll <= acc then
			return entry
		end
	end
	return entries[#entries]
end

return WeightedRandom
