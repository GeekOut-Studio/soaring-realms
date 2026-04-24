--[=[
	@class Observing
	Utilities for observing Comm properties with cleanup-aware callbacks.
]=]

type Cleanup = () -> ()
type Handler<T> = (value: T) -> Cleanup?

local Observing = {}

--[=[
	Observes a Comm property, calling `handler` immediately with the current value
	and again on every subsequent change.

	If `handler` returns a cleanup function, it is called before the next invocation
	and when the observer is disconnected.
	@within Observing
	@param property {Observe: (self: any, callback: (value: T) -> ()) -> RBXScriptConnection} -- The Comm property to observe.
	@param handler (value: T) -> (() -> ())? -- Called on each value change; may return a cleanup.
	@return () -> () -- Disconnects the observer and runs the last cleanup when called.
]=]
function Observing.observeCommProperty<T>(
	property: { Observe: (self: any, callback: (value: T) -> ()) -> RBXScriptConnection },
	handler: Handler<T>
): Cleanup
	local cleanup: Cleanup?

	local connection = property:Observe(function(value: T)
		if cleanup ~= nil then
			cleanup()
		end
		cleanup = handler(value)
	end)

	return function()
		if cleanup ~= nil then
			cleanup()
			cleanup = nil
		end
		connection:Disconnect()
	end
end

return Observing
