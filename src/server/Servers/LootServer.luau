--!strict

--[=[
	@class LootServer
	Bridges denizen death and the `LootBag` component, and is the
	authoritative store for per-kill loot state.

	One map (`lootByInstance`) keyed by whichever instance currently
	owns the loot: the dying denizen model during the corpse phase, the
	spawned bag Part once the corpse despawns. `ResolvePendingDrop`
	transfers the entry from the denizen key to a freshly-created bag
	key in a single step; same data, new owner.

	Flow: `Denizen:Die` calls `RegisterPendingDrop` with the rolled
	per-player loot map. When the corpse finishes despawning,
	`DenizenCorpse` calls `ResolvePendingDrop`, which pops the pending
	entry and calls `SpawnBag`. `SpawnBag` creates the bag Part, records
	the loot under its key, and tags it `LootBag` so the component
	picks it up.

	The component (`LootBag`) is a view: it reads its loot via
	`GetBagLoot`, drives the per-player `Comm` property from that, and
	delegates claims to `ClaimOne` / `ClaimAll`. It owns its spatial
	concerns (distance check, lifetime, destroy) but not the loot data.
	On `LootBag:Stop` the component calls `DiscardBag` to release the
	server-side entry.
]=]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Workspace = game:GetService("Workspace")

local InventoryServer = require(ServerScriptService.Server.Servers.InventoryServer)
local LootTypes = require(ReplicatedStorage.Shared.Types.LootTypes)
local Parts = require(ReplicatedStorage.Shared.Parts)

type PlayerLoot = LootTypes.PlayerLoot
type PlayerLootMap = { [Player]: PlayerLoot }

local LootServer = {}

local lootByInstance: { [Instance]: PlayerLootMap } = {}
local bagsFolder: Folder

--[=[
	Creates the `LootBags` folder under Workspace for spawned bag parts.
	@within LootServer
]=]
function LootServer.Init()
	local existing = Workspace:FindFirstChild("LootBags") :: Folder?
	if existing ~= nil then
		bagsFolder = existing
		return
	end
	local folder = Instance.new("Folder")
	folder.Name = "LootBags"
	folder.Parent = Workspace
	bagsFolder = folder
end

--[=[
	Records a rolled per-player loot map for a dying denizen. The corpse
	component calls `ResolvePendingDrop` when the body finishes its
	death animation, at which point the bag is materialized.
	@within LootServer
	@param instance Instance -- The dying denizen model.
	@param playerLoot {[Player]: PlayerLoot}
]=]
function LootServer.RegisterPendingDrop(instance: Instance, playerLoot: PlayerLootMap)
	lootByInstance[instance] = playerLoot
end

--[=[
	Pops and materializes the pending drop for `instance`, if any.
	No-op when no entry exists (e.g. the denizen had no `LootTable` or
	every per-player roll came up empty).
	@within LootServer
	@param instance Instance
	@param cframe CFrame -- The spawn position for the resulting bag.
]=]
function LootServer.ResolvePendingDrop(instance: Instance, cframe: CFrame)
	local playerLoot = lootByInstance[instance]
	if playerLoot == nil then
		return
	end
	lootByInstance[instance] = nil
	LootServer.SpawnBag(cframe, playerLoot)
end

--[=[
	Materializes a `LootBag` at `cframe` with `playerLoot`. Constructs a
	transparent, anchored, non-collidable Part, records the loot keyed
	by the Part, and tags the Part `LootBag` so the component picks it
	up. The loot entry persists in `lootByInstance` until `DiscardBag` is
	called (which `LootBag:Stop` is responsible for).
	@within LootServer
	@param cframe CFrame
	@param playerLoot {[Player]: PlayerLoot}
]=]
function LootServer.SpawnBag(cframe: CFrame, playerLoot: PlayerLootMap)
	local part = Instance.new("Part")
	part.Name = "LootBag"
	part.Size = Vector3.new(1, 1, 1)
	part.CFrame = cframe
	Parts.MakeIntangible(part)
	part.Parent = bagsFolder

	lootByInstance[part] = playerLoot
	part:AddTag("LootBag")
end

--[=[
	Returns the per-player loot map for `bag`, or `nil` if no entry
	exists. Read-only — callers must not mutate the returned table;
	use `ClaimLoot` to remove a player's entry.
	@within LootServer
	@param bag Instance
	@return {[Player]: PlayerLoot}?
]=]
function LootServer.GetBagLoot(bag: Instance): PlayerLootMap?
	return lootByInstance[bag]
end

--[=[
	Returns `true` when `bag` has no remaining player entries (or no
	entry in the registry at all, e.g. already discarded).
	@within LootServer
	@param bag Instance
	@return boolean
]=]
function LootServer.IsBagEmpty(bag: Instance): boolean
	local map = lootByInstance[bag]
	return map == nil or next(map) == nil
end

--[=[
	Authoritative single-item claim. If `player` has an item at `index`
	in their pile and the inventory transfer succeeds, removes the item
	and returns `true`. Returns `false` when the bag/player has no
	entry, the index is out of range, or the inventory rejects the add
	(e.g. full).

	When `targetSlot` is provided (drag-to-specific-slot from the loot
	menu), tries `InsertItemAt` first; on failure falls back to the
	auto-slot `AddItem` path. Only when *both* fail does this return
	`false`.

	Spatial validation is the caller's responsibility — `LootBag`'s
	`HandleLoot*` paths do the distance check before reaching this
	point.
	@within LootServer
	@param bag Instance
	@param player Player
	@param index number -- 1-based index into the player's `PlayerLoot` array.
	@param targetSlot string? -- Optional preferred inventory slot.
	@return boolean
]=]
function LootServer.ClaimOne(bag: Instance, player: Player, index: number, targetSlot: string?): boolean
	local map = lootByInstance[bag]
	if map == nil then
		return false
	end
	local loot = map[player]
	if loot == nil then
		return false
	end
	local item = loot[index]
	if item == nil then
		return false
	end

	local placed = false
	if targetSlot ~= nil then
		placed = InventoryServer.InsertItemAt(player, targetSlot, item)
	end
	if not placed then
		placed = InventoryServer.AddItem(player, item.Kind, item.Count, item.Meta)
	end
	if not placed then
		return false
	end

	table.remove(loot, index)
	if #loot == 0 then
		map[player] = nil
	end
	return true
end

--[=[
	Authoritative bulk claim. Tries to transfer every item in `player`'s
	pile to inventory, in order. Items that fail to fit are left behind so
	the player can come back for them (or claim individually). Returns
	`true` if at least one item was claimed.
	@within LootServer
	@param bag Instance
	@param player Player
	@return boolean
]=]
function LootServer.ClaimAll(bag: Instance, player: Player): boolean
	local map = lootByInstance[bag]
	if map == nil then
		return false
	end
	local loot = map[player]
	if loot == nil then
		return false
	end

	local claimedAny = false
	-- Walk in reverse so in-place removals don't shift indexes we haven't
	-- visited yet.
	for i = #loot, 1, -1 do
		local item = loot[i]
		if InventoryServer.AddItem(player, item.Kind, item.Count, item.Meta) then
			table.remove(loot, i)
			claimedAny = true
		end
	end

	if #loot == 0 then
		map[player] = nil
	end
	return claimedAny
end

--[=[
	Releases the loot entry for `bag`. Called by `LootBag:Stop` so the
	server-side map doesn't accumulate dead-instance entries.
	@within LootServer
	@param bag Instance
]=]
function LootServer.DiscardBag(bag: Instance)
	lootByInstance[bag] = nil
end

return LootServer
