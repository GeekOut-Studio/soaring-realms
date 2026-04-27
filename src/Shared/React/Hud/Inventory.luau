local ReplicatedStorage = game:GetService("ReplicatedStorage")

local React = require(ReplicatedStorage.Packages.React)
local Container = require(ReplicatedStorage.Shared.React.Common.Container)
local GridLayout = require(ReplicatedStorage.Shared.React.Common.GridLayout)
local Label = require(ReplicatedStorage.Shared.React.Common.Label)
local ColorDefs = require(ReplicatedStorage.Shared.Defs.ColorDefs)
local InventoryClient = require(ReplicatedStorage.Shared.Clients.InventoryClient)
local ItemDefs = require(ReplicatedStorage.Shared.Defs.ItemDefs)
local InventoryTypes = require(ReplicatedStorage.Shared.Types.InventoryTypes)

type Inventory = InventoryTypes.Inventory

local e = React.createElement

local function Inventory()
	local inventory, setInventory = React.useState({} :: Inventory)

	React.useEffect(function()
		return InventoryClient.ObserveInventory(function(inv)
			setInventory(inv)
		end)
	end, {})

	local children: { [string]: any } = {
		Padding = e("UIPadding", {
			PaddingLeft = UDim.new(0, 4),
			PaddingTop = UDim.new(0, 4),
			PaddingBottom = UDim.new(0, 4),
		}),
		Grid = e(GridLayout, {
			Native = {
				CellSize = UDim2.new(1 / 5, -4, 0, -4),
				CellPadding = UDim2.fromOffset(4, 4),
				FillDirection = Enum.FillDirection.Horizontal,
			},
		}, {
			AspectRatio = e("UIAspectRatioConstraint", {
				AspectRatio = 1,
				AspectType = Enum.AspectType.ScaleWithParentSize,
			}),
		}),
	}

	for i = 1, InventoryTypes.Size do
		local item = inventory[tostring(i)]
		local text = ""
		if item ~= nil then
			local def = ItemDefs[item.Kind]
			local name = if def ~= nil then def.Name else item.Kind
			text = if item.Count ~= nil then name .. "\n×" .. item.Count else name
		end

		children["Slot" .. i] = e(Container, {
			Native = {
				LayoutOrder = i,
				BackgroundColor3 = ColorDefs.SlotBackground,
				BackgroundTransparency = 0,
			},
		}, {
			ItemLabel = e(Label, {
				Native = {
					TextColor3 = ColorDefs.TextPrimary,
					TextSize = 13,
					TextWrapped = true,
					Text = text,
				},
			}),
			Stroke = e("UIStroke", {
				Color = ColorDefs.SlotBorder,
				Thickness = 1,
			}),
		})
	end

	return e(Container, {
		Native = {
			Size = UDim2.fromScale(1, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
		},
	}, children)
end

return Inventory
