--!strict

--[=[
	@class InventoryServer
	Manages player inventories: adding, removing, moving, and querying items.
	Reads and mutates `DataServer` synchronously; replicates the result via the
	`Inventory` Comm property after each commit.
]=]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Comm = require(ReplicatedStorage.Packages.Comm)
local Sift = require(ReplicatedStorage.Packages.Sift)
local t = require(ReplicatedStorage.Packages.t)

local DataServer = require(ServerScriptService.Server.Servers.DataServer)
local InventoryShared = require(ReplicatedStorage.Shared.InventoryShared)
local ItemDefs = require(ReplicatedStorage.Shared.Defs.ItemDefs)
local InventoryTypes = require(ReplicatedStorage.Shared.Types.InventoryTypes)

type Item = InventoryTypes.Item
type Inventory = InventoryTypes.Inventory

local InventoryServer = {}

local inventoryProperty

local function asInventory(data: any): Inventory
	return (data.Inventory :: any) :: Inventory
end

-- Commits a new inventory to DataServer and replicates it to the client.
-- Callers MUST have verified the player's data is loaded — `commit` asserts on
-- `UpdateData` returning nil so a missing pre-check fails loudly.
local function commit(player: Player, newInventory: Inventory)
	local committed = DataServer.UpdateData(player, function(data)
		return Sift.Dictionary.merge(data, { Inventory = newInventory })
	end)
	assert(committed ~= nil, "InventoryServer.commit: caller must verify DataServer.IsLoaded(player) first")
	inventoryProperty:SetFor(player, newInventory)
end

--[=[
	Returns the player's current inventory as a deeply frozen reference. If the
	player's data isn't loaded, returns the (also deeply frozen) default starting
	inventory — callers never receive nil and never crash. Mutation attempts error
	rather than silently corrupting the snapshot.
	@within InventoryServer
	@param player Player
	@return Inventory
]=]
function InventoryServer.GetInventory(player: Player): Inventory
	local data = DataServer.GetData(player)
	if data == nil then
		return InventoryTypes.DefaultInventory
	end
	return asInventory(data)
end

--[=[
	Adds items of `kind` to the player's inventory.

	Stackable items fill existing partial stacks with identical Meta first, then claim new slots.
	Non-stackable items each require their own slot.

	Atomic: either all items fit and are added, or none are.
	@within InventoryServer
	@param player Player
	@param kind string -- The item kind to add.
	@param count number? -- Number of items to add. Defaults to 1.
	@param meta {[string]: any}? -- Optional metadata. Stackable stacks only merge if Meta is identical.
	@return boolean -- `false` when the inventory cannot hold all items.
]=]
function InventoryServer.AddItem(player: Player, kind: string, count: number?, meta: { [string]: any }?): boolean
	local def = ItemDefs[kind]
	assert(def ~= nil, `InventoryServer.AddItem: unknown item kind {kind}`)

	local amount = count or 1
	assert(amount >= 1, "InventoryServer.AddItem: count must be >= 1")

	local data = DataServer.GetData(player)
	if data == nil then
		return false
	end
	local inventory: Inventory = Sift.Dictionary.copy(asInventory(data))

	if def.MaxStackSize ~= nil then
		local maxStackSize = def.MaxStackSize

		if InventoryShared.StackableCapacity(inventory, kind, maxStackSize, meta) < amount then
			return false
		end

		-- Fill existing partial stacks with matching Meta first.
		local remaining = amount
		for i = 1, InventoryTypes.Size do
			if remaining <= 0 then
				break
			end
			local key = tostring(i)
			local item = inventory[key]
			if item ~= nil and item.Kind == kind and InventoryShared.MetaEqual(item.Meta, meta) then
				local room = maxStackSize - (item.Count or 0)
				if room > 0 then
					local toAdd = math.min(room, remaining)
					inventory[key] = { Kind = kind, Count = (item.Count or 0) + toAdd, Meta = item.Meta }
					remaining -= toAdd
				end
			end
		end

		-- Claim empty slots for any remainder.
		for i = 1, InventoryTypes.Size do
			if remaining <= 0 then
				break
			end
			local key = tostring(i)
			if inventory[key] == nil then
				local toAdd = math.min(maxStackSize, remaining)
				inventory[key] = { Kind = kind, Count = toAdd, Meta = meta }
				remaining -= toAdd
			end
		end
	else
		if InventoryShared.CountFreeSlots(inventory) < amount then
			return false
		end

		local placed = 0
		for i = 1, InventoryTypes.Size do
			if placed >= amount then
				break
			end
			local key = tostring(i)
			if inventory[key] == nil then
				inventory[key] = { Kind = kind, Meta = meta }
				placed += 1
			end
		end
	end

	commit(player, inventory)
	return true
