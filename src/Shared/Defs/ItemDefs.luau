--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Sift = require(ReplicatedStorage.Packages.Sift)

local EquipmentTypes = require(ReplicatedStorage.Shared.Types.EquipmentTypes)

export type ItemDef = {
	Kind: string,
	Name: string,
	MaxStackSize: number?, -- nil = not stackable (one item per slot)
	EquipSlots: { EquipmentTypes.EquipmentSlot }?, -- nil = not equippable. Listed in display order.
	AssetPath: string?, -- nil = no rendered asset. Slash-delimited path under ServerStorage.Assets.
}

export type ItemDefs = { [string]: ItemDef }

local Defs = {
	Coin = {
		Name = "Coin",
		MaxStackSize = 2147483647,
	},
	Stone = {
		Name = "Stone",
	},
	CopperOre = {
		Name = "Copper Ore",
	},
	CopperIngot = {
		Name = "Copper Ingot",
	},
	CopperSword = {
		Name = "Copper Sword",
		EquipSlots = { "MainHandMelee" },
		AssetPath = "Base/Weapons/SwordCopper",
	},
}

local function transform(defs): ItemDefs
	return Sift.Dictionary.map(defs, function(def, kind)
		return Sift.Dictionary.merge(def, { Kind = kind })
	end)
end

return transform(Defs)
