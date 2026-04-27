local ReplicatedStorage = game:GetService("ReplicatedStorage")

local React = require(ReplicatedStorage.Packages.React)
local DragContext = require(ReplicatedStorage.Shared.React.DragContext)
local DragPreview = require(ReplicatedStorage.Shared.React.Hud.DragPreview)
local Hud = require(ReplicatedStorage.Shared.React.Hud.Hud)
local TeleportOverlay = require(ReplicatedStorage.Shared.React.TeleportOverlay)

local e = React.createElement

local App = function()
	return e(DragContext.Provider, {}, {
		GameGui = e("ScreenGui", {
			DisplayOrder = 1,
			ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
			ResetOnSpawn = false,
			IgnoreGuiInset = true,
		}, {
			Hud = e(Hud),
		}),
		TeleportOverlay = e(TeleportOverlay),
		DragPreview = e(DragPreview),
	})
end

return App