end

--[=[
	Inserts `item` at exactly `slotKey`. Strict: succeeds only when the
	target slot is empty, or when it holds the same stackable `Kind` with
	matching `Meta` and full room for `item.Count`. Anything else returns
	`false` — no swaps, no partial merges, no fallback to another slot.

	Callers that want "place here, otherwise anywhere" should fall back to
	`AddItem` on a `false` return. `LootServer.ClaimOne` does exactly that.
	@within InventoryServer
	@param player Player
	@param slotKey string -- Target slot key (`"1"`..`tostring(InventoryTypes.Size)`).
	@param item Item -- Stack-aware `Count` and `Meta` are honored.
	@return boolean
]=]
function InventoryServer.InsertItemAt(player: Player, slotKey: string, item: Item): boolean
	local def = ItemDefs[item.Kind]
	assert(def ~= nil, `InventoryServer.InsertItemAt: unknown item kind {item.Kind}`)

	local slotIndex = tonumber(slotKey)
	if slotIndex == nil or slotIndex < 1 or slotIndex > InventoryTypes.Size or slotIndex ~= math.floor(slotIndex) then
		return false
	end

	local data = DataServer.GetData(player)
	if data == nil then
		return false
	end
	local inventory: Inventory = Sift.Dictionary.copy(asInventory(data))
	local existing = inventory[slotKey]

	if existing == nil then
		inventory[slotKey] = { Kind = item.Kind, Count = item.Count, Meta = item.Meta }
	elseif
		def.MaxStackSize ~= nil
		and existing.Kind == item.Kind
		and InventoryShared.MetaEqual(existing.Meta, item.Meta)
	then
		local incomingCount = item.Count or 1
		local existingCount = existing.Count or 0
		if incomingCount > def.MaxStackSize - existingCount then
			return false
		end
		inventory[slotKey] = { Kind = existing.Kind, Count = existingCount + incomingCount, Meta = existing.Meta }
	else
		return false
	end

	commit(player, inventory)
	return true
end

--[=[
	Removes items from a specific inventory slot.

	For stackable items, reduces Count; clears the slot when Count reaches 0.
	For non-stackable items, clears the slot (`count` is ignored).
	@within InventoryServer
	@param player Player
	@param slot string -- The slot key to remove from.
	@param count number? -- Number of items to remove. Defaults to the full stack.
	@return boolean -- `false` when the slot is empty or count exceeds available.
]=]
function InventoryServer.RemoveItem(player: Player, slot: string, count: number?): boolean
	local data = DataServer.GetData(player)
	if data == nil then
		return false
	end
	local inventory: Inventory = asInventory(data)
	local item = inventory[slot]

	if item == nil then
		return false
	end

	local def = ItemDefs[item.Kind]
	assert(def ~= nil, `InventoryServer.RemoveItem: unknown item kind {item.Kind}`)

	local newInventory: Inventory = Sift.Dictionary.copy(inventory)

	if def.MaxStackSize ~= nil then
		local currentCount = item.Count or 0
		local toRemove = count or currentCount

		if toRemove > currentCount then
			return false
		end

		local remaining = currentCount - toRemove
		if remaining <= 0 then
			newInventory[slot] = nil
		else
			newInventory[slot] = { Kind = item.Kind, Count = remaining, Meta = item.Meta }
		end
	else
		newInventory[slot] = nil
	end

	commit(player, newInventory)
	return true
end

