local ServerScriptService = game:GetService("ServerScriptService")

local SkillServer = require(ServerScriptService.Server.Servers.SkillServer)

return function(_, players, skillKind, amount)
	for _, player in players do
		SkillServer.AddExperience(player, skillKind, amount)
	end

	return "Done"
end
