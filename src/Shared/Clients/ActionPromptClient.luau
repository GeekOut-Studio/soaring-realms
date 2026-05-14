--!strict

--[=[
	@class ActionPromptClient
	Singleton that owns the local-player visibility gate for every
	`"ActionPrompt"`-tagged `ProximityPrompt` in the world. Action prompts are
	the prompts that start an `Outworlder` action (mining, woodcutting, …); the
	gate hides them while the local player is already executing an action so the
	player can't queue a second one.

	The gate combines two inputs:
	- `ServerEnabled` (per-prompt attribute, authored by the prompt's server-side
	  owner, e.g. `OreNode` / `TreeNode`): whether the owner wants this prompt
	  to be active given the world state (node phase, etc.).
	- `inAction` (local-player-only): mirrored from the local `OutworlderClient`'s
	  `InActionProperty`.

	The actual `prompt.Enabled` is written locally by this module as
	`ServerEnabled and not inAction`. Owners must never write `prompt.Enabled`
	directly — they only set the attribute and let this module derive the final
	visibility. Client-local property writes don't replicate, so each player's
	gate is independent.
]=]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Observers = require(ReplicatedStorage.Packages.Observers)
local Trove = require(ReplicatedStorage.Packages.Trove)

local ActionPrompts = require(ReplicatedStorage.Shared.ActionPrompts)
local OutworlderClient = require(ReplicatedStorage.Shared.Components.OutworlderClient)

local ActionPromptClient = {}

local inAction = false
local trackedPrompts: { [ProximityPrompt]: RBXScriptConnection? } = {}

local function apply(prompt: ProximityPrompt)
	local serverEnabled = prompt:GetAttribute(ActionPrompts.Attribute)
	prompt.Enabled = (serverEnabled ~= false) and not inAction
end

local function applyAll()
	for prompt in trackedPrompts do
		apply(prompt)
	end
end

local function track(instance: Instance)
	if not instance:IsA("ProximityPrompt") then
		return
	end
	local prompt = instance :: ProximityPrompt
	if trackedPrompts[prompt] ~= nil then
		return
	end
	trackedPrompts[prompt] = prompt:GetAttributeChangedSignal(ActionPrompts.Attribute):Connect(function()
		apply(prompt)
	end)
	apply(prompt)
end

local function untrack(instance: Instance)
	if not instance:IsA("ProximityPrompt") then
		return
	end
	local prompt = instance :: ProximityPrompt
	local connection = trackedPrompts[prompt]
	if connection == nil then
		return
	end
	connection:Disconnect()
	trackedPrompts[prompt] = nil
end

--[=[
	Initializes the gate. Must be called once from the client bootstrap.
	@within ActionPromptClient
]=]
function ActionPromptClient.Init()
	for _, instance in CollectionService:GetTagged(ActionPrompts.Tag) do
		track(instance)
	end
	CollectionService:GetInstanceAddedSignal(ActionPrompts.Tag):Connect(track)
	CollectionService:GetInstanceRemovedSignal(ActionPrompts.Tag):Connect(untrack)

	Observers.observeCharacter(function(player: Player, character: Model)
		if player ~= Players.LocalPlayer then
			return
		end
		local trove = Trove.new()
		trove:AddPromise(OutworlderClient:WaitForInstance(character):andThen(function(componentInstance)
			trove:Add(componentInstance.InActionProperty:Observe(function(value: boolean)
				if value == inAction then
					return
				end
				inAction = value
				applyAll()
			end))
		end))
		trove:Add(function()
			-- On character despawn, fall back to "not in action" so prompts don't
			-- stay hidden across respawn until the new OutworlderClient appears.
			if inAction then
				inAction = false
				applyAll()
			end
		end)
		return trove:WrapClean() :: () -> ()
	end)
end

return ActionPromptClient
