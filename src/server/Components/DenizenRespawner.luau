--!strict

--[=[
	@class DenizenRespawner
	Server component for a `Folder` (or `Model`) in Workspace tagged
	`DenizenRespawner`. Wraps one or more *untagged* denizen model children;
	on `Construct` it snapshots each child as a pristine template, tags the
	original as `Denizen` (so the standard `Denizen` component picks it up),
	and watches for the live instance leaving the data model. When a live
	denizen is destroyed, the respawner schedules a re-clone from the stored
	template after the slot's `RespawnTime` and re-tags the clone.

	Studio authoring contract:
	- Create a `Folder` (or `Model`) under Workspace, tag it `DenizenRespawner`.
	- Drop one or more denizen `Model` children inside. Each child must satisfy
	  the `Denizen` component's contract (`DenizenKind` attribute, `PrimaryPart`
	  set on an unanchored part). Children must **not** carry the `Denizen` tag
	  themselves — the respawner is responsible for tagging.
	- Optional per-child attribute `RespawnTime` (number, seconds). Defaults to
	  `DEFAULT_RESPAWN_TIME` when absent.

	The "untagged template" rule is what makes this safe: the stored template
	is never seen by `Denizen.Construct`, so no `ControllerManager` /
	`GroundSensor` mutations ever pollute it. Each respawn clones from the
	pristine snapshot, not from a live instance.

	Authoring violations (a child already tagged `Denizen` at `Construct` time)
	are loudly warned and the offending child is skipped — its model has
	already been mutated by `Denizen.Construct`, so a clone of it would carry
	those mutations forward into every respawn.
]=]

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Component = require(ReplicatedStorage.Packages.Component)
local Trove = require(ReplicatedStorage.Packages.Trove)

local DEFAULT_RESPAWN_TIME = 10

--[=[
	@interface Slot
	@within DenizenRespawner
	@field Trove any -- Per-slot sub-trove (extended from the component's trove). Owns the template, the live AncestryChanged watch, and any pending respawn thread.
	@field Template Model -- The pristine, never-tagged snapshot used as the source for every respawn.
	@field SpawnCFrame CFrame -- Author-placed pivot, captured once at Construct.
	@field RespawnTime number -- Seconds between death and respawn for this slot.
	@field Live Model? -- The currently in-world instance, or `nil` while a respawn is pending.
	@field RespawnThread thread? -- Active `task.delay` handle for the pending respawn.
	@field WatchConn RBXScriptConnection? -- AncestryChanged connection on `Live`.
]=]
type Slot = {
	Trove: any,
	Template: Model,
	SpawnCFrame: CFrame,
	RespawnTime: number,
	Live: Model?,
	RespawnThread: thread?,
	WatchConn: RBXScriptConnection?,
}

local DenizenRespawner = Component.new({
	Tag = "DenizenRespawner",
	Ancestors = { Workspace },
})

function DenizenRespawner:Construct()
	self.Trove = Trove.new()
	self.Slots = {} :: { Slot }

	for _, child in self.Instance:GetChildren() do
		if not child:IsA("Model") then
			continue
		end

		if CollectionService:HasTag(child, "Denizen") then
			warn(
				`DenizenRespawner: child {child:GetFullName()} already has the "Denizen" tag and will NOT respawn. `
					.. `The Denizen component has already mutated this model, so any snapshot taken now would be polluted.`
					.. `REMOVE the "Denizen" tag from this child — the DenizenRespawner is responsible for tagging its children.`
			)
			continue
		end

		local respawnTimeAttr = child:GetAttribute("RespawnTime")
		local respawnTime = if type(respawnTimeAttr) == "number" then respawnTimeAttr else DEFAULT_RESPAWN_TIME

		local slotTrove = self.Trove:Extend()
		local template = child:Clone()
		template.Parent = nil
		slotTrove:Add(template)

		local slot: Slot = {
			Trove = slotTrove,
			Template = template,
			SpawnCFrame = child:GetPivot(),
			RespawnTime = respawnTime,
			Live = child,
			RespawnThread = nil,
			WatchConn = nil,
		}
		table.insert(self.Slots, slot)

		self:WatchSlot(slot)
		CollectionService:AddTag(child, "Denizen")
	end
end

function DenizenRespawner:Stop()
	self.Trove:Destroy()
end

--[=[
	Connects an `AncestryChanged` watch on `slot.Live`; when the live instance
	is removed from the data model (e.g. via `Denizen:Die` → `Destroy`),
	`HandleDeath` runs.

	Uses `AncestryChanged` + a nil-parent check rather than `Destroying` —
	`Destroying` misses some teardown paths (chained destructions, certain
	`ClearAllChildren` flows) that `AncestryChanged` catches.
	@within DenizenRespawner
	@param slot Slot
]=]
function DenizenRespawner:WatchSlot(slot: Slot)
	local live = slot.Live
	assert(live ~= nil, "DenizenRespawner:WatchSlot called with no Live instance")

	slot.WatchConn = slot.Trove:Connect(live.AncestryChanged, function()
		if live.Parent ~= nil then
			return
		end
		self:HandleDeath(slot)
	end)
end

--[=[
	Disconnects the death watch and schedules a respawn for `slot` after
	`slot.RespawnTime` seconds.
	@within DenizenRespawner
	@param slot Slot
]=]
function DenizenRespawner:HandleDeath(slot: Slot)
	if slot.WatchConn ~= nil then
		slot.Trove:Remove(slot.WatchConn)
		slot.WatchConn = nil
	end
	-- Drop the prior cycle's finished thread from the trove before queuing the new
	-- one. `task.cancel` on a dead thread is a no-op, so this is safe; we just want
	-- the trove's internal list not to accumulate one stale ref per death cycle.
	if slot.RespawnThread ~= nil then
		slot.Trove:Remove(slot.RespawnThread)
	end
	slot.Live = nil
	slot.RespawnThread = slot.Trove:Add(task.delay(slot.RespawnTime, function()
		self:Respawn(slot)
	end))
end

--[=[
	Clones the slot's pristine template, places it at `SpawnCFrame`, parents
	it under the respawner, tags it `Denizen`, and re-arms the death watch.
	@within DenizenRespawner
	@param slot Slot
]=]
function DenizenRespawner:Respawn(slot: Slot)
	local clone = slot.Template:Clone()
	clone:PivotTo(slot.SpawnCFrame)
	clone.Parent = self.Instance

	slot.Live = clone
	self:WatchSlot(slot)
	CollectionService:AddTag(clone, "Denizen")
end

return DenizenRespawner
