--!strict

--[=[
	@class HotbarTypes
	Shared types and constants for the hotbar system.

	A hotbar slot holds a `HotbarBinding` — either an ability to activate, an
	item-context action to run on the first matching inventory stack, or empty.
	One slot key (`MainHandSlotKey`) is reserved for the equipped melee weapon's
	primary ability and is server-managed; the rest are configurable by the player.
]=]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local EquipmentTypes = require(ReplicatedStorage.Shared.Types.EquipmentTypes)

--[=[
	@type ItemAction {Kind: "Equip", Slot: EquipmentSlot} | {Kind: "Drop"}
	@within HotbarTypes
	Discriminated union of item-context actions a hotbar slot may bind. Mirrors
	the actions the inventory context menu offers; new actions (Use, Consume,
	etc.) extend this union.
]=]
export type ItemAction = { Kind: "Equip", Slot: EquipmentTypes.EquipmentSlot } | { Kind: "Drop" }

--[=[
	@type HotbarBinding {Kind:"Empty"} | {Kind:"Ability", AbilityKind:string} | {Kind:"Item", ItemKind:string, Action:ItemAction}
	@within HotbarTypes
	What a single hotbar slot holds. `Ability` activates the referenced ability
	directly. `Item` looks up the first inventory stack of `ItemKind` and runs
	`Action` on it; if no stack exists the slot renders unavailable.
]=]
export type HotbarBinding =
	{ Kind: "Empty" }
	| { Kind: "Ability", AbilityKind: string }
	| { Kind: "Item", ItemKind: string, Action: ItemAction }

--[=[
	@interface Hotbar
	@within HotbarTypes
	@field Bindings {[string]: HotbarBinding} -- Keyed by slot key. The persisted shape omits `MainHandSlotKey`; the replicated shape includes it.
]=]
export type Hotbar = {
	Bindings: { [string]: HotbarBinding },
}

local HotbarTypes = {}

--[=[
	@prop HotbarSize number
	@within HotbarTypes
	Count of configurable numbered slots (`Hotbar1` through `HotbarN`). The
	MainHand slot is separate and not counted here.
]=]
HotbarTypes.HotbarSize = 5

--[=[
	@prop MainHandSlotKey string
	@within HotbarTypes
	Key of the special server-managed slot that mirrors the equipped MainHand
	melee weapon's `PrimaryAbility`. The player cannot bind this slot manually.
]=]
HotbarTypes.MainHandSlotKey = "HotbarMainHand"

--[=[
	@prop EmptyBinding HotbarBinding
	@within HotbarTypes
	Frozen singleton used to seed empty slots and to clear bindings without
	repeated allocations.
]=]
HotbarTypes.EmptyBinding = table.freeze({ Kind = "Empty" } :: HotbarBinding)

--[=[
	@prop SlotKeys {string}
	@within HotbarTypes
	Frozen ordered list of every valid hotbar slot key, used as the canonical
	UI iteration order. The MainHand key is positioned first; numbered slots
	follow.
]=]
local slotKeys: { string } = { HotbarTypes.MainHandSlotKey }
for i = 1, HotbarTypes.HotbarSize do
	table.insert(slotKeys, `Hotbar{i}`)
end
HotbarTypes.SlotKeys = table.freeze(slotKeys)

--[=[
	@prop ConfigurableSlotKeys {string}
	@within HotbarTypes
	Frozen ordered list of the numbered slot keys only. These are the keys
	the player may bind directly via `SetBinding`.
]=]
local configurableSlotKeys: { string } = {}
for i = 1, HotbarTypes.HotbarSize do
	table.insert(configurableSlotKeys, `Hotbar{i}`)
end
HotbarTypes.ConfigurableSlotKeys = table.freeze(configurableSlotKeys)

--[=[
	@prop SlotKeySet {[string]: true}
	@within HotbarTypes
	Set form of `SlotKeys` for O(1) membership checks (including the MainHand key).
]=]
local slotKeySet: { [string]: true } = {}
for _, key in HotbarTypes.SlotKeys do
	slotKeySet[key] = true
end
HotbarTypes.SlotKeySet = table.freeze(slotKeySet)

--[=[
	@prop ConfigurableSlotKeySet {[string]: true}
	@within HotbarTypes
	Set form of `ConfigurableSlotKeys` — used server-side to reject `SetBinding`
	requests that target the MainHand slot.
]=]
local configurableSlotKeySet: { [string]: true } = {}
for _, key in HotbarTypes.ConfigurableSlotKeys do
	configurableSlotKeySet[key] = true
end
HotbarTypes.ConfigurableSlotKeySet = table.freeze(configurableSlotKeySet)

--[=[
	@prop DefaultHotbar Hotbar
	@within HotbarTypes
	Starting hotbar for new players: every configurable slot is `Empty`. The
	MainHand slot is omitted from the persisted shape — it's derived at runtime
	by `HotbarServer` from the player's equipped melee.
]=]
local defaultBindings: { [string]: HotbarBinding } = {}
for _, key in HotbarTypes.ConfigurableSlotKeys do
	defaultBindings[key] = HotbarTypes.EmptyBinding
end
HotbarTypes.DefaultHotbar = table.freeze({ Bindings = table.freeze(defaultBindings) } :: Hotbar)

return HotbarTypes
