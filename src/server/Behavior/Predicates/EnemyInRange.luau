--!strict

--[=[
	@class EnemyInRange
	Predicate: scans live `Outworlder`s within `args.Range` studs of the denizen and, on a
	hit, calls `CombatServer.Engage(denizen, target)` so both end up in a session. Returns
	`true` exactly when an engagement happened (i.e., a hostile player was found in range).

	The side effect is the engagement itself, not stashing a target — `MeleeAggression`
	pulls its target from the denizen's session, not from a predicate-stashed field.
]=]

local ServerScriptService = game:GetService("ServerScriptService")

local CombatServer = require(ServerScriptService.Server.Servers.CombatServer)
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
	local pos = denizen:GetCFrame().Position
	local rangeSq = args.Range * args.Range

	local closest = nil
	local closestDistSq = math.huge
	for _, outworlder in Outworlder:GetAll() do
		if outworlder:GetHealth() <= 0 then
			continue
		end
		local distSq = (outworlder:GetCFrame().Position - pos).Magnitude ^ 2
		if distSq <= rangeSq and distSq < closestDistSq then
			closest = outworlder
			closestDistSq = distSq
		end
	end

	if closest == nil then
		return false
	end
	CombatServer.Engage(denizen, closest)
	return true
end
