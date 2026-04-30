--[=[
	@class ContextMenuActions
	Pure helpers for working with `ContextMenuAction` lists. Lives alongside the gesture
	helper (`DragOrTap`) rather than inside `ContextMenuContext` so the context module stays
	focused on React-state plumbing.
]=]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ContextMenuContext = require(ReplicatedStorage.Shared.React.ContextMenuContext)

local ContextMenuActions = {}

--[=[
	Returns the first non-`Destructive` action in `actions`, or `nil` if every action is
	destructive. Use this to find a safe default for left-click (or other low-friction)
	invocations that shouldn't risk triggering an irreversible operation.
	@within ContextMenuActions
	@param actions { ContextMenuAction }
	@return ContextMenuAction?
]=]
function ContextMenuActions.FindClickAction(
	actions: { ContextMenuContext.ContextMenuAction }
): ContextMenuContext.ContextMenuAction?
	for _, action in actions do
		if not action.Destructive then
			return action
		end
	end
	return nil
end

return ContextMenuActions
