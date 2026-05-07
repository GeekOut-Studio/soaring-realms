--!strict

--[=[
	@class Behavior
	@server
	Per-denizen FSM runner. Constructed from a `BehaviorDef` (states + transitions, both
	referenced by string `Kind` in the def and resolved here to the implementations in
	`States/` and `Predicates/`).

	The `Tick` order is:

	1. Check transitions top-to-bottom. The first whose `From` matches (or is omitted) and
	   whose predicate fires wins; we transition immediately.
	2. Tick the (possibly newly-entered) state's `Update`. If it returns a state name, we
	   transition to it.

	Transition order is a contract — see `DenizenBehaviorPlan.md` for the rationale.
]=]

local STATE_FACTORIES = {
	Wander = require(script.Parent.States.Wander),
	MeleeAggression = require(script.Parent.States.MeleeAggression),
	Flee = require(script.Parent.States.Flee),
	ReturnToSpawn = require(script.Parent.States.ReturnToSpawn),
}

local PREDICATES = {
	HealthBelow = require(script.Parent.Predicates.HealthBelow),
	HealthAbove = require(script.Parent.Predicates.HealthAbove),
	EnemyInRange = require(script.Parent.Predicates.EnemyInRange),
	InCombat = require(script.Parent.Predicates.InCombat),
	RecentlyDamaged = require(script.Parent.Predicates.RecentlyDamaged),
	NotRecentlyDamaged = require(script.Parent.Predicates.NotRecentlyDamaged),
}

--[=[
	@interface State
	@within Behavior
	@field Enter ((denizen: any) -> ())?
	@field Update (denizen: any, dt: number) -> string?
	@field Exit ((denizen: any) -> ())?
]=]
export type State = {
	Enter: ((denizen: any) -> ())?,
	Update: (denizen: any, dt: number) -> string?,
	Exit: ((denizen: any) -> ())?,
}

--[=[
	@type StateConfig {Kind: string, [string]: any}
	@within Behavior
	A state config table. `Kind` selects the implementation in `STATE_FACTORIES`; the rest is
	state-specific config.
]=]
export type StateConfig = { Kind: string, [string]: any }

--[=[
	@type PredicateArgs {Kind: string, [string]: any}
	@within Behavior
]=]
export type PredicateArgs = { Kind: string, [string]: any }

--[=[
	@interface Transition
	@within Behavior
	@field From string? -- Limits the transition to a specific source state. Omit to apply regardless of current state.
	@field When PredicateArgs -- Predicate to evaluate. Selected by `When.Kind`.
	@field Goto string -- Destination state name (a key in `BehaviorDef.States`).
]=]
export type Transition = {
	From: string?,
	When: PredicateArgs,
	Goto: string,
}

--[=[
	@interface BehaviorDef
	@within Behavior
	@field Initial string -- Name of the state to enter on construction.
	@field States {[string]: StateConfig} -- State configs keyed by state name.
	@field Transitions {Transition} -- Ordered list of transitions, evaluated top-to-bottom each tick.
]=]
export type BehaviorDef = {
	Initial: string,
	States: { [string]: StateConfig },
	Transitions: { Transition },
}

local Behavior = {}
Behavior.__index = Behavior

--[=[
	Constructs a behavior bound to `denizen`, instantiates all states up-front, and enters
	`behaviorDef.Initial`.
	@within Behavior
	@server
	@param denizen any
	@param behaviorDef BehaviorDef
	@return Behavior
]=]
function Behavior.new(denizen: any, behaviorDef: BehaviorDef)
	local self = setmetatable({}, Behavior)
	self.Denizen = denizen
	self.Transitions = behaviorDef.Transitions
	self.States = {} :: { [string]: State }
	for name, config in behaviorDef.States do
		local factory = STATE_FACTORIES[config.Kind]
		assert(factory ~= nil, `Unknown state kind: {config.Kind}`)
		self.States[name] = factory(config)
	end
	self.CurrentName = behaviorDef.Initial
	local initial = self.States[self.CurrentName]
	assert(initial ~= nil, `Initial state not in States table: {behaviorDef.Initial}`)
	if initial.Enter ~= nil then
		initial.Enter(denizen)
	end
	return self
end

--[=[
	Advance one frame: check transitions, then tick the current state.
	@within Behavior
	@server
	@param dt number
]=]
function Behavior:Tick(dt: number)
	for _, transition in self.Transitions do
		if transition.From ~= nil and transition.From ~= self.CurrentName then
			continue
		end
		local predicate = PREDICATES[transition.When.Kind]
		assert(predicate ~= nil, `Unknown predicate kind: {transition.When.Kind}`)
		if predicate(self.Denizen, transition.When) then
			self:TransitionTo(transition.Goto)
			break
		end
	end

	local state = self.States[self.CurrentName]
	local nextName = state.Update(self.Denizen, dt)
	if nextName ~= nil then
		self:TransitionTo(nextName)
	end
end

--[=[
	Switches the active state, calling `Exit` on the outgoing state and `Enter` on the
	incoming. No-op when `nextName` already matches the current state.
	@within Behavior
	@server
	@param nextName string
]=]
function Behavior:TransitionTo(nextName: string)
	if nextName == self.CurrentName then
		return
	end
	local currentState = self.States[self.CurrentName]
	if currentState.Exit ~= nil then
		currentState.Exit(self.Denizen)
	end
	local nextState = self.States[nextName]
	assert(nextState ~= nil, `Transition to unknown state: {nextName}`)
	self.CurrentName = nextName
	if nextState.Enter ~= nil then
		nextState.Enter(self.Denizen)
	end
end

return Behavior
