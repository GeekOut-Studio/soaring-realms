--!strict

--[=[
	@class CombatServer
	Owns every active `CombatSession` on the server. Routes engagements, refreshes
	per-combatant `CombatTimer`s, and ends sessions when no opposed alive pair remains or
	when every member's timer has expired.

	Two combatants are *hostile* iff at least one has `Team == nil` (treated as hostile to
	everyone) or their teams differ. Same-team combatants are never put into combat with
	each other; allied damage is invisible to this system.

	Tick cadence is 0.1s, accumulated against `Heartbeat`. The interval is short because the
	tick may eventually drive more than just timeout sweeps.
]=]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local CombatTypes = require(ReplicatedStorage.Shared.Types.CombatTypes)
local DamageTypes = require(ReplicatedStorage.Shared.Types.DamageTypes)

type Combatant = CombatTypes.Combatant
type CombatSession = CombatTypes.CombatSession
type Damage = DamageTypes.Damage

--[=[
	@prop COMBAT_TIMEOUT number
	@within CombatServer
	Seconds without involvement (damage dealt or taken between hostile combatants) before a
	combatant is dropped from its session.
]=]
local COMBAT_TIMEOUT = 6

local TICK_INTERVAL = 0.1

local sessions: { [CombatSession]: true } = {}
local accumulator = 0
local started = false

local CombatServer = {}

local function isCombatant(x: any): boolean
	return type(x) == "table"
		and type(x.GetTeam) == "function"
		and type(x.GetCFrame) == "function"
		and type(x.GetHealth) == "function"
end

local function isHostile(a: Combatant, b: Combatant): boolean
	local ta, tb = a:GetTeam(), b:GetTeam()
	return ta == nil or tb == nil or ta ~= tb
end

local function newSession(): CombatSession
	local session: CombatSession = { Members = {} }
	sessions[session] = true
	return session
end

local function endSession(session: CombatSession)
	for combatant in session.Members do
		combatant.CombatSession = nil
	end
	session.Members = {}
	sessions[session] = nil
end

local function hasOpposedAlivePair(session: CombatSession): boolean
	local alive: { Combatant } = {}
	for combatant in session.Members do
		if combatant:GetHealth() > 0 then
			table.insert(alive, combatant)
		end
	end
	for i = 1, #alive do
		for j = i + 1, #alive do
			if isHostile(alive[i], alive[j]) then
				return true
			end
		end
	end
	return false
end

local function mergeInto(survivor: CombatSession, absorbed: CombatSession)
	for combatant, timestamp in absorbed.Members do
		local existing = survivor.Members[combatant]
		if existing == nil or timestamp > existing then
			survivor.Members[combatant] = timestamp
		end
		combatant.CombatSession = survivor
	end
	absorbed.Members = {}
	sessions[absorbed] = nil
end

--[=[
	Refreshes `combatant`'s CombatTimer in its current session. No-op if the combatant
	isn't in a session.
	@within CombatServer
	@param combatant Combatant
	@param now number
	@private
]=]
local function refreshTimer(combatant: Combatant, now: number)
	local session = combatant.CombatSession
	if session == nil then
		return
	end
	session.Members[combatant] = now
end

--[=[
	Engages `a` and `b` in combat. Validates both are combatants and hostile, then routes:
	- neither in session → new session with both
	- one in session → other joins
	- both in different sessions → merge
	- both in same session → just refresh timers
	No-op when either party isn't a combatant, when they aren't hostile, or when
	`a == b`.
	@within CombatServer
	@param a any
	@param b any
]=]
function CombatServer.Engage(a: any, b: any)
	if a == b then
		return
	end
	if not isCombatant(a) or not isCombatant(b) then
		return
	end
	local ca, cb = a :: Combatant, b :: Combatant
	if not isHostile(ca, cb) then
		return
	end

	local now = os.clock()
	local sa, sb = ca.CombatSession, cb.CombatSession

	if sa ~= nil and sa == sb then
		sa.Members[ca] = now
		sa.Members[cb] = now
		return
	end

	local session: CombatSession
	if sa == nil and sb == nil then
		session = newSession()
	elseif sa ~= nil and sb == nil then
		session = sa
	elseif sa == nil and sb ~= nil then
		session = sb
	else
		session = sa :: CombatSession
		mergeInto(session, sb :: CombatSession)
	end

	session.Members[ca] = now
	session.Members[cb] = now
	ca.CombatSession = session
	cb.CombatSession = session
end

--[=[
	Removes `combatant` from its session, if any. Re-evaluates the session's viability and
	ends it if no opposed alive pair remains. Called by combatant `Stop()` handlers and by
	states like `Returning` that voluntarily drop out of combat.
	@within CombatServer
	@param combatant any
]=]
function CombatServer.Disengage(combatant: any)
	if not isCombatant(combatant) then
		return
	end
	local c = combatant :: Combatant
	local session = c.CombatSession
	if session == nil then
		return
	end
	session.Members[c] = nil
	c.CombatSession = nil
	if not hasOpposedAlivePair(session) then
		endSession(session)
	end
end

--[=[
	Damage-pipeline integration point. Called by `DamageServer.Damage` after the pipeline
	resolves. If both source and target are valid hostile combatants, engages them and
	refreshes both timers. Allied damage and damage with no source are ignored — the rule
	is "if it wouldn't start a fight, it doesn't continue one."
	@within CombatServer
	@param damage Damage
]=]
function CombatServer.OnDamageEvent(damage: Damage)
	local source = damage.Source
	if source == nil then
		return
	end
	if not isCombatant(source) or not isCombatant(damage.Target) then
		return
	end
	local cs = (source :: any) :: Combatant
	local ct = (damage.Target :: any) :: Combatant
	if not isHostile(cs, ct) then
		return
	end
	CombatServer.Engage(cs, ct)
	-- Engage already wrote `now` for both sides in the resulting session.
	local now = os.clock()
	refreshTimer(cs, now)
	refreshTimer(ct, now)
end

local function step()
	local now = os.clock()
	for session in sessions do
		local toRemove: { Combatant } = {}
		for combatant, timestamp in session.Members do
			if combatant:GetHealth() <= 0 or now - timestamp > COMBAT_TIMEOUT then
				table.insert(toRemove, combatant)
			end
		end
		for _, combatant in toRemove do
			session.Members[combatant] = nil
			combatant.CombatSession = nil
		end
		if not hasOpposedAlivePair(session) then
			endSession(session)
		end
	end
end

--[=[
	Wires the heartbeat-driven tick. Idempotent. Called once from `ServerInitializer`.
	@within CombatServer
]=]
function CombatServer.Init()
	if started then
		return
	end
	started = true
	RunService.Heartbeat:Connect(function(dt)
		accumulator += dt
		if accumulator < TICK_INTERVAL then
			return
		end
		accumulator = 0
		step()
	end)
end

return CombatServer
