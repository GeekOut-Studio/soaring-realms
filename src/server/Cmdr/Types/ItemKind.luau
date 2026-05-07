local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Sift = require(ReplicatedStorage.Packages.Sift)
local ItemDefs = require(ReplicatedStorage.Shared.Defs.ItemDefs)

return function(registry)
	registry:RegisterType("itemKind", registry.Cmdr.Util.MakeEnumType("ItemKind", Sift.Dictionary.keys(ItemDefs)))
end
