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
	@field AllowsMovement boolean -- Whether the character may move while this action runs.
	@field Update (self: Action, dt: number) -> ActionResult -- Called every Heartbeat.
	@field Stop (self: Action, reason: StopReason) -> () -- Called when the action ends for any reason.
]=]
export type Action = {
	AllowsMovement: boolean,
	Update: (self: Action, dt: number) -> ActionResult,
	Stop: (self: Action, reason: StopReason) -> (),
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
