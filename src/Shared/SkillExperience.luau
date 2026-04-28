--!strict

--[=[
	@class SkillExperience
	Experience-curve helpers matching the Old School RuneScape progression.

	The threshold for level `L` is:

	```
	XP[L] = floor((1 / 4) * sum from x = 1 to L - 1 of floor(x + 300 * 2 ^ (x / 7)))
	```

	Sample values: `XP[1] = 0`, `XP[2] = 83`, `XP[3] = 174`, `XP[99] = 13_034_431`.
]=]

local SkillExperience = {}

--[=[
	@prop MaxLevel number
	@within SkillExperience
	The highest level the curve is precomputed for. Levels above this clamp to the
	`MaxLevel` threshold.
]=]
SkillExperience.MaxLevel = 99

local thresholds: { number } = {}

do
	local total = 0
	thresholds[1] = 0
	for level = 2, SkillExperience.MaxLevel do
		local x = level - 1
		total += math.floor(x + 300 * 2 ^ (x / 7))
		thresholds[level] = math.floor(total / 4)
	end
end

--[=[
	Returns the cumulative experience required to reach `level`.

	`level` is clamped to `[1, MaxLevel]`; out-of-range values return the corresponding
	endpoint threshold.
	@within SkillExperience
	@param level number
	@return number
]=]
function SkillExperience.ExperienceForLevel(level: number): number
	if level <= 1 then
		return 0
	end
	if level > SkillExperience.MaxLevel then
		return thresholds[SkillExperience.MaxLevel]
	end
	return thresholds[level]
end

--[=[
	Returns the level corresponding to a given accumulated experience total.

	Caps at `MaxLevel`. Negative inputs return `1`.
	@within SkillExperience
	@param experience number
	@return number
]=]
function SkillExperience.LevelForExperience(experience: number): number
	for level = SkillExperience.MaxLevel, 1, -1 do
		if experience >= thresholds[level] then
			return level
		end
	end
	return 1
end

return SkillExperience
