--!strict

--[=[
	@class DialogueContext
	React context for the bottom-left `Dialogue` panel. Owns the currently
	displayed message (or nil when hidden). Any consumer in the App subtree
	can call `ShowMessage` to push text — used today by failed-requirement
	notifications and intended for NPC dialogue and general alerts.

	Newer messages replace older ones; there's no queue. `Dismiss` clears
	the panel.
]=]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local React = require(ReplicatedStorage.Packages.React)

local e = React.createElement

--[=[
	@interface DialogueContextValue
	@within DialogueContext
	@field Message string? -- The currently shown message, or nil if hidden.
	@field ShowMessage (text: string) -> () -- Replaces any current message.
	@field Dismiss () -> () -- Clears the panel.
]=]
export type DialogueContextValue = {
	Message: string?,
	ShowMessage: (text: string) -> (),
	Dismiss: () -> (),
}

local defaultValue: DialogueContextValue = {
	Message = nil,
	ShowMessage = function() end,
	Dismiss = function() end,
}

--[=[
	@prop Context React.Context<DialogueContextValue>
	@within DialogueContext
]=]
local Context = React.createContext(defaultValue)

--[=[
	@within DialogueContext
	Provider component that owns the dialogue message state. Wrap the App
	subtree containing `Dialogue` and any producers (e.g. the failed-action
	subscriber).
]=]
local function Provider(props: { children: any })
	local message, setMessage = React.useState(nil :: string?)

	local value = React.useMemo(function(): DialogueContextValue
		return {
			Message = message,
			ShowMessage = setMessage :: any,
			Dismiss = function()
				(setMessage :: any)(nil)
			end,
		}
	end, { message } :: { any })

	return e(Context.Provider, { value = value }, props.children)
end

return {
	Context = Context,
	Provider = Provider,
}
