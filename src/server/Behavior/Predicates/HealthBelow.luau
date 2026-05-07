--!strict

--[=[
	@class HealthBelow
	Predicate: returns `true` when `denizen.Health / denizen.MaxHealth` is strictly below
	`args.Fraction`.
]=]

--[=[
	@interface Args
	@within HealthBelow
	@field Fraction number -- 0..1.
]=]
export type Args = {
	Kind: string,
	Fraction: number,
}

return function(denizen: any, args: Args): boolean
	return denizen.Health / denizen.MaxHealth < args.Fraction
end
