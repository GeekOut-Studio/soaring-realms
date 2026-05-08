--!strict

--[=[
	@class DamageTypes
	Shared types for the centralized damage pipeline. `Damage` records flow through
	`DamageServer.Damage`, threaded through any `OnWillDealDamage` / `OnWillTakeDamage`
	hooks the source and target expose, then applied to the target's health, then read by
	`OnDidDealDamage` / `OnDidTakeDamage` hooks. Records are immutable end-to-end — modifier
	hooks build a new frozen `Damage` via `DamageTypes.With` rather than mutating in place.
]=]

--[=[
	@type DamageType "Slashing" | "Piercing" | "Crushing"
	@within DamageTypes
	String-literal union of damage types. Future resistances and on-hit effects key off
	this field.
]=]
export type DamageType = "Slashing" | "Piercing" | "Crushing"

--[=[
	@interface Damage
	@within DamageTypes
	@field Amount number -- Pre-application damage amount in HP. Hooks may transform this.
	@field Type DamageType
	@field Source DamageSource? -- Origin of the damage. `nil` for environmental hazards.
	@field Target DamageTarget
	@field Tags {[string]: true}? -- Free-form labels modifiers can use to tag and filter damage events. Normalized to an empty frozen table by `DamageServer.Damage` on entry, so downstream hooks can rely on it being non-nil.
]=]
export type Damage = {
	Amount: number,
	Type: DamageType,
	Source: DamageSource?,
	Target: DamageTarget,
	Tags: { [string]: true }?,
}

--[=[
	@interface DamageSource
	@within DamageTypes
	@field OnWillDealDamage ((DamageSource, Damage) -> Damage)? -- Pre-apply transform run on the source side. Returns the (possibly modified) Damage.
	@field OnDidDealDamage ((DamageSource, Damage) -> Damage)? -- Post-apply observer / final transform run on the source side after health is mutated.
]=]
export type DamageSource = {
	OnWillDealDamage: ((DamageSource, Damage) -> Damage)?,
	OnDidDealDamage: ((DamageSource, Damage) -> Damage)?,
}

--[=[
	@interface DamageTarget
	@within DamageTypes
	@field OnWillTakeDamage ((DamageTarget, Damage) -> Damage)? -- Pre-apply transform on the target side, runs after the source-side `OnWillDealDamage`.
	@field OnDidTakeDamage ((DamageTarget, Damage) -> Damage)? -- Post-apply observer / final transform on the target side.
	@field GetHealth (DamageTarget) -> number
	@field SetHealth (DamageTarget, number) -> ()
]=]
export type DamageTarget = {
	OnWillTakeDamage: ((DamageTarget, Damage) -> Damage)?,
	OnDidTakeDamage: ((DamageTarget, Damage) -> Damage)?,
	GetHealth: (DamageTarget) -> number,
	SetHealth: (DamageTarget, number) -> (),
}

local DamageTypes = {}

--[=[
	@prop Types {DamageType}
	@within DamageTypes
	Ordered list of every valid damage type.
]=]
DamageTypes.Types = table.freeze({ "Slashing", "Piercing", "Crushing" } :: { DamageType })

--[=[
	@prop TypeSet {[string]: true}
	@within DamageTypes
	Set form of `Types` for O(1) membership checks.
]=]
local typeSet: { [string]: true } = {}
for _, damageType in DamageTypes.Types do
	typeSet[damageType] = true
end
DamageTypes.TypeSet = table.freeze(typeSet)

--[=[
	Returns a new frozen `Damage` with `overrides` applied on top of `damage`. Use this in
	hooks to produce a transformed record instead of mutating the input.
	@within DamageTypes
	@param damage Damage
	@param overrides {[string]: any}
	@return Damage
]=]
function DamageTypes.With(damage: Damage, overrides: { [string]: any }): Damage
	local copy = table.clone(damage)
	for key, value in overrides do
		(copy :: any)[key] = value
	end
	return table.freeze(copy) :: any
end

return DamageTypes
