--!strict

--[=[
	@class MovementTypes
	Shared types and constants for character movement modes (Walk / Sprint / Crouch) and
	stamina. The character's current `MovementMode` is server-authoritative; the speed it
	maps to is read by both the server (when applying authoritative state) and the local
	client (when applying optimistic predictions).
]=]

--[=[
	@type MovementMode string
	@within MovementTypes
	String literal union of valid movement modes.
]=]
export type MovementMode = "Walk" | "Sprint" | "Crouch"

local MovementTypes = {}

--[=[
	@prop Modes {MovementMode}
	@within MovementTypes
	Ordered list of every valid movement mode.
]=]
MovementTypes.Modes = table.freeze({ "Walk", "Sprint", "Crouch" } :: { MovementMode })

--[=[
	@prop ModeSet {[string]: true}
	@within MovementTypes
	Set form of `Modes` for O(1) membership checks.
]=]
local modeSet: { [string]: true } = {}
for _, mode in MovementTypes.Modes do
	modeSet[mode] = true
end
MovementTypes.ModeSet = table.freeze(modeSet)

--[=[
	@prop DefaultMode MovementMode
	@within MovementTypes
	Mode characters spawn in.
]=]
MovementTypes.DefaultMode = "Walk" :: MovementMode

--[=[
	@prop Speeds {[string]: number}
	@within MovementTypes
	Maps each `MovementMode` to the `ControllerManager.BaseMoveSpeed` value that should
	be active while the character is in that mode.
]=]
MovementTypes.Speeds = table.freeze({
	Walk = 16,
	Sprint = 24,
	Crouch = 8,
} :: { [string]: number })

--[=[
	@prop MaxStamina number
	@within MovementTypes
	Upper bound on accumulated stamina. Characters spawn at this value.
]=]
MovementTypes.MaxStamina = 100

--[=[
	@prop SprintStaminaDrainPerSecond number
	@within MovementTypes
	Stamina depleted per second while `MovementMode == "Sprint"` and the character is
	actually moving (drain pauses if the player is sprinting in place).
]=]
MovementTypes.SprintStaminaDrainPerSecond = 25

--[=[
	@prop StaminaRegenPerSecond number
	@within MovementTypes
	Stamina recovered per second while not sprinting.
]=]
MovementTypes.StaminaRegenPerSecond = 10

--[=[
	@prop StaminaReplicationInterval number
	@within MovementTypes
	Server-side throttle for replicating Stamina to the owning client (seconds between
	updates). Avoids one packet per frame while still feeling responsive on a HUD.
]=]
MovementTypes.StaminaReplicationInterval = 0.1

--[=[
	@prop CrouchAirborneGraceSeconds number
	@within MovementTypes
	Time the character may remain airborne while in `Crouch` before being forced back to
	`Walk`. Provides hysteresis so `ActiveController` flickering on small terrain bumps
	doesn't repeatedly cancel a crouch.
]=]
MovementTypes.CrouchAirborneGraceSeconds = 0.15

return MovementTypes
