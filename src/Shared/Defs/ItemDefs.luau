--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Sift = require(ReplicatedStorage.Packages.Sift)

local EquipmentTypes = require(ReplicatedStorage.Shared.Types.EquipmentTypes)
local ItemStatsTypes = require(ReplicatedStorage.Shared.Types.ItemStatsTypes)

export type ItemDef = {
	Kind: string,
	Name: string,
	MaxStackSize: number?, -- nil = not stackable (one item per slot)
	EquipSlots: { EquipmentTypes.EquipmentSlot }?, -- nil = not equippable. Listed in display order.
	AssetPath: string?, -- nil = no rendered asset. Slash-delimited path under ServerStorage.Assets.
	Stats: ItemStatsTypes.Stats?, -- nil = no gameplay-class stats. Used to gate and parameterize gathering/combat actions.
	IdleAnimation: string?, -- nil = no idle pose. Animation name from `AnimationDefs` played on the equipping `Outworlder` while this item is equipped.
	PrimaryAbility: string?, -- nil = no primary ability. Key into `AbilityDefs` for the ability fired by the player's primary input (M1) while this item is equipped in its weapon-bearing slot.
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
	OreCopper = {
		Name = "Copper Ore",
	},
	BarCopper = {
		Name = "Copper Bar",
	},
	LogPoplar = {
		Name = "Poplar Log",
	},
	FishCommon = {
		Name = "Common Fish",
	},
	Junk = {
		Name = "Junk",
	},
	SwordCopper = {
		Name = "Copper Sword",
		EquipSlots = { "MainHandMelee" },
		AssetPath = "Base/Weapons/SwordCopper",
		IdleAnimation = "WeaponOneHandedIdle",
		PrimaryAbility = "BasicAttackMainHandMelee",
		Stats = {
			Combat = {
				Interval = 1,
				Power = { Min = 6, Max = 9 },
				Range = 8,
				DamageType = "Slashing",
				AttackAnimation = "WeaponOneHandedHorizontalSwing",
			},
		},
	},
	PickaxeCopper = {
		Name = "Copper Pickaxe",
		EquipSlots = { "MainHandMelee" },
		AssetPath = "Base/Tools/PickaxeCopper",
		IdleAnimation = "ToolShoulderedIdle",
		Stats = {
			Mining = {
				Interval = 1.75,
				Power = { Min = 0.9, Max = 1.1 },
			},
		},
	},
	AxeCopper = {
		Name = "Copper Axe",
		EquipSlots = { "MainHandMelee" },
		AssetPath = "Base/Tools/AxeCopper",
		IdleAnimation = "ToolShoulderedIdle",
		Stats = {
			Woodcutting = {
				Interval = 1.75,
				Power = { Min = 0.9, Max = 1.1 },
			},
		},
	},
	FishingRodCopper = {
		Name = "Copper Fishing Rod",
		EquipSlots = { "MainHandMelee" },
		AssetPath = "Base/Tools/FishingRodCopper",
		IdleAnimation = "ToolShoulderedIdle",
		Stats = {
			Fishing = {
				Interval = 4,
				CatchChance = 0.25,
			},
		},
	},
}

local function transform(defs): ItemDefs
	return Sift.Dictionary.map(defs, function(def, kind)
		return Sift.Dictionary.merge(def, { Kind = kind })
	end)
end

return transform(Defs)
