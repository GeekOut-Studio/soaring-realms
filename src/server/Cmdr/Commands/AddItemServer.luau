local ServerScriptService = game:GetService("ServerScriptService")

local InventoryServer = require(ServerScriptService.Server.Servers.InventoryServer)

return function(_, players, itemKind, count)
	local resolvedCount = count or 1

	for _, player in players do
		InventoryServer.AddItem(player, itemKind, resolvedCount)
	end

	return "Done"
end
