--!strict

--[=[
	@class EquipmentTypes
	Shared types and constants for the equipment system.
]=]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local InventoryTypes = require(ReplicatedStorage.Shared.Types.InventoryTypes)

--[=[
	@type EquipmentSlot string
	@within EquipmentTypes
	String literal union of valid equipment slot names.
]=]
export type EquipmentSlot =
	"Head"
	| "Neck"
	| "Back"
	| "Torso"
	| "Hands"
	| "Legs"
	| "Feet"
	| "MainHandMelee"
	| "MainHandRanged"
	| "Offhand"
	| "RingRight"
	| "RingLeft"
	| "Waist"

--[=[
	@type Equipment {[string]: Item}
	@within EquipmentTypes
	A player's equipped items, keyed by `EquipmentSlot` name. Missing keys denote empty slots.
]=]
export type Equipment = { [string]: InventoryTypes.Item }

local EquipmentTypes = {}

--[=[
	@prop Slots {EquipmentSlot}
	@within EquipmentTypes
	Ordered list of every valid equipment slot. Use this constant when iterating all slots.
]=]
EquipmentTypes.Slots = table.freeze({
	"Head",
	"Neck",
	"Back",
	"Torso",
	"Hands",
	"Legs",
	"Feet",
	"MainHandMelee",
	"MainHandRanged",
	"Offhand",
	"RingRight",
	"RingLeft",
	"Waist",
} :: { EquipmentSlot })

--[=[
	@prop SlotSet {[string]: true}
	@within EquipmentTypes
	Set form of `Slots` for O(1) membership checks.
]=]
local slotSet: { [string]: true } = {}
for _, slot in EquipmentTypes.Slots do
	slotSet[slot] = true
end
EquipmentTypes.SlotSet = table.freeze(slotSet)

--[=[
	@prop DefaultEquipment Equipment
	@within EquipmentTypes
	Empty equipment used as the starting state for new players.
]=]
EquipmentTypes.DefaultEquipment = table.freeze({} :: Equipment)

--[=[
	@prop SlotLabels {[string]: string}
	@within EquipmentTypes
	Short, human-readable display labels keyed by `EquipmentSlot`. Used wherever a slot
	needs to surface in UI (placeholder text, equip action labels, etc.).
]=]
EquipmentTypes.SlotLabels = table.freeze({
	Head = "Head",
	Neck = "Neck",
	Back = "Back",
	Torso = "Torso",
	Hands = "Hands",
	Legs = "Legs",
	Feet = "Feet",
	MainHandMelee = "Melee",
	MainHandRanged = "Ranged",
	Offhand = "Offhand",
	RingRight = "R. Ring",
	RingLeft = "L. Ring",
	Waist = "Waist",
} :: { [string]: string })

return EquipmentTypes
