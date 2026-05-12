--!strict

--[=[
	@class HotbarServer
	Authoritative owner of each player's hotbar bindings. The configurable
	slots are persisted in `PlayerData.Hotbar`; the MainHand slot is derived
	at runtime from the equipped melee weapon's `PrimaryAbility` and merged
	into the replicated payload. The Comm property is only re-published when
	the resulting bindings actually change, so a no-op weapon swap doesn't
	churn the wire.

	Activation dispatches by binding kind: `Ability` calls `AbilityServer.Activate`;
	`Item` resolves the first inventory stack of the bound `ItemKind` and runs the
	bound action on it (Equip / Drop). Cooldowns are not tracked here — ability
	cooldowns already live in `AbilityServer.Cooldowns` and the client reads them
	directly via `AbilityClient`.
]=]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Comm = require(ReplicatedStorage.Packages.Comm)
local Sift = require(ReplicatedStorage.Packages.Sift)
local t = require(ReplicatedStorage.Packages.t)

local AbilityServer = require(ServerScriptService.Server.Servers.AbilityServer)
local DataServer = require(ServerScriptService.Server.Servers.DataServer)
local EquipmentServer = require(ServerScriptService.Server.Servers.EquipmentServer)
local InventoryServer = require(ServerScriptService.Server.Servers.InventoryServer)
local Outworlder = require(ServerScriptService.Server.Components.Outworlder)
local AbilityDefs = require(ReplicatedStorage.Shared.Defs.AbilityDefs)
local ItemDefs = require(ReplicatedStorage.Shared.Defs.ItemDefs)
local EquipmentTypes = require(ReplicatedStorage.Shared.Types.EquipmentTypes)
local HotbarTypes = require(ReplicatedStorage.Shared.Types.HotbarTypes)
local InventoryTypes = require(ReplicatedStorage.Shared.Types.InventoryTypes)

type Hotbar = HotbarTypes.Hotbar
type HotbarBinding = HotbarTypes.HotbarBinding
type ItemAction = HotbarTypes.ItemAction
type Inventory = InventoryTypes.Inventory
type Equipment = EquipmentTypes.Equipment

local HotbarServer = {}

local hotbarProperty

local function asHotbar(data: any): Hotbar
	return (data.Hotbar :: any) :: Hotbar
end

local function asEquipment(data: any): Equipment
	return (data.Equipment :: any) :: Equipment
end

-- Computes the MainHand binding for a given equipment table. Returns
-- `EmptyBinding` when no melee is equipped or the equipped item has no
-- declared `PrimaryAbility`.
local function computeMainHandBinding(equipment: Equipment): HotbarBinding
	local melee = equipment.MainHandMelee
	if melee == nil then
		return HotbarTypes.EmptyBinding
	end
	local def = ItemDefs[melee.Kind]
	if def == nil or def.PrimaryAbility == nil then
		return HotbarTypes.EmptyBinding
	end
	return { Kind = "Ability", AbilityKind = def.PrimaryAbility }
end

-- Returns true when `a` and `b` describe the same binding. Tagged-union
-- structural equality — cheap because every binding has at most three fields
-- and the `Item` action sub-table is also tiny.
local function bindingsEqual(a: HotbarBinding, b: HotbarBinding): boolean
	if a.Kind ~= b.Kind then
		return false
	end
	if a.Kind == "Empty" then
		return true
	elseif a.Kind == "Ability" then
		return a.AbilityKind == (b :: any).AbilityKind
	elseif a.Kind == "Item" then
		local bi = b :: any
		if a.ItemKind ~= bi.ItemKind then
			return false
		end
		local actA = a.Action
		local actB = bi.Action
		if actA.Kind ~= actB.Kind then
			return false
		end
		if actA.Kind == "Equip" then
			return actA.Slot == (actB :: any).Slot
		end
		return true
	end
	return false
end

local function bindingsTableEqual(a: { [string]: HotbarBinding }, b: { [string]: HotbarBinding }): boolean
	for _, key in HotbarTypes.SlotKeys do
		if not bindingsEqual(a[key] or HotbarTypes.EmptyBinding, b[key] or HotbarTypes.EmptyBinding) then
			return false
		end
	end
	return true
end

local function buildPayload(persisted: Hotbar, equipment: Equipment): Hotbar
	local persistedBindings = persisted.Bindings
	local fullBindings: { [string]: HotbarBinding } = {}
	for _, key in HotbarTypes.ConfigurableSlotKeys do
		fullBindings[key] = persistedBindings[key] or HotbarTypes.EmptyBinding
	end
	fullBindings[HotbarTypes.MainHandSlotKey] = computeMainHandBinding(equipment)
	return table.freeze({ Bindings = table.freeze(fullBindings) } :: Hotbar)
