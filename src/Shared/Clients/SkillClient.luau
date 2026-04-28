--[=[
	@class SkillClient
	Client-side interface for the local player's skills. Reflects the server-driven `Skills` Comm property.
]=]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Comm = require(ReplicatedStorage.Packages.Comm)
local Observing = require(ReplicatedStorage.Shared.Observing)
local SkillTypes = require(ReplicatedStorage.Shared.Types.SkillTypes)

type Skills = SkillTypes.Skills

local SkillClient = {}

local skillsProperty

function SkillClient.Init()
	local clientComm = Comm.ClientComm.new(ReplicatedStorage, false, "Skill")
	skillsProperty = clientComm:GetProperty("Skills")
end

--[=[
	Returns the local player's current skills.
	@within SkillClient
	@return Skills
]=]
function SkillClient.Get(): Skills
	return skillsProperty:Get()
end

--[=[
	Observes changes to the local player's skills.

	`callback` is called immediately with the current value and again on every change.
	It may return a cleanup function that is called before the next invocation and on disconnect.
	@within SkillClient
	@param callback (skills: Skills) -> (() -> ())? -- Handler; may return a cleanup.
	@return () -> () -- Disconnects the observer when called.
]=]
function SkillClient.ObserveSkills(callback: (skills: Skills) -> (() -> ())?)
	return Observing.observeCommProperty(skillsProperty, callback)
end

return SkillClient
