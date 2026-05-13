local ReplicatedStorage = game:GetService("ReplicatedStorage")

local React = require(ReplicatedStorage.Packages.React)
local PlatformScale = require(ReplicatedStorage.Shared.React.Common.PlatformScale)
local Providers = require(ReplicatedStorage.Shared.React.Providers)
local BillboardsHost = require(ReplicatedStorage.Shared.React.Billboards.BillboardsHost)
local ContextMenu = require(ReplicatedStorage.Shared.React.Hud.ContextMenu)
local DragPreview = require(ReplicatedStorage.Shared.React.Hud.DragPreview)
local Hud = require(ReplicatedStorage.Shared.React.Hud.Hud)
local LootMenu = require(ReplicatedStorage.Shared.React.Hud.LootMenu)
local TeleportOverlay = require(ReplicatedStorage.Shared.React.TeleportOverlay)

local e = React.createElement

local App = function()
	return e(Providers, {}, {
		GameGui = e("ScreenGui", {
			DisplayOrder = 1,
			ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
			ResetOnSpawn = false,
			IgnoreGuiInset = true,
		}, {
			PlatformScale = e(PlatformScale),
			Hud = e(Hud),
			LootMenu = e(LootMenu),
		}),
		Billboards = e(BillboardsHost),
		TeleportOverlay = e(TeleportOverlay),
		DragPreview = e(DragPreview),
		ContextMenu = e(ContextMenu),
	})
end

return App
