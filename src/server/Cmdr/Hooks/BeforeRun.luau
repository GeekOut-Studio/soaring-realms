local RunService = game:GetService("RunService")

return function(registry)
	registry:RegisterHook("BeforeRun", function(context)
		if context.Group == "Help" then
			return
		end

		if RunService:IsStudio() then
			return
		end

		if context.Group == "Debug" then
			local player = context.Executor :: Player
			local rank = player:GetRankInGroupAsync(35353746)
			if rank >= 10 then
				if false then
					return
				else
					if rank >= 200 then
						return
					end
				end
			end
		end

		return "You do not have permission to run this command."
	end)
end
