--!strict

export type ActionResult = "Continue" | "Complete" | "Fail"
export type StopReason = "Interrupted" | "Completed" | "Failed"

export type Action = {
	AllowsMovement: boolean,
	Update: (self: Action, dt: number) -> ActionResult,
	Stop: (self: Action, reason: StopReason) -> (),
}

local Action = {}

Action.Result = {
	Continue = "Continue" :: ActionResult,
	Complete = "Complete" :: ActionResult,
	Fail = "Fail" :: ActionResult,
}

Action.StopReason = {
	Interrupted = "Interrupted" :: StopReason,
	Completed = "Completed" :: StopReason,
	Failed = "Failed" :: StopReason,
}

return Action
