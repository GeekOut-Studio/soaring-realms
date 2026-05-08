--!strict

--[=[
	@class Targeting
	Spatial predicates used by denizen behavior states and predicates to answer
	"is this point/entity in scope?" questions — range checks today, line-of-sight
	and area-of-effect shape predicates as they land.
]=]

local Targeting = {}

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
function Targeting.WithinCylinder(point: Vector3, center: Vector3, radius: number): boolean
	local dx = point.X - center.X
	local dy = point.Y - center.Y
	local dz = point.Z - center.Z
	return dx * dx + dz * dz <= radius * radius and math.abs(dy) <= radius
end

return Targeting
