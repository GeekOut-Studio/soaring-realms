--!strict

--[=[
	@class InventoryServer
	Manages player inventories: adding, removing, moving, and querying items.
	Interfaces with DataServer for persistence.
]=]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Comm = require(ReplicatedStorage.Packages.Comm)
local Observers = require(ReplicatedStorage.Packages.Observers)
local Promise = require(ReplicatedStorage.Packages.Promise)
local Sift = require(ReplicatedStorage.Packages.Sift)
local t = require(ReplicatedStorage.Packages.t)

local DataServer = require(ServerScriptService.Server.Servers.DataServer)
local ItemDefs = require(ReplicatedStorage.Shared.Defs.ItemDefs)
local InventoryTypes = require(ReplicatedStorage.Shared.Types.InventoryTypes)

type Item = InventoryTypes.Item
type Inventory = InventoryTypes.Inventory

local InventoryServer = {}

local inventoryProperty

-- Private helpers

local function asInventory(data: any): Inventory
	return (data.Inventory :: any) :: Inventory
end

-- Recursive deep equality used to determine whether two Meta tables match,
-- and therefore whether two stacks of the same kind can be merged.
local function metaEqual(a: { [string]: any }?, b: { [string]: any }?): boolean
	if a == b then
		return true
	end
	if a == nil or b == nil then
		return false
	end
	for k, v in a do
		local bv = b[k]
		if type(v) == "table" then
			if not metaEqual(v :: any, bv :: any) then
				return false
			end
		elseif bv ~= v then
			return false
		end
	end
	for k in b do
		if a[k] == nil then
			return false
		end
	end
	return true
end

local function countFreeSlots(inventory: Inventory): number
	local count = 0
	for i = 1, InventoryTypes.Size do
		if inventory[tostring(i)] == nil then
			count += 1
		end
	end
	return count
end

-- Computes how many more items of a stackable kind with matching Meta can fit.
local function stackableCapacity(
	inventory: Inventory,
	kind: string,
	maxStackSize: number,
	meta: { [string]: any }?
): number
	local capacity = 0
	for i = 1, InventoryTypes.Size do
		local item = inventory[tostring(i)]
		if item == nil then
			capacity += maxStackSize
		elseif item.Kind == kind and metaEqual(item.Meta, meta) then
			capacity += maxStackSize - (item.Count or 0)
		end
	end
	return capacity
end

-- Commits a new inventory to DataServer, replicates it to the client, and resolves true.
local function commit(player: Player, newInventory: Inventory)
	return DataServer.UpdateData(player, function(data)
		return Sift.Dictionary.merge(data, { Inventory = newInventory })
	end):andThen(function()
		inventoryProperty:SetFor(player, newInventory)
		return true
	end)
end

--[=[
	Returns a shallow copy of the player's current inventory.
	@within InventoryServer
	@param player Player
	@return Promise<Inventory>
]=]
function InventoryServer.GetInventory(player: Player): any
	return DataServer.GetData(player):andThen(function(data)
		return Sift.Dictionary.copy(asInventory(data))
	end)
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
	@return Promise<boolean> -- Resolves `false` when the inventory cannot hold all items.
]=]
function InventoryServer.AddItem(player: Player, kind: string, count: number?, meta: { [string]: any }?): any
	local def = ItemDefs[kind]
	if def == nil then
		return Promise.reject("Unknown item kind: " .. kind)
	end

	local amount = count or 1
	if amount < 1 then
		return Promise.reject("Count must be >= 1")
	end

	return DataServer.GetData(player):andThen(function(data)
		local inventory: Inventory = Sift.Dictionary.copy(asInventory(data))

		if def.MaxStackSize ~= nil then
			local maxStackSize = def.MaxStackSize

			if stackableCapacity(inventory, kind, maxStackSize, meta) < amount then
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
				if item ~= nil and item.Kind == kind and metaEqual(item.Meta, meta) then
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
			if countFreeSlots(inventory) < amount then
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

		return commit(player, inventory)
	end)
end