--[=[
	Moves the item in `fromSlot` to `toSlot`.

	- If `toSlot` is empty: simple move.
	- If `toSlot` holds the same stackable item with identical Meta: merges as many as fit;
	  any remainder stays in `fromSlot`.
	- Otherwise (different item, non-stackable, or mismatched Meta): swaps the two slots.
	@within InventoryServer
	@param player Player
	@param fromSlot string -- The slot to move from.
	@param toSlot string -- The slot to move to.
	@return boolean -- `false` when `fromSlot` is empty.
]=]
function InventoryServer.MoveItem(player: Player, fromSlot: string, toSlot: string): boolean
	if fromSlot == toSlot then
		return true
	end

	local data = DataServer.GetData(player)
	if data == nil then
		return false
	end
	local inventory: Inventory = asInventory(data)
	local fromItem = inventory[fromSlot]

	if fromItem == nil then
		return false
	end

	local def = ItemDefs[fromItem.Kind]
	assert(def ~= nil, `InventoryServer.MoveItem: unknown item kind {fromItem.Kind}`)

	local newInventory: Inventory = Sift.Dictionary.copy(inventory)
	local toItem = inventory[toSlot]

	if toItem == nil then
		newInventory[toSlot] = fromItem
		newInventory[fromSlot] = nil
	elseif
		def.MaxStackSize ~= nil
		and toItem.Kind == fromItem.Kind
		and InventoryShared.MetaEqual(toItem.Meta, fromItem.Meta)
	then
		-- Merge stacks; swap if destination is already full.
		local maxStackSize = def.MaxStackSize
		local fromCount = fromItem.Count or 0
		local toCount = toItem.Count or 0
		local room = maxStackSize - toCount

		if room <= 0 then
			newInventory[toSlot] = fromItem
			newInventory[fromSlot] = toItem
		else
			local transferred = math.min(room, fromCount)
			newInventory[toSlot] = { Kind = toItem.Kind, Count = toCount + transferred, Meta = toItem.Meta }
			local leftover = fromCount - transferred
			if leftover <= 0 then
				newInventory[fromSlot] = nil
			else
				newInventory[fromSlot] = { Kind = fromItem.Kind, Count = leftover, Meta = fromItem.Meta }
			end
		end
	else
		-- Swap (different items, non-stackable, or mismatched Meta).
		newInventory[toSlot] = fromItem
		newInventory[fromSlot] = toItem
	end

	commit(player, newInventory)
	return true
end

--[=[
	Splits exactly `count` items from `fromSlot` into `toSlot`.

	`fromSlot` must hold a stackable item with Count > count (the source is never fully emptied).
	`toSlot` must be empty or hold the same item kind with identical Meta and enough room.
	@within InventoryServer
	@param player Player
	@param fromSlot string -- The slot to split from.
	@param toSlot string -- The destination slot. Must be empty or hold the same item with room.
	@param count number -- Number of items to split off.
	@return boolean -- `false` when the split is not possible.
]=]
function InventoryServer.SplitStack(player: Player, fromSlot: string, toSlot: string, count: number): boolean
	if fromSlot == toSlot then
		return false
	end

	local data = DataServer.GetData(player)
	if data == nil then
		return false
	end
	local inventory: Inventory = asInventory(data)
	local fromItem = inventory[fromSlot]

	if fromItem == nil then
		return false
	end

	local def = ItemDefs[fromItem.Kind]
	assert(def ~= nil, `InventoryServer.SplitStack: unknown item kind {fromItem.Kind}`)

	if def.MaxStackSize == nil then
		return false
	end

	local fromCount = fromItem.Count or 0
	if count < 1 or count >= fromCount then
		return false
	end

	local toItem = inventory[toSlot]
	if toItem ~= nil then
		if toItem.Kind ~= fromItem.Kind or not InventoryShared.MetaEqual(toItem.Meta, fromItem.Meta) then
			return false
		end
		if (toItem.Count or 0) + count > def.MaxStackSize then
			return false
		end
	end

	local newInventory: Inventory = Sift.Dictionary.copy(inventory)
	newInventory[fromSlot] = { Kind = fromItem.Kind, Count = fromCount - count, Meta = fromItem.Meta }

	if toItem ~= nil then
		newInventory[toSlot] = { Kind = toItem.Kind, Count = (toItem.Count or 0) + count, Meta = toItem.Meta }
	else
		newInventory[toSlot] = { Kind = fromItem.Kind, Count = count, Meta = fromItem.Meta }
	end

	commit(player, newInventory)
	return true
