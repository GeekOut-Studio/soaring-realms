-- React hook returning the local player's current hotbar payload. Subscribes
-- to `HotbarClient.ObserveHotbar` and re-renders on every change. Re-rendering
-- on every replication is fine because the server only re-publishes when the
-- bindings actually change (`HotbarServer` diffs against the last push).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local React = require(ReplicatedStorage.Packages.React)

local HotbarClient = require(ReplicatedStorage.Shared.Clients.HotbarClient)
local HotbarTypes = require(ReplicatedStorage.Shared.Types.HotbarTypes)

return function(): HotbarTypes.Hotbar
	local hotbar, setHotbar = React.useState(HotbarTypes.DefaultHotbar)

	React.useEffect(function()
		return HotbarClient.ObserveHotbar(function(value)
			setHotbar(value)
		end)
	end, {})

	return hotbar
end