--[=[
	Removes items from a specific inventory slot.

	For stackable items, reduces Count; clears the slot when Count reaches 0.
	For non-stackable items, clears the slot (`count` is ignored).
	@within InventoryServer
	@param player Player
	@param slot string -- The slot key to remove from.
	@param count number? -- Number of items to remove. Defaults to the full stack.
	@return Promise<boolean> -- Resolves `false` when the slot is empty or count exceeds available.
]=]
function InventoryServer.RemoveItem(player: Player, slot: string, count: number?): any
	return DataServer.GetData(player):andThen(function(data)
		local inventory: Inventory = asInventory(data)
		local item = inventory[slot]

		if item == nil then
			return false
		end

		local def = ItemDefs[item.Kind]
		if def == nil then
			return Promise.reject("Unknown item kind: " .. item.Kind)
		end

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

		return commit(player, newInventory)
	end)
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
	@return Promise<boolean> -- Resolves `false` when `fromSlot` is empty.
]=]
function InventoryServer.MoveItem(player: Player, fromSlot: string, toSlot: string): any
	if fromSlot == toSlot then
		return Promise.resolve(true)
	end

	return DataServer.GetData(player):andThen(function(data)
		local inventory: Inventory = asInventory(data)
		local fromItem = inventory[fromSlot]

		if fromItem == nil then
			return false
		end

		local def = ItemDefs[fromItem.Kind]
		if def == nil then
			return Promise.reject("Unknown item kind: " .. fromItem.Kind)
		end

		local newInventory: Inventory = Sift.Dictionary.copy(inventory)
		local toItem = inventory[toSlot]

		if toItem == nil then
			newInventory[toSlot] = fromItem
			newInventory[fromSlot] = nil
		elseif def.MaxStackSize ~= nil and toItem.Kind == fromItem.Kind and metaEqual(toItem.Meta, fromItem.Meta) then
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

		return commit(player, newInventory)
	end)
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
	@return Promise<boolean> -- Resolves `false` when the split is not possible.
]=]
function InventoryServer.SplitStack(player: Player, fromSlot: string, toSlot: string, count: number): any
	if fromSlot == toSlot then
		return Promise.resolve(false)
	end

	return DataServer.GetData(player):andThen(function(data)
		local inventory: Inventory = asInventory(data)
		local fromItem = inventory[fromSlot]

		if fromItem == nil then
			return false
		end

		local def = ItemDefs[fromItem.Kind]
		if def == nil then
			return Promise.reject("Unknown item kind: " .. fromItem.Kind)
		end

		if def.MaxStackSize == nil then
			return false
		end

		local fromCount = fromItem.Count or 0
		if count < 1 or count >= fromCount then
			return false
		end

		local toItem = inventory[toSlot]
		if toItem ~= nil then
			if toItem.Kind ~= fromItem.Kind or not metaEqual(toItem.Meta, fromItem.Meta) then
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

		return commit(player, newInventory)
	end)
end

--[=[
	Returns the total number of items of `kind` across all inventory slots.
	Sums `Count` for stackable items; counts one per slot for non-stackable items.
	@within InventoryServer
	@param player Player
	@param kind string -- The item kind to count.
	@return Promise<number>
]=]
function InventoryServer.GetItemCount(player: Player, kind: string): any
	if ItemDefs[kind] == nil then
		return Promise.reject("Unknown item kind: " .. kind)
	end

	return DataServer.GetData(player):andThen(function(data)
		local inventory: Inventory = asInventory(data)
		local total = 0
		for i = 1, InventoryTypes.Size do
			local item = inventory[tostring(i)]
			if item ~= nil and item.Kind == kind then
				total += item.Count or 1
			end
		end
		return total
	end)
end

--[=[
	Returns whether the player has at least `count` items of `kind`.
	@within InventoryServer
	@param player Player
	@param kind string -- The item kind to check.
	@param count number? -- Minimum required quantity. Defaults to 1.
	@return Promise<boolean>
]=]
function InventoryServer.HasItem(player: Player, kind: string, count: number?): any
	return InventoryServer.GetItemCount(player, kind):andThen(function(total)
		return total >= (count or 1)
	end)
end

--[=[
	Removes `count` items of `kind`, consuming from slot 1 upward.

	Atomic: checks total availability before removing anything.
	@within InventoryServer
	@param player Player
	@param kind string -- The item kind to remove.
	@param count number? -- Number of items to remove. Defaults to 1.
	@return Promise<boolean> -- Resolves `false` when the player does not have enough items.
]=]
function InventoryServer.RemoveItemByKind(player: Player, kind: string, count: number?): any
	if ItemDefs[kind] == nil then
		return Promise.reject("Unknown item kind: " .. kind)
	end

	local amount = count or 1
	if amount < 1 then
		return Promise.reject("Count must be >= 1")
	end

	return DataServer.GetData(player):andThen(function(data)
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

		return commit(player, newInventory)
	end)
end

--[=[
	Replicates `inventory` to the player's `Inventory` Comm property without writing to DataServer.
	Use this from sibling servers (e.g. `EquipmentServer`) that perform their own atomic
	cross-table commit through `DataServer.UpdateData` and only need to push the resulting
	inventory state to the client.
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

	Observers.observePlayer(function(player)
		InventoryServer.GetInventory(player):andThen(function(inventory)
			inventoryProperty:SetFor(player, inventory)
		end)

		local kinds = Sift.Dictionary.keys(ItemDefs)
		for _ = 1, 20 do
			local kind = kinds[math.random(1, #kinds)]
			InventoryServer.AddItem(player, kind)
		end

		return nil
	end)
end

return InventoryServer