end

-- Pushes a freshly built payload only if its bindings differ from the current
-- replicated value. `GetFor` falls back to the property's top-level value
-- (`DefaultHotbar`) when the player has never been written to, which makes
-- this the correct comparison even before the first push.
local function pushIfChanged(player: Player, payload: Hotbar)
	local current = hotbarProperty:GetFor(player) :: Hotbar
	if bindingsTableEqual(current.Bindings, payload.Bindings) then
		return
	end
	hotbarProperty:SetFor(player, payload)
end

local function refresh(player: Player)
	local data = DataServer.GetData(player)
	if data == nil then
		return
	end
	pushIfChanged(player, buildPayload(asHotbar(data), asEquipment(data)))
end

-- Wire-input shape validator for `HotbarBinding`. Composed once at module
-- load so each call is a flat tree walk through pre-built `t` checks.
-- `keyOf` snapshots the defs at construction time, which is fine because
-- both `AbilityDefs` and `ItemDefs` are static at runtime.
local validateBinding = t.union(
	t.strictInterface({ Kind = t.literal("Empty") }),
	t.strictInterface({
		Kind = t.literal("Ability"),
		AbilityKind = t.keyOf(AbilityDefs),
	}),
	t.strictInterface({
		Kind = t.literal("Item"),
		ItemKind = t.keyOf(ItemDefs),
		Action = t.union(
			t.strictInterface({
				Kind = t.literal("Equip"),
				Slot = t.keyOf(EquipmentTypes.SlotSet),
			}),
			t.strictInterface({ Kind = t.literal("Drop") })
		),
	})
)

-- Drops any persisted bindings that no longer pass `validateBinding` — e.g.
-- references to AbilityKinds or ItemKinds removed from defs since the
-- player's last session. Writes back to `PlayerData` only when something
-- actually changed.
local function sanitizeBindings(player: Player)
	local data = DataServer.GetData(player)
	if data == nil then
		return
	end
	local existing = asHotbar(data).Bindings
	local cleaned: { [string]: HotbarBinding }? = nil
	for _, key in HotbarTypes.ConfigurableSlotKeys do
		local binding = existing[key]
		if binding == nil or binding.Kind == "Empty" then
			continue
		end
		local ok = validateBinding(binding)
		if not ok then
			if cleaned == nil then
				cleaned = table.clone(existing)
			end
			(cleaned :: { [string]: HotbarBinding })[key] = HotbarTypes.EmptyBinding
		end
	end
	if cleaned == nil then
		return
	end
	local cleanedFinal: { [string]: HotbarBinding } = cleaned
	DataServer.UpdateData(player, function(current)
		local hotbar = asHotbar(current)
		return Sift.Dictionary.merge(current, { Hotbar = Sift.Dictionary.merge(hotbar, { Bindings = cleanedFinal }) })
	end)
end

local function findFirstInventorySlotOfKind(inventory: Inventory, itemKind: string): string?
	for i = 1, InventoryTypes.Size do
		local key = tostring(i)
		local item = inventory[key]
		if item ~= nil and item.Kind == itemKind then
			return key
		end
	end
	return nil
end

--[=[
	Returns the player's full replicated hotbar payload, including the derived
	MainHand binding. Returns the (also frozen) `DefaultHotbar` shape when data
	isn't loaded — never `nil`.
	@within HotbarServer
	@param player Player
	@return Hotbar
]=]
function HotbarServer.GetHotbar(player: Player): Hotbar
	return hotbarProperty:GetFor(player) :: Hotbar
end

--[=[
	Sets the binding for a configurable slot. The MainHand slot is rejected —
	it's server-managed. Returns `(true, nil)` on success or `(false, message)`
	when validation fails.
	@within HotbarServer
	@param player Player
	@param slotKey string
	@param binding HotbarBinding
	@return (boolean, string?)
]=]
function HotbarServer.SetBinding(player: Player, slotKey: string, binding: HotbarBinding): (boolean, string?)
	if not HotbarTypes.ConfigurableSlotKeySet[slotKey] then
		return false, `Slot "{slotKey}" is not configurable.`
	end
	local ok, message = validateBinding(binding)
	if not ok then
		return false, message
	end

	local committed = DataServer.UpdateData(player, function(data)
		local hotbar = asHotbar(data)
		local newBindings = Sift.Dictionary.merge(hotbar.Bindings, { [slotKey] = binding })
		return Sift.Dictionary.merge(data, { Hotbar = Sift.Dictionary.merge(hotbar, { Bindings = newBindings }) })
	end)
	if committed == nil then
		return false, "Player data is not loaded."
	end

	pushIfChanged(player, buildPayload(asHotbar(committed), asEquipment(committed)))
	return true, nil
