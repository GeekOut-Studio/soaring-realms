--!strict

--[=[
	@class MenusContext
	React context for the bottom-right `Menus` panel. Owns which submenu
	is currently open and whether that choice is *forced* by an external
	consumer (e.g. `LootMenu` forces `Inventory` open while it's visible,
	storage will force it too).

	`OpenedMenu` is derived: if `ForcedMenu` is non-nil, that's what's
	open; otherwise the user's own choice from `OpenMenu`. User-initiated
	tab clicks no-op while a force is active. `IsForced` lets the tab
	row dim non-forced buttons.

	`SetForcedMenu(name)` is the programmatic lock. Pair with
	`SetForcedMenu(nil)` on cleanup; calling it twice with different
	names just overwrites.
]=]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local React = require(ReplicatedStorage.Packages.React)

local e = React.createElement

--[=[
	@interface MenusContextValue
	@within MenusContext
	@field OpenedMenu string? -- The currently open submenu key, or nil if none.
	@field IsForced boolean -- True iff the open menu is forced by `SetForcedMenu`.
	@field OpenMenu (name: string?) -> () -- User-initiated; no-op while forced.
	@field SetForcedMenu (name: string?) -> () -- Programmatic; nil clears the force.
]=]
export type MenusContextValue = {
	OpenedMenu: string?,
	IsForced: boolean,
	OpenMenu: (name: string?) -> (),
	SetForcedMenu: (name: string?) -> (),
}

local defaultValue: MenusContextValue = {
	OpenedMenu = nil,
	IsForced = false,
	OpenMenu = function() end,
	SetForcedMenu = function() end,
}

--[=[
	@prop Context React.Context<MenusContextValue>
	@within MenusContext
]=]
local Context = React.createContext(defaultValue)

--[=[
	@within MenusContext
	Provider component that owns the user-menu / forced-menu state.
	Wrap the App subtree containing `Menus` and any consumer that wants
	to force a menu open.
]=]
local function Provider(props: { children: any })
	local userMenu, setUserMenu = React.useState(nil :: string?)
	local forcedMenu, setForcedMenu = React.useState(nil :: string?)

	local openMenu = React.useCallback(function(name: string?)
		setUserMenu(function(current)
			-- `forcedMenu` is captured by the closure but reads stale state safely:
			-- if it changes between calls, the next call sees fresh state.
			return if forcedMenu ~= nil then current else name
		end)
	end, { forcedMenu } :: { any })

	local openedMenu = if forcedMenu ~= nil then forcedMenu else userMenu

	local value = React.useMemo(function(): MenusContextValue
		return {
			OpenedMenu = openedMenu,
			IsForced = forcedMenu ~= nil,
			OpenMenu = openMenu,
			SetForcedMenu = setForcedMenu,
		}
	end, { openedMenu, forcedMenu, openMenu } :: { any })

	return e(Context.Provider, { value = value }, props.children)
end

return {
	Context = Context,
	Provider = Provider,
}
