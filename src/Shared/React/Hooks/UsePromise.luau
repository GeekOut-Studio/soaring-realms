local ReplicatedStorage = game:GetService("ReplicatedStorage")

local React = require(ReplicatedStorage.Packages.React)

return function(promiseFunc, default, deps)
	local value, setValue = React.useState(default)

	local func = React.useCallback(promiseFunc, deps)

	React.useEffect(function()
		local promise = func()
		if not promise then return end

		promise:andThen(setValue)

		return function()
			promise:cancel()
		end
	end, deps)

	return value
end
