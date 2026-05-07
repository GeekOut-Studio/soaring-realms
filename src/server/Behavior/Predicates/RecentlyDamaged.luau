--!strict

--[=[
	@class RecentlyDamaged
	Predicate: returns `true` when the denizen took damage within the last `args.Seconds`
	seconds. Reads `denizen.LastDamagedTime`, which `Denizen:OnDidTakeDamage` keeps current.
]=]

--[=[
	@interface Args
	@within RecentlyDamaged
	@field Seconds number
]=]
export type Args = {
	Kind: string,
	Seconds: number,
}

return function(denizen: any, args: Args): boolean
	local last = denizen.LastDamagedTime
	if last == nil then
		return false
	end
	return os.clock() - last <= args.Seconds
end
