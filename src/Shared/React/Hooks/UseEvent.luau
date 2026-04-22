local ReplicatedStorage = game:GetService("ReplicatedStorage")

local React = require(ReplicatedStorage.Packages.React)

type Connection = {
	Disconnect: (Connection) -> (),
}
type Event = {
	Connect: (Event, (...any) -> ()) -> Connection,
}

return function(event: Event, callback: (...any) -> (), predicate: ((...any) -> boolean)?)
	React.useCallback(function()
		local conn = event:Connect(function(...)
			if (predicate == nil) or (predicate(...) == true) then
				callback(...)
			end
		end)

		return function()
			conn:Disconnect()
		end
	end, { event, callback, predicate })
end
