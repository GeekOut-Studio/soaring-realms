local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Sift = require(ReplicatedStorage.Packages.Sift)

export type IslandKind = "Oswalayt" | "HikasWood"

export type IslandDef = {
	Kind: IslandKind,
	Name: string,
	PlaceId: number,
}

export type IslandDefs = { [IslandKind]: IslandDef }

local Defs = {
	Oswalayt = {
		Name = "Oswalayt",
		PlaceId = 83069405786977,
	},
	HikasWood = {
		Name = "Hika's Wood",
		PlaceId = 83506007467844,
	},
}

local function transform(defs): IslandDefs
	return Sift.Dictionary.map(defs, function(def, kind)
		return Sift.Dictionary.merge(def, {
			Kind = kind,
		})
	end)
end

return transform(Defs)
