--!strict

--[=[
	@class TreeNodeClient
	Client-side companion to the server `TreeNode` component. Subscribes to its
	Comm (`State`, `Cut`, `Hit`) and tracks which entries the *local player* has
	recently cut. Each active entry registers a `Billboards` entry with a
	`TreeNodeBillboard` renderer; entries auto-prune `BAR_VISIBILITY_SECONDS`
	after their last hit and unregister.

	State and cut value updates flow through `TreeNodeClient`'s own properties
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
local TreeNodeBillboard = require(ReplicatedStorage.Shared.React.Billboards.TreeNodeBillboard)

local e = React.createElement

local BAR_VISIBILITY_SECONDS = 5

--[=[
	@type State "Normal" | "Bonus" | "Depleted"
	@within TreeNodeClient
]=]
export type State = "Normal" | "Bonus" | "Depleted"

--[=[
	@interface HitPayload
	@within TreeNodeClient
	@field Root BasePart -- The cut entry's root part. Anchor for the billboard.
	@field EntryKey string -- `"Stump"` or `"Trunk"`.
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

local TreeNodeClient = Component.new({
	Tag = "TreeNode",
	Ancestors = { Workspace },
})

function TreeNodeClient:Construct()
	self.Trove = Trove.new()
	self.ActiveEntries = {} :: { [BasePart]: ActiveEntry }
	self.Guid = HttpService:GenerateGUID(false)

	self.Comm = Comm.ClientComm.new(self.Instance, false, "TreeNode")
	self.Trove:Add(self.Comm)
	self.StateProperty = self.Comm:GetProperty("State")
	self.CutProperty = self.Comm:GetProperty("Cut")
	self.HitSignal = self.Comm:GetSignal("Hit")

	self.HitSignal:Connect(function(payload: HitPayload)
		self:HandleHit(payload)
	end)
end

function TreeNodeClient:Stop()
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
	@within TreeNodeClient
	@param payload HitPayload
]=]
function TreeNodeClient:HandleHit(payload: HitPayload)
	local root = payload.Root
	local existing = self.ActiveEntries[root]

	if existing == nil then
		local key = `TreeNode:{self.Guid}:{HttpService:GenerateGUID(false)}`
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
				return e(TreeNodeBillboard, {
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
	@within TreeNodeClient
	@param root BasePart
]=]
function TreeNodeClient:ExpireEntry(root: BasePart)
	local entry = self.ActiveEntries[root]
	if entry == nil then
		return
	end
	self.ActiveEntries[root] = nil
	Billboards.Remove(entry.BillboardKey)
end

return TreeNodeClient
