--!strict

--[=[
	@class ActionTypes
	Type contracts and enum constants for the action system.
]=]

--[=[
	@type ActionResult "Continue" | "Complete" | "Fail"
	@within ActionTypes
	Returned by `Action:Update` each frame to signal the action's current status.
]=]
export type ActionResult = "Continue" | "Complete" | "Fail"

--[=[
	@type StopReason "Interrupted" | "Completed" | "Failed"
	@within ActionTypes
	Passed to `Action:Stop` to describe why the action ended.
]=]
export type StopReason = "Interrupted" | "Completed" | "Failed"

--[=[
	@interface Action
	@within ActionTypes
	@field Name string -- Human-readable name. Replicated to the owning client as the progress bar's label.
	@field AllowsMovement boolean -- Whether the character may move while this action runs.
	@field CompletionTimestamp number? -- Server-time (`Workspace:GetServerTimeNow()`) at which the current cycle completes. Mutually exclusive with `Alpha`.
	@field Alpha number? -- Direct progress value in 0..1. Mutually exclusive with `CompletionTimestamp`.
	@field Update (self: Action, dt: number) -> ActionResult -- Called every Heartbeat.
	@field Stop (self: Action, reason: StopReason) -> () -- Called when the action ends for any reason.
]=]
export type Action = {
	Name: string,
	AllowsMovement: boolean,
	CompletionTimestamp: number?,
	Alpha: number?,
	Update: (self: Action, dt: number) -> ActionResult,
	Stop: (self: Action, reason: StopReason) -> (),
}

--[=[
	@interface ActionProgress
	@within ActionTypes
	@field Name string
	@field CompletionTimestamp number? -- Mutually exclusive with `Alpha`.
	@field Alpha number? -- Mutually exclusive with `CompletionTimestamp`.

	Replicated payload describing the local player's current action progress. The
	server pushes this owner-only via `Outworlder`'s `ActionProgress` Comm property,
	or `nil` when no action is running (or the action exposes neither progress
	field).
]=]
export type ActionProgress = {
	Name: string,
	CompletionTimestamp: number?,
	Alpha: number?,
}

local ActionTypes = {}

--[=[
	@prop Result {Continue: ActionResult, Complete: ActionResult, Fail: ActionResult}
	@within ActionTypes
	Typed constants for `ActionResult` values.
]=]
ActionTypes.Result = {
	Continue = "Continue" :: ActionResult,
	Complete = "Complete" :: ActionResult,
	Fail = "Fail" :: ActionResult,
}

--[=[
	@prop StopReason {Interrupted: StopReason, Completed: StopReason, Failed: StopReason}
	@within ActionTypes
	Typed constants for `StopReason` values.
]=]
ActionTypes.StopReason = {
	Interrupted = "Interrupted" :: StopReason,
	Completed = "Completed" :: StopReason,
	Failed = "Failed" :: StopReason,
}

return ActionTypes
