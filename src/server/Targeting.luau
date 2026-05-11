--!strict

--[=[
	@class Targeting
	Spatial queries over server combatants. Two layers:

	1. **Pure geometric predicates** — `IsPointIn*` functions that ask whether
	   a `point` lies inside a named shape. No combatant knowledge, just math.
	   Reusable for any spatial check (behavior arrival, leash range, future
	   placement-validity, etc.).

	2. **Combatant-finding queries** — `NearestCombatant*` functions that
	   combine the geometric primitives with `CombatServer`'s live-combatant
	   registry plus a `Filter` predicate. The geometric arguments (CFrame,
	   radius, angle) are decoupled from the notion of an activator; pass an
	   explicit filter to decide which candidates qualify.

	The common "hostile to me" filter is exposed via the `HostileTo(seeker)`
	factory. Custom filters (e.g. allies for a heal-target query) follow the
	same `Filter` shape.
]=]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local CombatServer = require(ServerScriptService.Server.Servers.CombatServer)
local CombatTypes = require(ReplicatedStorage.Shared.Types.CombatTypes)

type Combatant = CombatTypes.Combatant

--[=[
	@type Filter (candidate: Combatant) -> boolean
	@within Targeting
	Predicate deciding whether a combatant qualifies for a `Nearest*` query.
	Geometric (range, shape) checks are handled by the query itself; the
	filter handles team / status / self-exclusion / etc.
]=]
export type Filter = (candidate: Combatant) -> boolean

local Targeting = {}

--[=[
	A `Filter` that only excludes dead combatants. Useful default for queries
	that don't have a notion of "self" or hostility (e.g. environmental
	point-anchored effects).
	@within Targeting
	@param candidate Combatant
	@return boolean
]=]
function Targeting.Alive(candidate: Combatant): boolean
	return candidate:GetHealth() > 0
end

--[=[
	Returns a `Filter` that accepts only combatants that are alive, not
	`seeker` itself, and hostile to `seeker` per `CombatTypes.IsHostile`. The
	common case for "who can I attack right now."
	@within Targeting
	@param seeker Combatant
	@return Filter
]=]
function Targeting.HostileTo(seeker: Combatant): Filter
	return function(candidate: Combatant): boolean
		if candidate == seeker then
			return false
		end
		if candidate:GetHealth() <= 0 then
			return false
		end
		return CombatTypes.IsHostile(seeker, candidate)
	end
end

--[=[
	Returns whether `point` lies inside an upright cylinder of the given `radius`
	centered at `center`, with **height equal to the diameter** (so the vertical
	tolerance is `±radius`).

	This shape is used wherever a denizen's controller, which navigates only on
	the XZ plane, would be misled by a pure-3D distance check. A 3D radius would
	trap behaviors against unsatisfiable Y deltas; a pure-XZ check would let
	behaviors fire across arbitrary elevations. The diameter-tall cylinder is a
	pragmatic middle ground — generous enough to absorb small physics-driven
	elevation drift, tight enough that a target on a high ledge or under a floor
	doesn't qualify.
	@within Targeting
	@param point Vector3
	@param center Vector3
	@param radius number
	@return boolean
]=]
function Targeting.IsPointInCylinder(point: Vector3, center: Vector3, radius: number): boolean
	local dx = point.X - center.X
	local dy = point.Y - center.Y
	local dz = point.Z - center.Z
	return dx * dx + dz * dz <= radius * radius and math.abs(dy) <= radius
end

--[=[
	Returns whether `point` lies inside the sphere of `radius` centered at
	`center`. Pure 3D distance check.
	@within Targeting
	@param point Vector3
	@param center Vector3
	@param radius number
	@return boolean
]=]
function Targeting.IsPointInSphere(point: Vector3, center: Vector3, radius: number): boolean
	return (point - center).Magnitude <= radius
end

--[=[
	Returns whether `point` lies inside a cone whose apex is at `origin`,
	axis points along `direction` (assumed unit-length), reach is `range`,
	and **total opening angle** is `coneAngle` (radians). The cone is the
	classic "flashlight" shape — half-angle from axis to edge is `coneAngle / 2`.
	@within Targeting
	@param point Vector3
	@param origin Vector3
	@param direction Vector3 -- Unit-length cone axis.
	@param range number
	@param coneAngle number -- Full cone opening angle in radians.
	@return boolean
]=]
function Targeting.IsPointInCone(
	point: Vector3,
	origin: Vector3,
	direction: Vector3,
	range: number,
	coneAngle: number
): boolean
	local toPoint = point - origin
	local dist = toPoint.Magnitude
	if dist > range then
		return false
	end
	if toPoint:FuzzyEq(Vector3.zero) then
		return true
	end
	return direction:Dot(toPoint.Unit) >= math.cos(coneAngle / 2)
end

