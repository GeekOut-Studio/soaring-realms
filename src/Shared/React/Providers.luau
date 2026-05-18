local ReplicatedStorage = game:GetService("ReplicatedStorage")

local React = require(ReplicatedStorage.Packages.React)
local ContextMenuContext = require(ReplicatedStorage.Shared.React.ContextMenuContext)
local DialogueContext = require(ReplicatedStorage.Shared.React.DialogueContext)
local DragContext = require(ReplicatedStorage.Shared.React.DragContext)
local MenusContext = require(ReplicatedStorage.Shared.React.MenusContext)

local e = React.createElement

-- Top-level provider stack for the App. Add new context providers here in the
-- order they need to nest (outermost first). Consumers higher up the file
-- reference contexts; placing a provider above another means the lower one
-- can `useContext` the upper.
local function Providers(props: { children: any })
	return e(ContextMenuContext.Provider, {}, {
		DragProvider = e(DragContext.Provider, {}, {
			MenusProvider = e(MenusContext.Provider, {}, {
				DialogueProvider = e(DialogueContext.Provider, {}, props.children),
			}),
		}),
	})
end

return Providers
