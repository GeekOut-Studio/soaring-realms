--!strict

--[=[
	@class EnemyInRange
	Predicate: returns `true` when an `Outworlder` is within `args.Range` studs of the
	denizen, and stashes the closest one on `denizen.Target` as a side effect so the
	subsequent transition's destination state can use it.

	The side effect is intentional but worth knowing about: see "Predicate side effects" in
	`DenizenBehaviorPlan.md` (commit history) for the rationale.
]=]

local ServerScriptService = game:GetService("ServerScriptService")

local Outworlder = require(ServerScriptService.Server.Components.Outworlder)

--[=[
	@interface Args
	@within EnemyInRange
	@field Range number
]=]
export type Args = {
	Kind: string,
	Range: number,
}

return function(denizen: any, args: Args): boolean
	local pos = denizen.Instance:GetPivot().Position
	local rangeSq = args.Range * args.Range

	local closest = nil
	local closestDistSq = math.huge
	for _, outworlder in Outworlder:GetAll() do
		if outworlder.Health <= 0 then
			continue
		end
		local distSq = (outworlder.Instance:GetPivot().Position - pos).Magnitude ^ 2
		if distSq <= rangeSq and distSq < closestDistSq then
			closest = outworlder
			closestDistSq = distSq
		end
	end

	if closest == nil then
		return false
	end
	denizen.Target = closest
	return true
end
