--!strict

--[=[
	@class SkillServer
	Manages player skills: tracking accumulated experience and the derived level for each
	`SkillKind`. Experience is monotonically non-decreasing; levels are computed from
	experience via `SkillExperience`.
]=]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Comm = require(ReplicatedStorage.Packages.Comm)
local Observers = require(ReplicatedStorage.Packages.Observers)
local Promise = require(ReplicatedStorage.Packages.Promise)
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
	Fires whenever a call to `AddExperience` results in a strictly higher level for the
	affected skill. Signature: `(player, skillKind, newLevel)`. Fires once per call regardless
	of how many levels were gained.
]=]
SkillServer.LeveledUp = leveledUp

local function asSkills(data: any): Skills
	return (data.Skills :: any) :: Skills
end

local function commit(player: Player, newSkills: Skills)
	return DataServer.UpdateData(player, function(data)
		return Sift.Dictionary.merge(data, { Skills = newSkills })
	end):andThen(function()
		skillsProperty:SetFor(player, newSkills)
		return true
	end)
end

--[=[
	Returns a shallow copy of the player's current skills.
	@within SkillServer
	@param player Player
	@return Promise<Skills>
]=]
function SkillServer.GetSkills(player: Player): any
	return DataServer.GetData(player):andThen(function(data)
		return Sift.Dictionary.copy(asSkills(data))
	end)
end

--[=[
	Adds `amount` experience to `kind` for `player`. Recomputes the level from the new
	cumulative experience and fires `LeveledUp` once if the level strictly increased.
	@within SkillServer
	@param player Player
	@param kind SkillKind
	@param amount number -- Must be positive.
	@return Promise<boolean>
]=]
function SkillServer.AddExperience(player: Player, kind: SkillKind, amount: number): any
	if not SkillTypes.KindSet[kind] then
		return Promise.reject("Unknown skill kind: " .. tostring(kind))
	end
	if amount <= 0 then
		return Promise.reject("Experience amount must be > 0")
	end

	return DataServer.GetData(player):andThen(function(data)
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

		return commit(player, newSkills):andThen(function()
			if newLevel > oldLevel then
				leveledUp:Fire(player, kind, newLevel)
			end
			return true
		end)
	end)
end

function SkillServer.Init()
	local serverComm = Comm.ServerComm.new(ReplicatedStorage, "Skill")
	skillsProperty = serverComm:CreateProperty("Skills", SkillTypes.DefaultSkills)

	Observers.observePlayer(function(player)
		SkillServer.GetSkills(player):andThen(function(skills)
			skillsProperty:SetFor(player, skills)
		end)
		return nil
	end)
end

return SkillServer
