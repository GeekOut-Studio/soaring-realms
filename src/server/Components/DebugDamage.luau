--!strict

--[=[
	@class DebugDamage
	Component placed on tagged parts that deal a fixed amount of damage to any Outworlder
	character that touches them, with a per-character cooldown so repeated touches in the
	same step don't burst-damage the player.
]=]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Workspace = game:GetService("Workspace")

local Component = require(ReplicatedStorage.Packages.Component)
local Trove = require(ReplicatedStorage.Packages.Trove)

local DamageServer = require(ServerScriptService.Server.Servers.DamageServer)
local Outworlder = require(ServerScriptService.Server.Components.Outworlder)

local DAMAGE = 10
local COOLDOWN = 1

local DebugDamage = Component.new({
	Tag = "DebugDamage",
	Ancestors = { Workspace },
})

--[=[
	@prop Cooldown {[Model]: true}
	@within DebugDamage
	Set of characters currently on cooldown. Entries are removed by `task.delay` callbacks
	scheduled when damage is dealt.
]=]

function DebugDamage:Construct()
	self.Trove = Trove.new()
	self.Cooldown = {} :: { [Model]: true }
end

function DebugDamage:Start()
	self.Trove:Connect(self.Instance.Touched, function(otherPart: BasePart)
		self:HandleTouched(otherPart)
	end)
end

function DebugDamage:Stop()
	self.Trove:Destroy()
end

--[=[
	Resolves `otherPart`'s character, gates on the per-character cooldown, and applies
	damage via the character's Outworlder.
	@within DebugDamage
	@param otherPart BasePart
]=]
function DebugDamage:HandleTouched(otherPart: BasePart)
	local character = otherPart:FindFirstAncestorOfClass("Model")
	if character == nil or Players:GetPlayerFromCharacter(character) == nil then
		return
	end

	if self.Cooldown[character] then
		return
	end

	local outworlder = Outworlder:FromInstance(character)
	if outworlder == nil then
		return
	end

	self.Cooldown[character] = true
	task.delay(COOLDOWN, function()
		self.Cooldown[character] = nil
	end)
	DamageServer.Damage({
		Amount = DAMAGE,
		Type = "Crushing",
		Target = outworlder,
	})
end

return DebugDamage
