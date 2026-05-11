--!strict

--[=[
	@class Flee
	State factory for fleeing. Picks a point `Distance` studs away from `denizen.LastAttacker`
	(or `denizen.Target`, whichever is set) and walks there at `Speed`× the denizen's
	`BaseMoveSpeed`. Re-picks once the denizen arrives.

	`Speed` is restored on `Exit` so subsequent states use the def's normal move speed.
]=]

--[=[
	@interface Config
	@within Flee
	@field Speed number -- Multiplier on `Def.MoveSpeed` while fleeing.
	@field Distance number -- Stud distance away from the threat to flee toward.
]=]
export type Config = {
	Kind: string,
	Speed: number,
	Distance: number,
}

local function threatPosition(denizen: any): Vector3?
	local attacker = denizen.LastAttacker
	if attacker ~= nil then
		return attacker:GetCFrame().Position
	end
	local target = denizen.Target
	if target ~= nil then
		return target:GetCFrame().Position
	end
	return nil
end

return function(config: Config)
	local prevMoveSpeed: number? = nil

	return {
		Enter = function(denizen: any)
			prevMoveSpeed = denizen.ControllerManager.BaseMoveSpeed
			denizen.ControllerManager.BaseMoveSpeed = denizen.Def.MoveSpeed * config.Speed
		end,
		Update = function(denizen: any, _dt: number): string?
			if denizen.MoveTarget ~= nil then
				return nil
			end

			local pos = denizen:GetCFrame().Position
			local threat = threatPosition(denizen)
			local awayDir: Vector3
			if threat ~= nil then
				local diff = pos - threat
				if diff:FuzzyEq(Vector3.zero) then
					local angle = math.random() * math.pi * 2
					awayDir = Vector3.new(math.cos(angle), 0, math.sin(angle))
				else
					awayDir = Vector3.new(diff.X, 0, diff.Z).Unit
				end
			else
				local angle = math.random() * math.pi * 2
				awayDir = Vector3.new(math.cos(angle), 0, math.sin(angle))
			end

			denizen:MoveTo(pos + awayDir * config.Distance)
			return nil
		end,
		Exit = function(denizen: any)
			if prevMoveSpeed ~= nil then
				denizen.ControllerManager.BaseMoveSpeed = prevMoveSpeed
				prevMoveSpeed = nil
			end
			denizen:StopMoving()
		end,
	}
end
