--!strict

--[=[
	@class NotRecentlyDamaged
	Predicate: complement of `RecentlyDamaged`. Returns `true` when the denizen has not been
	damaged within the last `args.Seconds` seconds (or has never been damaged).
]=]

--[=[
	@interface Args
	@within NotRecentlyDamaged
	@field Seconds number
]=]
export type Args = {
	Kind: string,
	Seconds: number,
}

return function(denizen: any, args: Args): boolean
	local last = denizen.LastDamagedTime
	if last == nil then
		return true
	end
	return os.clock() - last > args.Seconds
end
