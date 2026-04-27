local ReplicatedStorage = game:GetService("ReplicatedStorage")

local React = require(ReplicatedStorage.Packages.React)

local e = React.createElement

--[=[
	@interface ContextMenuAction
	@within ContextMenuContext
	@field Label string -- Displayed text for the action.
	@field OnSelect () -> () -- Called when the user chooses this action.
]=]
export type ContextMenuAction = {
	Label: string,
	OnSelect: () -> (),
}

--[=[
	@interface ContextMenuState
	@within ContextMenuContext
	@field Position UDim2 -- Screen-space anchor for the menu panel.
	@field Actions { ContextMenuAction } -- Ordered list of actions to display.
]=]
export type ContextMenuState = {
	Position: UDim2,
	Actions: { ContextMenuAction },
}

--[=[
	@interface ContextMenuContextValue
	@within ContextMenuContext
	@field MenuState ContextMenuState? -- Active menu; nil when closed.
	@field OpenContextMenu (position: UDim2, actions: { ContextMenuAction }) -> ()
	@field CloseContextMenu () -> ()
]=]
export type ContextMenuContextValue = {
	MenuState: ContextMenuState?,
	OpenContextMenu: (position: UDim2, actions: { ContextMenuAction }) -> (),
	CloseContextMenu: () -> (),
}

local defaultValue: ContextMenuContextValue = {
	MenuState = nil,
	OpenContextMenu = function() end,
	CloseContextMenu = function() end,
}

--[=[
	@class ContextMenuContext
	React context and provider for a generic floating context menu.
	Callers supply a screen position and an ordered list of `ContextMenuAction`
	entries; the `ContextMenu` component renders them. No item or game knowledge
	lives here.
]=]
local Context = React.createContext(defaultValue)

local function Provider(props: { children: any })
	local menuState, setMenuState = React.useState(nil :: ContextMenuState?)

	local contextValue: ContextMenuContextValue = {
		MenuState = menuState,
		OpenContextMenu = function(position, actions)
			setMenuState({ Position = position, Actions = actions })
		end,
		CloseContextMenu = function()
			setMenuState(nil)
		end,
	}

	return e(Context.Provider, { value = contextValue }, props.children)
end

return {
	Context = Context,
	Provider = Provider,
}
