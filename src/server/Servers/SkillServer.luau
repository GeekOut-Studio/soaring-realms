--!strict

--[=[
	@class SkillServer
	Manages player skills: tracking accumulated experience and the derived level
	for each `SkillKind`. Experience is monotonically non-decreasing; levels are
	computed from experience via `SkillExperience`.
]=]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Comm = require(ReplicatedStorage.Packages.Comm)
local Sift = require(ReplicatedStorage.Packages.Sift)
local Signal = require(ReplicatedStorage.Packages.Signal)

local DataServer = require(ServerScriptService.Server.Servers.DataServer)
local SkillExperience = require(ReplicatedStorage.Shared.SkillExperience)
local SkillTypes = require(ReplicatedStorage.Shared.Types.SkillTypes)

type Skill = SkillTypes.Skill
type Skills = SkillTypes.Skills
type SkillKind = SkillTypes.SkillKind

local SkillServer = {}

local skillsProperty
local leveledUp = Signal.new() :: Signal.Signal<Player, SkillKind, number>

--[=[
	@prop LeveledUp Signal<Player, SkillKind, number>
	@within SkillServer
	Fires whenever a call to `AddExperience` results in a strictly higher level
	for the affected skill. Signature: `(player, skillKind, newLevel)`. Fires once
	per call regardless of how many levels were gained.
]=]
SkillServer.LeveledUp = leveledUp

local function asSkills(data: any): Skills
	return (data.Skills :: any) :: Skills
end

-- Commits new skills to DataServer and replicates to the client. Callers MUST
-- have verified the player's data is loaded.
local function commit(player: Player, newSkills: Skills)
	local committed = DataServer.UpdateData(player, function(data)
		return Sift.Dictionary.merge(data, { Skills = newSkills })
	end)
	assert(committed ~= nil, "SkillServer.commit: caller must verify DataServer.IsLoaded(player) first")
	skillsProperty:SetFor(player, newSkills)
end

--[=[
	Returns a shallow copy of the player's current skills. If the player's data
	isn't loaded, returns a copy of the default skills (every skill at level 1,
	zero experience) — callers never receive nil and never crash.
	@within SkillServer
	@param player Player
	@return Skills
]=]
function SkillServer.GetSkills(player: Player): Skills
	local data = DataServer.GetData(player)
	if data == nil then
		return Sift.Dictionary.copy(SkillTypes.DefaultSkills)
	end
	return Sift.Dictionary.copy(asSkills(data))
end

--[=[
	Adds `amount` experience to `kind` for `player`. Recomputes the level from
	the new cumulative experience and fires `LeveledUp` once if the level strictly
	increased. Returns `false` (without writing or firing `LeveledUp`) if the
	player's data isn't loaded.
	@within SkillServer
	@param player Player
	@param kind SkillKind
	@param amount number -- Must be positive.
	@return boolean
]=]
function SkillServer.AddExperience(player: Player, kind: SkillKind, amount: number): boolean
	assert(SkillTypes.KindSet[kind], `SkillServer.AddExperience: unknown skill kind {tostring(kind)}`)
	assert(amount > 0, "SkillServer.AddExperience: amount must be > 0")

	local data = DataServer.GetData(player)
	if data == nil then
		return false
	end
	local skills: Skills = asSkills(data)
	local current = skills[kind]

	local oldLevel = 1
	local oldExperience = 0
	if current ~= nil then
		oldLevel = current.Level
		oldExperience = current.Experience
	end

	local newExperience = oldExperience + amount
	local newLevel = SkillExperience.LevelForExperience(newExperience)

	local newSkills: Skills = Sift.Dictionary.copy(skills)
	newSkills[kind] = {
		Level = newLevel,
		Experience = newExperience,
	}

	commit(player, newSkills)
	if newLevel > oldLevel then
		leveledUp:Fire(player, kind, newLevel)
	end
	return true
end

function SkillServer.Init()
	local serverComm = Comm.ServerComm.new(ReplicatedStorage, "Skill")
	skillsProperty = serverComm:CreateProperty("Skills", SkillTypes.DefaultSkills)

	DataServer.ObservePlayer(function(player, data)
		skillsProperty:SetFor(player, asSkills(data))
		return nil
	end)
end

return SkillServer
