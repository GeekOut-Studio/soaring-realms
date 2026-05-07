--!strict

--[=[
	@class Wander
	State factory for the `Wander` behavior. The denizen drifts to random points within
	`Radius` of its `SpawnPosition`, pausing for a random time between `PauseRange[1]` and
	`PauseRange[2]` seconds between picks.
]=]

--[=[
	@interface PauseRange
	@within Wander
	@field Min number -- Minimum seconds to pause between wander picks.
	@field Max number -- Maximum seconds to pause between wander picks.
]=]
export type PauseRange = {
	Min: number,
	Max: number,
}

--[=[
	@interface Config
	@within Wander
	@field Radius number -- Stud radius around `denizen.SpawnPosition` to pick wander points within.
	@field PauseRange PauseRange? -- Seconds-pause range between wander picks. Optional; defaults to `{Min = 1, Max = 3}`.
]=]
export type Config = {
	Kind: string,
	Radius: number,
	PauseRange: PauseRange?,
}

local function pickPoint(spawn: Vector3, radius: number): Vector3
	local angle = math.random() * math.pi * 2
	local r = math.random() * radius
	return spawn + Vector3.new(math.cos(angle) * r, 0, math.sin(angle) * r)
end

return function(config: Config)
	local pauseMin = if config.PauseRange ~= nil then config.PauseRange.Min else 1
	local pauseMax = if config.PauseRange ~= nil then config.PauseRange.Max else 3

	local pauseRemaining = 0

	return {
		Enter = function(_denizen: any)
			pauseRemaining = 0
		end,
		Update = function(denizen: any, dt: number): string?
			if denizen.MoveTarget ~= nil then
				return nil
			end

			pauseRemaining -= dt
			if pauseRemaining > 0 then
				return nil
			end

			pauseRemaining = pauseMin + math.random() * (pauseMax - pauseMin)
			denizen:MoveTo(pickPoint(denizen.SpawnPosition, config.Radius))
			return nil
		end,
		Exit = function(denizen: any)
			denizen:StopMoving()
		end,
	}
end
