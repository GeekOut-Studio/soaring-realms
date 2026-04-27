local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local React = require(ReplicatedStorage.Packages.React)
local InventoryTypes = require(ReplicatedStorage.Shared.Types.InventoryTypes)

local e = React.createElement

--[=[
	@interface DragItem
	@within DragContext
	@field Item InventoryTypes.Item
	@field SourceContainer string
	@field SourceSlot string
]=]
export type DragItem = {
	Item: InventoryTypes.Item,
	SourceContainer: string,
	SourceSlot: string,
}

type RegistryEntry = {
	OnDrop: (dragItem: DragItem) -> (),
}

--[=[
	@interface DragContextValue
	@within DragContext
	@field DragState DragItem? -- Currently dragged item; nil when idle.
	@field BeginDrag (item: InventoryTypes.Item, sourceContainer: string, sourceSlot: string) -> ()
	@field CancelDrag () -> ()
	@field RegisterDropTarget (id: string, ref: GuiObject, onDrop: (dragItem: DragItem) -> ()) -> ()
	@field UnregisterDropTarget (id: string, ref: GuiObject) -> ()
]=]
export type DragContextValue = {
	DragState: DragItem?,
	BeginDrag: (item: InventoryTypes.Item, sourceContainer: string, sourceSlot: string) -> (),
	CancelDrag: () -> (),
	RegisterDropTarget: (id: string, ref: GuiObject, onDrop: (dragItem: DragItem) -> ()) -> (),
	UnregisterDropTarget: (id: string, ref: GuiObject) -> (),
}

local defaultValue: DragContextValue = {
	DragState = nil,
	BeginDrag = function() end,
	CancelDrag = function() end,
	RegisterDropTarget = function() end,
	UnregisterDropTarget = function() end,
}

--[=[
	@class DragContext
	React context and provider for inventory drag-and-drop state.
	Drop targets register their own OnDrop callbacks; the provider mediates
	between draggable items and registered targets via GetGuiObjectsAtPosition.
]=]
local Context = React.createContext(defaultValue)

local function Provider(props: { children: any })
	local dragState, setDragState = React.useState(nil :: DragItem?)
	local hoveredEntry = React.useRef(nil :: RegistryEntry?)
	local registry = React.useRef({} :: { [string]: RegistryEntry })
	local instanceMap = React.useRef({} :: { [GuiObject]: RegistryEntry })

	local contextValue: DragContextValue = {
		DragState = dragState,
		BeginDrag = function(item, sourceContainer, sourceSlot)
			setDragState({
				Item = item,
				SourceContainer = sourceContainer,
				SourceSlot = sourceSlot,
			})
		end,
		CancelDrag = function()
			setDragState(nil)
			hoveredEntry.current = nil
		end,
		RegisterDropTarget = function(id, instance, onDrop)
			local entry: RegistryEntry = { OnDrop = onDrop }
			registry.current[id] = entry
			instanceMap.current[instance] = entry
		end,
		UnregisterDropTarget = function(id, instance)
			registry.current[id] = nil
			instanceMap.current[instance] = nil
		end,
	}

	React.useEffect(function()
		if dragState == nil then
			return
		end

		local playerGui = Players.LocalPlayer.PlayerGui

		local movedConnection = UserInputService.InputChanged:Connect(function(input)
			if
				input.UserInputType ~= Enum.UserInputType.MouseMovement
				and input.UserInputType ~= Enum.UserInputType.Touch
			then
				return
			end

			local objects = playerGui:GetGuiObjectsAtPosition(input.Position.X, input.Position.Y)
			hoveredEntry.current = nil
			for _, obj in objects do
				local entry = instanceMap.current[obj]
				if entry ~= nil then
					hoveredEntry.current = entry
					break
				end
			end
		end)

		local endedConnection = UserInputService.InputEnded:Connect(function(input)
			if
				input.UserInputType ~= Enum.UserInputType.MouseButton1
				and input.UserInputType ~= Enum.UserInputType.Touch
			then
				return
			end

			local entry = hoveredEntry.current
			if entry ~= nil then
				entry.OnDrop(dragState)
			end
			setDragState(nil)
			hoveredEntry.current = nil
		end)

		return function()
			movedConnection:Disconnect()
			endedConnection:Disconnect()
		end
	end, { dragState } :: { any })

	return e(Context.Provider, { value = contextValue }, props.children)
end

return {
	Context = Context,
	Provider = Provider,
}
