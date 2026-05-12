-- React hook returning a binding that's `true` when the drop target with this
-- `id` is the one currently hovered during an active drag, and `false`
-- otherwise. Backed by `DragContext.SubscribeDropTargetHover` — the binding
-- updates without triggering a re-render, so consumers should drive Roblox
-- properties (`UIStroke.Thickness`, `BackgroundColor3`, etc.) via `binding:map`
-- rather than reading the value at render time.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local React = require(ReplicatedStorage.Packages.React)

local DragContext = require(ReplicatedStorage.Shared.React.DragContext)

return function(id: string)
	local dragContext = React.useContext(DragContext.Context)
	local hovered, setHovered = React.useBinding(false)

	React.useEffect(function()
		return dragContext.SubscribeDropTargetHover(id, setHovered)
	end, { id, dragContext.SubscribeDropTargetHover } :: { any })

	return hovered
end
