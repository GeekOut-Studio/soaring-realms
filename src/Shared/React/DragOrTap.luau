--[=[
	@class DragOrTap
	Helper for the "did the user drag or tap?" pattern used by inventory and equipment slots.

	Connects to `UserInputService.InputChanged` and `InputEnded`, watches for the cursor or
	finger to move past a threshold, and dispatches either `OnDrag` (threshold crossed before
	release) or `OnTap` (released without crossing). The `IsMove` / `IsRelease` predicates let
	callers recognize subsequent inputs as belonging to the same gesture — mouse gestures
	filter by `UserInputType`, touch gestures filter by `InputObject` identity.
]=]

local UserInputService = game:GetService("UserInputService")

local DragOrTap = {}

--[=[
	@interface Options
	@within DragOrTap
	@field StartPos Vector2 -- Cursor / finger position at the start of the gesture.
	@field IsMove (input: InputObject) -> boolean -- Predicate: is this `InputChanged` event part of the gesture?
	@field IsRelease (input: InputObject) -> boolean -- Predicate: is this `InputEnded` event the gesture's release?
	@field Threshold number -- Pixel magnitude past `StartPos` that promotes the gesture from tap to drag.
	@field OnDrag () -> () -- Called once when the threshold is crossed.
	@field OnTap () -> () -- Called once on release if the threshold was never crossed.
]=]
export type Options = {
	StartPos: Vector2,
	IsMove: (input: InputObject) -> boolean,
	IsRelease: (input: InputObject) -> boolean,
	Threshold: number,
	OnDrag: () -> (),
	OnTap: () -> (),
}

--[=[
	Begins tracking a press. Disconnects automatically when the gesture resolves
	(threshold crossed → `OnDrag`, or release → `OnTap`).
	@within DragOrTap
	@param options Options
]=]
function DragOrTap.Track(options: Options)
	local dragStarted = false
	local movedConn: RBXScriptConnection
	local endedConn: RBXScriptConnection

	movedConn = UserInputService.InputChanged:Connect(function(changedInput)
		if not options.IsMove(changedInput) then
			return
		end
		local delta = Vector2.new(changedInput.Position.X, changedInput.Position.Y) - options.StartPos
		if delta.Magnitude > options.Threshold and not dragStarted then
			dragStarted = true
			movedConn:Disconnect()
			endedConn:Disconnect()
			options.OnDrag()
		end
	end)

	endedConn = UserInputService.InputEnded:Connect(function(endedInput)
		if not options.IsRelease(endedInput) then
			return
		end
		movedConn:Disconnect()
		endedConn:Disconnect()
		if not dragStarted then
			options.OnTap()
		end
	end)
end

return DragOrTap
