--!strict

--[=[
	@class InCombat
	Predicate: returns `true` when the denizen is currently in a `CombatSession` (its
	`CombatSession` field is non-nil). Useful for transitioning into combat states from
	"someone hit me from afar" cases the active sensor (`EnemyInRange`) may not have caught.
]=]

--[=[
	@interface Args
	@within InCombat
]=]
export type Args = {
	Kind: string,
}

return function(denizen: any, _args: Args): boolean
	return denizen.CombatSession ~= nil
end
