local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local React = require(ReplicatedStorage.Packages.React)
local Container = require(ReplicatedStorage.Shared.React.Common.Container)
local GridLayout = require(ReplicatedStorage.Shared.React.Common.GridLayout)
local Label = require(ReplicatedStorage.Shared.React.Common.Label)
local ColorDefs = require(ReplicatedStorage.Shared.Defs.ColorDefs)
local ContextMenuContext = require(ReplicatedStorage.Shared.React.ContextMenuContext)
local EquipmentClient = require(ReplicatedStorage.Shared.Clients.EquipmentClient)
local EquipmentTypes = require(ReplicatedStorage.Shared.Types.EquipmentTypes)
local InventoryTypes = require(ReplicatedStorage.Shared.Types.InventoryTypes)
local ItemDefs = require(ReplicatedStorage.Shared.Defs.ItemDefs)

type EquipmentSlot = EquipmentTypes.EquipmentSlot
type Item = InventoryTypes.Item

local e = React.createElement

local TAP_THRESHOLD = 10

local GRID_COLUMNS = 5
local BLANK = "X"

local LAYOUT: { { string } } = {
	{ BLANK, BLANK, "Head", BLANK, BLANK },
	{ BLANK, "Back", "Neck", BLANK, BLANK },
	{ "RingRight", "Hands", "Torso", BLANK, "RingLeft" },
	{ "MainHandRanged", "MainHandMelee", "Legs", "Waist", "Offhand" },
	{ BLANK, BLANK, "Feet", BLANK, BLANK },
}

type SlotProps = {
	SlotKey: EquipmentSlot,
	Item: Item?,
	LayoutOrder: number,
}

local function EquipmentSlotComponent(props: SlotProps)
	local contextMenuContext = React.useContext(ContextMenuContext.Context)

	local item = props.Item

	local function buildActions(): { ContextMenuContext.ContextMenuAction }
		return {
			{
				Label = "Unequip",
				OnSelect = function()
					EquipmentClient.Unequip(props.SlotKey)
				end,
			},
		}
	end

	local function openMenu(screenPos: Vector2)
		local viewport = workspace.CurrentCamera.ViewportSize
		contextMenuContext.OpenContextMenu(
			UDim2.fromScale(screenPos.X / viewport.X, screenPos.Y / viewport.Y),
			buildActions()
		)
	end

	local placeholder = EquipmentTypes.SlotLabels[props.SlotKey] or props.SlotKey
	local text: string
	if item ~= nil then
		local def = ItemDefs[item.Kind]
		local name = if def ~= nil then def.Name else item.Kind
		text = if item.Count ~= nil then name .. "\n×" .. item.Count else name
	else
		text = placeholder
	end

	return e(Container, {
		Native = {
			LayoutOrder = props.LayoutOrder,
			BackgroundColor3 = ColorDefs.SlotBackground,
			[React.Event.InputBegan] = function(_, input)
				if item == nil then
					return
				end

				if input.UserInputType == Enum.UserInputType.MouseButton2 then
					openMenu(UserInputService:GetMouseLocation())
				elseif
					input.UserInputType == Enum.UserInputType.Touch
					and input.UserInputState == Enum.UserInputState.Begin
				then
					local startPos = Vector2.new(input.Position.X, input.Position.Y)
					local cancelled = false
					local touchInput = input

					local movedConn: RBXScriptConnection
					local endedConn: RBXScriptConnection

					movedConn = UserInputService.InputChanged:Connect(function(changedInput)
						if changedInput ~= touchInput then
							return
						end
						local delta = Vector2.new(changedInput.Position.X, changedInput.Position.Y) - startPos
						if delta.Magnitude > TAP_THRESHOLD then
							cancelled = true
							movedConn:Disconnect()
							endedConn:Disconnect()
						end
					end)

					endedConn = UserInputService.InputEnded:Connect(function(endedInput)
						if endedInput ~= touchInput then
							return
						end
						movedConn:Disconnect()
						endedConn:Disconnect()
						if not cancelled then
							openMenu(UserInputService:GetMouseLocation())
						end
					end)
				end
			end,
		},
	}, {
		ItemLabel = e(Label, {
			Native = {
				TextColor3 = ColorDefs.TextPrimary,
				TextSize = 13,
				TextWrapped = true,
				TextTransparency = if item ~= nil then 0 else 0.5,
				Text = text,
			},
		}),
		Stroke = e("UIStroke", {
			Color = ColorDefs.SlotBorder,
			Thickness = 1,
		}),
	})
end

local function BlankCell(props: { LayoutOrder: number })
	return e(Container, {
		Native = {
			LayoutOrder = props.LayoutOrder,
			BackgroundTransparency = 1,
		},
	})
end

local function Equipment()
	local equipment, setEquipment = React.useState({} :: EquipmentTypes.Equipment)

	React.useEffect(function()
		return EquipmentClient.ObserveEquipment(function(eq)
			setEquipment(eq)
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
				CellSize = UDim2.new(1 / GRID_COLUMNS, -4, 0, -4),
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

	local layoutOrder = 0
	for rowIndex, row in LAYOUT do
		for colIndex, slotKey in row do
			layoutOrder += 1
			local cellName = "Cell_" .. rowIndex .. "_" .. colIndex
			if slotKey == BLANK then
				children[cellName] = e(BlankCell, { LayoutOrder = layoutOrder })
			else
				children[cellName] = e(EquipmentSlotComponent, {
					SlotKey = slotKey :: EquipmentSlot,
					Item = equipment[slotKey],
					LayoutOrder = layoutOrder,
				})
			end
		end
	end

	return e(Container, {
		Native = {
			Size = UDim2.fromScale(1, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
		},
	}, children)
end

return Equipment
