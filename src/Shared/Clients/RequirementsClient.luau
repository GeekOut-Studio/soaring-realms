--!strict

--[=[
	@class RequirementsClient
	Client-side wrapper around the shared `Requirements` algorithm. Builds a
	`PlayerSnapshot` synchronously from the local Comm-replicated state
	(`SkillClient` / `InventoryClient` / `EquipmentClient`) and runs the check.

	Use `CheckForLocal` for one-shot checks. Use `ObserveLocal` to drive a UI
	gate (e.g. enabling/disabling a prompt) — it re-runs the check whenever any
	relevant input changes and invokes `callback(ok, message?)` each time.
]=]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Trove = require(ReplicatedStorage.Packages.Trove)

local EquipmentClient = require(ReplicatedStorage.Shared.Clients.EquipmentClient)
local InventoryClient = require(ReplicatedStorage.Shared.Clients.InventoryClient)
local Requirements = require(ReplicatedStorage.Shared.Requirements.Requirements)
local SkillClient = require(ReplicatedStorage.Shared.Clients.SkillClient)

type Cleanup = () -> ()

local RequirementsClient = {}

local function buildSnapshot(): Requirements.PlayerSnapshot
	return {
		Skills = SkillClient.Get(),
		Inventory = InventoryClient.Get(),
		Equipment = EquipmentClient.Get(),
	}
end

--[=[
	Returns `(ok: boolean, message: string?)` for `requirements` against the
	local player's currently-replicated state.
	@within RequirementsClient
	@client
	@param requirements {Requirement}
	@return (boolean, string?)
]=]
function RequirementsClient.CheckForLocal(requirements: { Requirements.Requirement }): (boolean, string?)
	return Requirements.Check(buildSnapshot(), requirements)
end

--[=[
	Subscribes to local Skills / Inventory / Equipment changes and invokes
	`callback(ok, message?)` immediately and on every change. Returns a function
	that disconnects all subscriptions when called.
	@within RequirementsClient
	@client
	@param requirements {Requirement}
	@param callback (ok: boolean, message: string?) -> ()
	@return () -> ()
]=]
function RequirementsClient.ObserveLocal(
	requirements: { Requirements.Requirement },
	callback: (ok: boolean, message: string?) -> ()
): Cleanup
	local trove = Trove.new()

	local function update()
		local ok, message = RequirementsClient.CheckForLocal(requirements)
		callback(ok, message)
	end

	trove:Add(SkillClient.ObserveSkills(function()
		update()
		return nil
	end))
	trove:Add(InventoryClient.ObserveInventory(function()
		update()
		return nil
	end))
	trove:Add(EquipmentClient.ObserveEquipment(function()
		update()
		return nil
	end))

	return trove:WrapClean()
end

return RequirementsClient
