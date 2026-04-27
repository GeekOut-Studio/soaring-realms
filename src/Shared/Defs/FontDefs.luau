local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Sift = require(ReplicatedStorage.Packages.Sift)

local Defs = {
	Normal = { "rbxasset://fonts/families/SourceSansPro.json", Enum.FontWeight.Regular },
	Bold = { "rbxasset://fonts/families/SourceSansPro.json", Enum.FontWeight.Bold },
}

return Sift.Dictionary.map(Defs, function(def)
	return Font.new(table.unpack(def))
end)
