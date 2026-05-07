--!strict

--[=[
	@class DenizenDefs
	Static defs for each kind of Denizen — the non-player combat-capable inhabitants of the
	realm (cows, imps, NPCs, …). Indexed by a string `Kind`, which is the value of the
	`DenizenKind` attribute on each `Denizen`-tagged model. No string-literal union: we
	expect hundreds of kinds, so we follow the `ItemDefs` precedent of plain string keys.
]=]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Sift = require(ReplicatedStorage.Packages.Sift)

--[=[
	@interface Animations
	@within DenizenDefs
	@field Idle string? -- `AnimationDefs` key looped over the denizen's lifetime.
]=]
export type Animations = {
	Idle: string?,
}

--[=[
	@interface DenizenDef
	@within DenizenDefs
	@field Kind string -- The defs key. Auto-filled by `transform`; def authors don't restate it.
	@field Name string -- Human-readable label.
	@field MaxHealth number
	@field Animations Animations
]=]
export type DenizenDef = {
	Kind: string,
	Name: string,
	MaxHealth: number,
	Animations: Animations,
}

export type DenizenDefs = { [string]: DenizenDef }

local Defs = {
	Imp = {
		Name = "Imp",
		MaxHealth = 50,
		Animations = {
			Idle = "ImpIdle",
		},
	},
}

local function transform(defs): DenizenDefs
	return Sift.Dictionary.map(defs, function(def, kind)
		return Sift.Dictionary.merge(def, { Kind = kind })
	end)
end

return transform(Defs)