end

--[=[
	Returns the total number of items of `kind` across all inventory slots.
	Sums `Count` for stackable items; counts one per slot for non-stackable items.
	@within InventoryServer
	@param player Player
	@param kind string -- The item kind to count.
	@return number
]=]
function InventoryServer.GetItemCount(player: Player, kind: string): number
	assert(ItemDefs[kind] ~= nil, `InventoryServer.GetItemCount: unknown item kind {kind}`)

	local data = DataServer.GetData(player)
	if data == nil then
		return 0
	end
	local inventory: Inventory = asInventory(data)
	local total = 0
	for i = 1, InventoryTypes.Size do
		local item = inventory[tostring(i)]
		if item ~= nil and item.Kind == kind then
			total += item.Count or 1
		end
	end
	return total
end

--[=[
	Returns whether the player has at least `count` items of `kind`.
	@within InventoryServer
	@param player Player
	@param kind string -- The item kind to check.
	@param count number? -- Minimum required quantity. Defaults to 1.
	@return boolean
]=]
function InventoryServer.HasItem(player: Player, kind: string, count: number?): boolean
	return InventoryServer.GetItemCount(player, kind) >= (count or 1)
end

--[=[
	Removes `count` items of `kind`, consuming from slot 1 upward.

	Atomic: checks total availability before removing anything.
	@within InventoryServer
	@param player Player
	@param kind string -- The item kind to remove.
	@param count number? -- Number of items to remove. Defaults to 1.
	@return boolean -- `false` when the player does not have enough items.
]=]
function InventoryServer.RemoveItemByKind(player: Player, kind: string, count: number?): boolean
	assert(ItemDefs[kind] ~= nil, `InventoryServer.RemoveItemByKind: unknown item kind {kind}`)

	local amount = count or 1
	assert(amount >= 1, "InventoryServer.RemoveItemByKind: count must be >= 1")

	local data = DataServer.GetData(player)
	if data == nil then
		return false
	end
	local inventory: Inventory = asInventory(data)

	local total = 0
	for i = 1, InventoryTypes.Size do
		local item = inventory[tostring(i)]
		if item ~= nil and item.Kind == kind then
			total += item.Count or 1
		end
	end

	if total < amount then
		return false
	end

	local newInventory: Inventory = Sift.Dictionary.copy(inventory)
	local remaining = amount

	for i = 1, InventoryTypes.Size do
		if remaining <= 0 then
			break
		end
		local key = tostring(i)
		local item = newInventory[key]
		if item ~= nil and item.Kind == kind then
			local slotCount = item.Count or 1
			if slotCount <= remaining then
				newInventory[key] = nil
				remaining -= slotCount
			else
				newInventory[key] = { Kind = item.Kind, Count = slotCount - remaining, Meta = item.Meta }
				remaining = 0
			end
		end
	end

	commit(player, newInventory)
	return true
end

--[=[
	Replicates `inventory` to the player's `Inventory` Comm property without
	writing to DataServer. Use this from sibling servers (e.g. `EquipmentServer`)
	that perform their own atomic cross-table commit through `DataServer.UpdateData`
	and only need to push the resulting inventory state to the client.
	@within InventoryServer
	@param player Player
	@param inventory Inventory
]=]
function InventoryServer.ReplicateInventory(player: Player, inventory: Inventory)
	inventoryProperty:SetFor(player, inventory)
end

function InventoryServer.Init()
	local serverComm = Comm.ServerComm.new(ReplicatedStorage, "Inventory")
	inventoryProperty = serverComm:CreateProperty("Inventory", InventoryTypes.DefaultInventory)

	serverComm:BindFunction("MoveItem", function(player, fromSlot, toSlot)
		if not t.string(fromSlot) then
			return
		end
		if not t.string(toSlot) then
			return
		end

		return InventoryServer.MoveItem(player, fromSlot, toSlot)
	end)

	serverComm:BindFunction("DropItem", function(player, slot)
		if not t.string(slot) then
			return
		end

		return InventoryServer.RemoveItem(player, slot)
	end)

	DataServer.ObservePlayer(function(player, data)
		inventoryProperty:SetFor(player, asInventory(data))
		return nil
	end)
end

return InventoryServer
