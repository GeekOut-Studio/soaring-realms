local ReplicatedStorage = game:GetService("ReplicatedStorage")

local SkillTypes = require(ReplicatedStorage.Shared.Types.SkillTypes)

return function(registry)
	registry:RegisterType("skillKind", registry.Cmdr.Util.MakeEnumType("SkillKind", SkillTypes.Kinds))
end
