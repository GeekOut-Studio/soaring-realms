local ReplicatedStorage = game:GetService("ReplicatedStorage")

local React = require(ReplicatedStorage.Packages.React)
local Container = require(ReplicatedStorage.Shared.React.Common.Container)
local HorizontalList = require(ReplicatedStorage.Shared.React.Common.HorizontalList)
local TextButton = require(ReplicatedStorage.Shared.React.Common.TextButton)
local VerticalList = require(ReplicatedStorage.Shared.React.Common.VerticalList)
local ColorDefs = require(ReplicatedStorage.Shared.Defs.ColorDefs)
local Inventory = require(ReplicatedStorage.Shared.React.Hud.Inventory)

local e = React.createElement

local BUTTON_SIZE = 56
local GAP = 4
local PANEL_WIDTH = 5 * BUTTON_SIZE + 4 * GAP

local MENU_DEFS = {
	{ Key = "Inventory", Label = "Inventory", Component = Inventory },
	{ Key = "Equipment", Label = "Equipment", Component = nil },
	{ Key = "Skills", Label = "Skills", Component = nil },
	{ Key = "Journal", Label = "Journal", Component = nil },
	{ Key = "Abilities", Label = "Abilities & Utility Magic", Component = nil },
}

local function Menus()
	local selectedMenu, setSelectedMenu = React.useState(nil :: string?)

	local buttons: { [string]: any } = {
		Layout = e(HorizontalList, { Native = { Padding = UDim.new(0, GAP) } }),
	}

	for i, menu in MENU_DEFS do
		local isSelected = selectedMenu == menu.Key
		buttons[menu.Key] = e(TextButton, {
			Native = {
				Size = UDim2.fromOffset(BUTTON_SIZE, BUTTON_SIZE),
				LayoutOrder = i,
				Text = menu.Label,
				TextSize = 12,
				BackgroundColor3 = if isSelected then ColorDefs.ButtonSelected else ColorDefs.ButtonIdle,
				[React.Event.Activated] = function()
					setSelectedMenu(if isSelected then nil else menu.Key)
				end,
			},
		}, {
			Stroke = e("UIStroke", {
				Color = ColorDefs.PanelBorder,
				Thickness = 1,
			}),
		})
	end

	local activeComponent = nil
	if selectedMenu ~= nil then
		for _, menu in MENU_DEFS do
			if menu.Key == selectedMenu and menu.Component ~= nil then
				activeComponent = e(menu.Component)
				break
			end
		end
	end

	return e(Container, {
		Native = {
			AnchorPoint = Vector2.new(1, 1),
			Position = UDim2.fromScale(1, 1),
			Size = UDim2.fromOffset(PANEL_WIDTH, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
		},
	}, {
		Layout = e(VerticalList, { Native = { Padding = UDim.new(0, GAP) } }),

		Content = if selectedMenu ~= nil
			then e(Container, {
				Native = {
					Active = true,
					Size = UDim2.fromOffset(PANEL_WIDTH, 0),
					AutomaticSize = Enum.AutomaticSize.Y,
					LayoutOrder = 1,
					BackgroundColor3 = ColorDefs.PanelBackground,
					BackgroundTransparency = 0,
				},
			}, {
				Submenu = activeComponent,
				Stroke = e("UIStroke", {
					Color = ColorDefs.PanelBorder,
					Thickness = 2,
				}),
			})
			else nil,

		ButtonRow = e(Container, {
			Native = {
				Size = UDim2.fromOffset(PANEL_WIDTH, BUTTON_SIZE),
				LayoutOrder = 2,
			},
		}, buttons),
	})
end

return Menus
