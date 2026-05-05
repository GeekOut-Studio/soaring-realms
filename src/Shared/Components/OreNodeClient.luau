--!strict

--[=[
	@class OreNodeClient
	@client
	Client-side companion to the server `OreNode` component. Subscribes to its Comm
	(`State`, `Break`, `Hit`) and tracks which entries the *local player* has
	recently mined. Each active entry registers a `Billboards` entry with an
	`OreNodeBillboard` renderer; entries auto-prune `BAR_VISIBILITY_SECONDS` after
	their last hit and unregister.

	State and break value updates flow through `OreNodeClient`'s own properties
	(re-exposing the Comm properties so renderers can read current values without
	holding a Comm handle directly) and through signal events. Renderers subscribe
	to those for per-frame updates without going through the registry.
]=]

local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Comm = require(ReplicatedStorage.Packages.Comm)
local Component = require(ReplicatedStorage.Packages.Component)
local React = require(ReplicatedStorage.Packages.React)
local Trove = require(ReplicatedStorage.Packages.Trove)

local Billboards = require(ReplicatedStorage.Shared.React.Billboards.Billboards)
local OreNodeBillboard = require(ReplicatedStorage.Shared.React.Billboards.OreNodeBillboard)

local e = React.createElement

local BAR_VISIBILITY_SECONDS = 5

--[=[
	@type State "Normal" | "Bonus" | "Depleted"
	@within OreNodeClient
]=]
export type State = "Normal" | "Bonus" | "Depleted"

--[=[
	@interface HitPayload
	@within OreNodeClient
	@field Root BasePart -- The mined entry's root part. Anchor for the billboard.
	@field EntryKey string -- `"Center"` or `"Bonus<i>"` (1-based).
	@field Progress number -- The local player's new progress on this entry, 0..1.
]=]
export type HitPayload = {
	Root: BasePart,
	EntryKey: string,
	Progress: number,
}

type ActiveEntry = {
	Root: BasePart,
	EntryKey: string,
	Progress: number,
	ExpireThread: thread?,
	BillboardKey: string,
}

local OreNodeClient = Component.new({
	Tag = "OreNode",
	Ancestors = { Workspace },
})

function OreNodeClient:Construct()
	self.Trove = Trove.new()
	self.ActiveEntries = {} :: { [BasePart]: ActiveEntry }
	self.Guid = HttpService:GenerateGUID(false)

	self.Comm = Comm.ClientComm.new(self.Instance, false, "OreNode")
	self.Trove:Add(self.Comm)
	self.StateProperty = self.Comm:GetProperty("State")
	self.BreakProperty = self.Comm:GetProperty("Break")
	self.HitSignal = self.Comm:GetSignal("Hit")

	self.HitSignal:Connect(function(payload: HitPayload)
		self:HandleHit(payload)
	end)
end

function OreNodeClient:Stop()
	for root, entry in self.ActiveEntries do
		Billboards.Remove(entry.BillboardKey)
		if entry.ExpireThread ~= nil then
			task.cancel(entry.ExpireThread)
		end
		self.ActiveEntries[root] = nil
	end
	self.Trove:Destroy()
end

--[=[
	Handles an incoming `Hit` signal. Records / refreshes the active entry, resets
	its expire timer, and registers a `Billboards` entry on first activation.
	@within OreNodeClient
	@param payload HitPayload
]=]
function OreNodeClient:HandleHit(payload: HitPayload)
	local root = payload.Root
	local existing = self.ActiveEntries[root]

	if existing == nil then
		local key = `OreNode:{self.Guid}:{HttpService:GenerateGUID(false)}`
		local entry: ActiveEntry = {
			Root = root,
			EntryKey = payload.EntryKey,
			Progress = payload.Progress,
			ExpireThread = nil,
			BillboardKey = key,
		}
		self.ActiveEntries[root] = entry
		Billboards.Set(key, {
			Adornee = root,
			Native = {},
			Render = function()
				return e(OreNodeBillboard, {
					Node = self,
					Root = root,
					EntryKey = payload.EntryKey,
					InitialProgress = payload.Progress,
				})
			end,
		})
		existing = entry
	else
		existing.EntryKey = payload.EntryKey
		existing.Progress = payload.Progress
	end

	if existing.ExpireThread ~= nil then
		task.cancel(existing.ExpireThread)
	end
	existing.ExpireThread = task.delay(BAR_VISIBILITY_SECONDS, function()
		self:ExpireEntry(root)
	end)
end

--[=[
	Removes the active entry tracking and its registered billboard for `root`.
	@within OreNodeClient
	@param root BasePart
]=]
function OreNodeClient:ExpireEntry(root: BasePart)
	local entry = self.ActiveEntries[root]
	if entry == nil then
		return
	end
	self.ActiveEntries[root] = nil
	Billboards.Remove(entry.BillboardKey)
end

return OreNodeClient
