-- Drives an alpha (0..1) over `duration` seconds via RunService.Heartbeat, calling
-- `callback` every frame with the current alpha. Returns a Promise that resolves on
-- natural completion. Cancelling the Promise stops the heartbeat connection early.
-- Guarantees: callback fires immediately with 0; never with alpha > 1; fires exactly
-- once with alpha = 1 at natural completion (not when cancelled).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Promise = require(ReplicatedStorage.Packages.Promise)

return function(duration: number, callback: (alpha: number) -> ())
	return Promise.new(function(resolve, _, onCancel)
		callback(0)
		local elapsed = 0
		local connection
		connection = RunService.Heartbeat:Connect(function(dt)
			elapsed += dt
			if elapsed >= duration then
				connection:Disconnect()
				callback(1)
				resolve()
				return
			end
			callback(elapsed / duration)
		end)
		onCancel(function()
			connection:Disconnect()
		end)
	end)
end
