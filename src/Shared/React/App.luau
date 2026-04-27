local ReplicatedStorage = game:GetService("ReplicatedStorage")

local React = require(ReplicatedStorage.Packages.React)
local ContextMenuContext = require(ReplicatedStorage.Shared.React.ContextMenuContext)
local DragContext = require(ReplicatedStorage.Shared.React.DragContext)
local PlatformScale = require(ReplicatedStorage.Shared.React.Common.PlatformScale)
local ContextMenu = require(ReplicatedStorage.Shared.React.Hud.ContextMenu)
local DragPreview = require(ReplicatedStorage.Shared.React.Hud.DragPreview)
local Hud = require(ReplicatedStorage.Shared.React.Hud.Hud)
local TeleportOverlay = require(ReplicatedStorage.Shared.React.TeleportOverlay)

local e = React.createElement

local App = function()
	return e(ContextMenuContext.Provider, {}, {
		DragProvider = e(DragContext.Provider, {}, {
			GameGui = e("ScreenGui", {
				DisplayOrder = 1,
				ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
				ResetOnSpawn = false,
				IgnoreGuiInset = true,
			}, {
				PlatformScale = e(PlatformScale),
				Hud = e(Hud),
			}),
			TeleportOverlay = e(TeleportOverlay),
			DragPreview = e(DragPreview),
			ContextMenu = e(ContextMenu),
		}),
	})
end

return App
