local ReplicatedStorage = game:GetService("ReplicatedStorage")

local React = require(ReplicatedStorage.Packages.React)
local Container = require(ReplicatedStorage.Shared.React.Common.Container)
local PaddingAll = require(ReplicatedStorage.Shared.React.Common.PaddingAll)
local Hotbar = require(ReplicatedStorage.Shared.React.Hud.Hotbar)
local Menus = require(ReplicatedStorage.Shared.React.Hud.Menus)
local MobileControls = require(ReplicatedStorage.Shared.React.Hud.MobileControls)

local e = React.createElement

local function Hud()
	return e(Container, {
		Native = {
			AnchorPoint = Vector2.new(1, 1),
			Position = UDim2.fromScale(1, 1),
		},
	}, {
		Padding = e(PaddingAll, {
			Padding = UDim.new(0, 16),
		}),
		Menus = e(Menus),
		Hotbar = e(Hotbar),
		MobileControls = e(MobileControls),
	})
end

return Hud
