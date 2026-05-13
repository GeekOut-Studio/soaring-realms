local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local React = require(ReplicatedStorage.Packages.React)
local Container = require(ReplicatedStorage.Shared.React.Common.Container)
local GridLayout = require(ReplicatedStorage.Shared.React.Common.GridLayout)
local ItemSlot = require(ReplicatedStorage.Shared.React.Common.ItemSlot)
local ContextMenuActions = require(ReplicatedStorage.Shared.React.ContextMenuActions)
local ContextMenuContext = require(ReplicatedStorage.Shared.React.ContextMenuContext)
local DragContext = require(ReplicatedStorage.Shared.React.DragContext)
local EquipmentClient = require(ReplicatedStorage.Shared.Clients.EquipmentClient)
local EquipmentTypes = require(ReplicatedStorage.Shared.Types.EquipmentTypes)
local InventoryClient = require(ReplicatedStorage.Shared.Clients.InventoryClient)
local ItemDefs = require(ReplicatedStorage.Shared.Defs.ItemDefs)
local InventoryTypes = require(ReplicatedStorage.Shared.Types.InventoryTypes)
local LootClient = require(ReplicatedStorage.Shared.Clients.LootClient)
local UsePlatform = require(ReplicatedStorage.Shared.React.Hooks.UsePlatform)

type Item = InventoryTypes.Item
type DragItem = DragContext.DragItem

local e = React.createElement

local function InventorySlot(props: {
	SlotKey: string,
	Item: Item?,
	LayoutOrder: number,
})
	local contextMenuContext = React.useContext(ContextMenuContext.Context)
	local platform = UsePlatform()

	local item = props.Item

	local function buildActions(slotKey: string): { ContextMenuContext.ContextMenuAction }
		local actions: { ContextMenuContext.ContextMenuAction } = {}

		if item ~= nil then
			local def = ItemDefs[item.Kind]
			if def ~= nil and def.EquipSlots ~= nil then
				for _, equipmentSlot in def.EquipSlots do
					local label = EquipmentTypes.SlotLabels[equipmentSlot] or equipmentSlot
					table.insert(actions, {
						Label = "Equip: " .. label,
						OnSelect = function()
							EquipmentClient.Equip(slotKey, equipmentSlot)
						end,
					})
				end
			end
		end

		table.insert(actions, {
			Label = "Drop",
			OnSelect = function()
				InventoryClient.DropItem(slotKey)
			end,
			Destructive = true,
		})

		return actions
	end

	local function openMenu(screenPos: Vector2)
		local viewport = workspace.CurrentCamera.ViewportSize
		contextMenuContext.OpenContextMenu(
			UDim2.fromScale(screenPos.X / viewport.X, screenPos.Y / viewport.Y),
			buildActions(props.SlotKey)
		)
	end

	-- Desktop tap performs the slot's default click action (equip etc.). Mobile
	-- has no right-click, so a tap opens the full context menu — same behavior
	-- the pre-extraction `InventorySlot` had.
	local function onTap()
		if platform == "Desktop" or platform == "Console" then
			local action = ContextMenuActions.FindClickAction(buildActions(props.SlotKey))
			if action ~= nil then
				action.OnSelect()
			end
		else
			openMenu(UserInputService:GetMouseLocation())
		end
	end

	-- Stable identity across renders so ItemSlot's `RegisterDropTarget` effect
	-- doesn't unregister/re-register every render. `props.SlotKey` is the only
	-- captured value that varies between slots, so it's the lone dep.
	local onDrop = React.useCallback(function(dragItem: DragItem)
		if dragItem.SourceContainer == "Inventory" then
			if dragItem.SourceSlot ~= props.SlotKey then
				InventoryClient.MoveItem(dragItem.SourceSlot, props.SlotKey)
			end
		elseif dragItem.SourceContainer == "LootBag" then
			-- `SourceSlot` is `"LootBag:<index>"` (the prefix keeps it unique
			-- against inventory slot ids in `DragContext`'s hover registry).
			local index = tonumber(dragItem.SourceSlot:match("^LootBag:(%d+)$"))
			if index ~= nil then
				LootClient.ClaimOne(index, props.SlotKey)
			end
		end
	end, { props.SlotKey } :: { any })

	return e(ItemSlot, {
		Item = item,
		LayoutOrder = props.LayoutOrder,
		SlotKey = props.SlotKey,
		SourceContainer = "Inventory",
		OnDrop = onDrop,
		OnTap = onTap,
		OnAlternate = openMenu,
	})
end

local function Inventory()
	local inventory, setInventory = React.useState({} :: InventoryTypes.Inventory)

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
		local slotKey = tostring(i)
		children["Slot" .. i] = e(InventorySlot, {
			SlotKey = slotKey,
			Item = inventory[slotKey],
			LayoutOrder = i,
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
