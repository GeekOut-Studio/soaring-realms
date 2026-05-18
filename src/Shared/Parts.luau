--!strict

--[=[
	@class Parts
	Small helpers for the recurring `BasePart` recipes used across systems —
	mostly invisible prompt/billboard anchors.
]=]

local Parts = {}

--[=[
	Mutates `part` into the standard "anchored, invisible, ignored by physics
	and raycasts" state used by prompt anchors, billboard anchors, and similar
	non-physical pieces of world state. Idempotent: calling it again on an
	already-intangible part is a no-op.
	@within Parts
	@param part BasePart
]=]
function Parts.MakeIntangible(part: BasePart)
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Transparency = 1
end

return Parts
