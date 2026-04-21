type Cleanup = () -> ()
type Handler<T> = (value: T) -> Cleanup?

local Observing = {}

function Observing.observeCommProperty<T>(
	property: { Observe: (self: any, callback: (value: T) -> ()) -> RBXScriptConnection },
	handler: Handler<T>
): Cleanup
	local cleanup: Cleanup?

	local connection = property:Observe(function(value: T)
		if cleanup then
			cleanup()
		end
		cleanup = handler(value)
	end)

	return function()
		if cleanup then
			cleanup()
			cleanup = nil
		end
		connection:Disconnect()
	end
end

return Observing
