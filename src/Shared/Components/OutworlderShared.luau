--!strict

--[=[
	@class OutworlderShared
	Pure, side-effect-light state-to-state helpers shared between the server-authoritative
	`Outworlder` component and the client-side `OutworlderClient`.

	Keeping these in one module guarantees that the client's optimistic predictions and
	the server's authoritative simulation can't drift on rate constants, threshold logic,
	or the physical effect of a movement mode.
]=]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MovementTypes = require(ReplicatedStorage.Shared.Types.MovementTypes)

local OutworlderShared = {}

--[=[
	Applies the physical effects of `mode` to `controllerManager`. Currently sets
	`BaseMoveSpeed`; future additions (e.g. crouch hip-height changes) belong here so both
	sides stay in sync.
	@within OutworlderShared
	@param controllerManager ControllerManager
	@param mode MovementMode
]=]
function OutworlderShared.ApplyMode(controllerManager: ControllerManager, mode: MovementTypes.MovementMode)
	controllerManager.BaseMoveSpeed = MovementTypes.Speeds[mode]
end

--[=[
	Returns whether `controllerManager`'s `MovingDirection` represents non-zero movement
	intent. Uses `FuzzyEq` against `Vector3.zero` so we avoid the implicit `sqrt` in
	`Magnitude`.
	@within OutworlderShared
	@param controllerManager ControllerManager
	@return boolean
]=]
function OutworlderShared.IsMoving(controllerManager: ControllerManager): boolean
	return not controllerManager.MovingDirection:FuzzyEq(Vector3.zero)
end

--[=[
	Returns whether the character is currently being driven by its `GroundController`
	(as opposed to airborne / swimming / climbing). Used to gate ground-only behaviors
	like crouch-walk animation playback and to detect jumps/falls for crouch exit.
	@within OutworlderShared
	@param controllerManager ControllerManager
	@return boolean
]=]
function OutworlderShared.IsGrounded(controllerManager: ControllerManager): boolean
	local active = controllerManager.ActiveController
	return active ~= nil and active:IsA("GroundController")
end

--[=[
	Drains stamina for one `dt` step. If `mode == "Sprint"` and `isMoving`,
	returns `stamina - SprintStaminaDrainPerSecond * dt` clamped to 0.
	Otherwise returns `stamina` unchanged.

	Regen is intentionally *not* part of this function: it's authoritative
	server-only logic (with a delay timer driven by drain edges) and lives on
	the server-side `Outworlder` component. The client uses this same function
	to predict drain locally and waits for replication to see regen.
	@within OutworlderShared
	@param stamina number
	@param mode MovementMode
	@param isMoving boolean
	@param dt number
	@return number -- new stamina
]=]
function OutworlderShared.StepStaminaDrain(
	stamina: number,
	mode: MovementTypes.MovementMode,
	isMoving: boolean,
	dt: number
): number
	if mode == "Sprint" and isMoving then
		return math.max(0, stamina - MovementTypes.SprintStaminaDrainPerSecond * dt)
	end
	return stamina
end

return OutworlderShared