--[=[
	Returns whether `point` lies inside a wedge — a cylindrical sector
	extruded vertically. The wedge is anchored at `origin`, opens horizontally
	along the XZ projection of `direction` with total opening angle
	`coneAngle` (radians) and planar reach `range`, and extends `height / 2`
	above and below `origin.Y`.

	Useful for ground-based AoE attacks (the "swing arc" around a player or
	NPC) where vertical position matters only within a tolerance.
	@within Targeting
	@param point Vector3
	@param origin Vector3 -- Wedge apex.
	@param direction Vector3 -- Wedge facing; only the XZ component is used.
	@param range number -- Planar reach from `origin`.
	@param height number -- Total vertical extrusion; `±height / 2` around `origin.Y`.
	@param coneAngle number -- Full opening angle in radians.
	@return boolean
]=]
function Targeting.IsPointInWedge(
	point: Vector3,
	origin: Vector3,
	direction: Vector3,
	range: number,
	height: number,
	coneAngle: number
): boolean
	local delta = point - origin
	if math.abs(delta.Y) > (height / 2) then
		return false
	end
	local toPoint = delta * Vector3.new(1, 0, 1)
	local dist = toPoint.Magnitude
	if dist > range then
		return false
	end
	if toPoint:FuzzyEq(Vector3.zero) then
		return true
	end
	local flatDirection = direction * Vector3.new(1, 0, 1)
	return flatDirection.Unit:Dot(toPoint.Unit) >= math.cos(coneAngle / 2)
end

--[=[
	Returns the closest combatant by 3D distance whose position lies inside a
	cone of `range` studs and total opening angle `coneAngle` (radians),
	rooted at `cframe.Position` and opening along `cframe.LookVector`, that
	passes `filter`. `nil` if no candidate qualifies.

	The geometric arguments are deliberately decoupled from the seeker — pass
	the activator's CFrame for the standard "in front of me" scan, or any
	other CFrame for cone-anchored effects (e.g. a projectile firing forward
	from a launcher).
	@within Targeting
	@param cframe CFrame -- Cone apex + axis direction (`LookVector`).
	@param range number
	@param coneAngle number -- Full cone opening angle in radians.
	@param filter Filter -- Combine with `HostileTo` for "find me an enemy."
	@return Combatant?
]=]
function Targeting.NearestCombatantInCone(cframe: CFrame, range: number, coneAngle: number, filter: Filter): Combatant?
	local origin = cframe.Position
	local forward = cframe.LookVector
	local best: Combatant? = nil
	local bestDistSq = math.huge
	for candidate in CombatServer.GetCombatants() do
		if not filter(candidate) then
			continue
		end
		local pos = candidate:GetCFrame().Position
		if not Targeting.IsPointInCone(pos, origin, forward, range, coneAngle) then
			continue
		end
		local distSq = (pos - origin).Magnitude ^ 2
		if distSq < bestDistSq then
			best = candidate
			bestDistSq = distSq
		end
	end
	return best
end

--[=[
	Returns the closest combatant by 3D distance whose position lies inside a
	wedge of `range` studs planar reach, `height` studs total vertical
	extrusion, and total opening angle `coneAngle` (radians), rooted at
	`cframe.Position` and opening along the XZ projection of `cframe.LookVector`,
	that passes `filter`. `nil` if no candidate qualifies.

	Use over `NearestCombatantInCone` when you want vertical position to be
	bounded by a fixed extrusion rather than coupled to the planar reach —
	melee swings, ground-stomps, and similar attacks where reach forward is
	independent of reach up/down.
	@within Targeting
	@param cframe CFrame -- Wedge apex + axis direction (`LookVector`).
	@param range number -- Planar reach from the apex.
	@param height number -- Total vertical extrusion; `±height / 2` around `cframe.Position.Y`.
	@param coneAngle number -- Full opening angle in radians.
	@param filter Filter -- Combine with `HostileTo` for "find me an enemy."
	@return Combatant?
]=]
function Targeting.NearestCombatantInWedge(
	cframe: CFrame,
	range: number,
	height: number,
	coneAngle: number,
	filter: Filter
): Combatant?
	local origin = cframe.Position
	local forward = cframe.LookVector
	local best: Combatant? = nil
	local bestDistSq = math.huge
	for candidate in CombatServer.GetCombatants() do
		if not filter(candidate) then
			continue
		end
		local pos = candidate:GetCFrame().Position
		if not Targeting.IsPointInWedge(pos, origin, forward, range, height, coneAngle) then
			continue
		end
		local distSq = (pos - origin).Magnitude ^ 2
		if distSq < bestDistSq then
			best = candidate
			bestDistSq = distSq
		end
	end
	return best
end

--[=[
	Returns the closest combatant to `point` by 3D distance within `range`
	studs that passes `filter`. `nil` if no candidate qualifies. Useful for
	point-anchored queries like ground-target AoEs or "anyone near this spot."
	@within Targeting
	@param point Vector3
	@param range number
	@param filter Filter
	@return Combatant?
]=]
function Targeting.NearestCombatantToPoint(point: Vector3, range: number, filter: Filter): Combatant?
	local best: Combatant? = nil
	local bestDistSq = math.huge
	local rangeSq = range * range
	for candidate in CombatServer.GetCombatants() do
		if not filter(candidate) then
			continue
		end
		local distSq = (candidate:GetCFrame().Position - point).Magnitude ^ 2
		if distSq <= rangeSq and distSq < bestDistSq then
			best = candidate
			bestDistSq = distSq
		end
	end
	return best
end

return Targeting