end

--[=[
	Clears the binding for a configurable slot — sugar for `SetBinding` with
	the empty binding.
	@within HotbarServer
	@param player Player
	@param slotKey string
	@return (boolean, string?)
]=]
function HotbarServer.ClearBinding(player: Player, slotKey: string): (boolean, string?)
	return HotbarServer.SetBinding(player, slotKey, HotbarTypes.EmptyBinding)
end

-- Runs an Item binding's action against the first inventory stack matching
-- its ItemKind. Returns `(false, message)` when no matching stack exists or
-- the underlying server call rejects.
local function activateItemBinding(player: Player, binding: HotbarBinding): (boolean, string?)
	assert(binding.Kind == "Item", "activateItemBinding: non-Item binding")
	local inventory = InventoryServer.GetInventory(player)
	local slot = findFirstInventorySlotOfKind(inventory, binding.ItemKind)
	if slot == nil then
		return false, `No "{binding.ItemKind}" in inventory.`
	end
	local action = binding.Action
	if action.Kind == "Equip" then
		local ok = EquipmentServer.Equip(player, slot, action.Slot)
		if not ok then
			return false, "Equip failed."
		end
		return true, nil
	elseif action.Kind == "Drop" then
		local ok = InventoryServer.RemoveItem(player, slot)
		if not ok then
			return false, "Drop failed."
		end
		return true, nil
	end
	return false, "Unknown item action kind."
end

--[=[
	Activates the binding in `slotKey`. Returns `(true, nil)` on success or
	`(false, message)` on rejection. Dispatches by binding kind:
	- `Empty` rejects.
	- `Ability` defers to `AbilityServer.Activate` using the player's Outworlder.
	- `Item` finds the first matching stack and runs the bound action.
	@within HotbarServer
	@param player Player
	@param slotKey string
	@return (boolean, string?)
]=]
function HotbarServer.Activate(player: Player, slotKey: string): (boolean, string?)
	if not HotbarTypes.SlotKeySet[slotKey] then
		return false, `Unknown slot "{slotKey}".`
	end
	local payload = HotbarServer.GetHotbar(player)
	local binding = payload.Bindings[slotKey]
	if binding == nil or binding.Kind == "Empty" then
		return false, "Slot is empty."
	end

	if binding.Kind == "Ability" then
		local character = player.Character
		if character == nil then
			return false, "Character not ready."
		end
		local outworlder = Outworlder:FromInstance(character)
		if outworlder == nil then
			return false, "Character not ready."
		end
		return AbilityServer.Activate(outworlder, binding.AbilityKind, nil)
	end
	if binding.Kind == "Item" then
		return activateItemBinding(player, binding)
	end
	return false, "Unsupported binding."
end

function HotbarServer.Init()
	local serverComm = Comm.ServerComm.new(ReplicatedStorage, "Hotbar")
	hotbarProperty = serverComm:CreateProperty("Hotbar", HotbarTypes.DefaultHotbar)

	serverComm:BindFunction("SetBinding", function(player, slotKey, binding)
		if not t.string(slotKey) then
			return false, "Bad slot key."
		end
		local ok, message = HotbarServer.SetBinding(player, slotKey, binding)
		return ok, message or ""
	end)

	serverComm:BindFunction("ClearBinding", function(player, slotKey)
		if not t.string(slotKey) then
			return false, "Bad slot key."
		end
		local ok, message = HotbarServer.ClearBinding(player, slotKey)
		return ok, message or ""
	end)

	serverComm:BindFunction("Activate", function(player, slotKey)
		if not t.string(slotKey) then
			return false, "Bad slot key."
		end
		local ok, message = HotbarServer.Activate(player, slotKey)
		return ok, message or ""
	end)

	DataServer.ObservePlayer(function(player, _data)
		sanitizeBindings(player)
		-- `ObserveEquipment`'s immediate-fire-with-current-value handles the
		-- initial replication; no explicit `pushIfChanged` needed here.
		return EquipmentServer.ObserveEquipment(player, function(_equipment)
			refresh(player)
		end)
	end)
end

return HotbarServer
