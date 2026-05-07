--!strict

--[=[
	@class ReturnToSpawn
	State factory that walks the denizen back to its `SpawnPosition` and returns `"Idle"`
	when it arrives within `ArrivalRadius` studs.
]=]

--[=[
	@interface Config
	@within ReturnToSpawn
	@field ArrivalRadius number? -- How close to the spawn point counts as arrived. Defaults to 2.
	@field OnArrive string -- State to transition to once the denizen has arrived back at its spawn.
]=]
export type Config = {
	Kind: string,
	ArrivalRadius: number?,
	OnArrive: string,
}

return function(config: Config)
	local arrivalRadius = if config.ArrivalRadius ~= nil then config.ArrivalRadius else 2

	return {
		Enter = function(denizen: any)
			denizen.Target = nil
			denizen:MoveTo(denizen.SpawnPosition)
		end,
		Update = function(denizen: any, _dt: number): string?
			local pos = denizen.Instance:GetPivot().Position
			if (pos - denizen.SpawnPosition).Magnitude <= arrivalRadius then
				return config.OnArrive
			end
			if denizen.MoveTarget == nil then
				denizen:MoveTo(denizen.SpawnPosition)
			end
			return nil
		end,
		Exit = function(denizen: any)
			denizen:StopMoving()
		end,
	}
end
