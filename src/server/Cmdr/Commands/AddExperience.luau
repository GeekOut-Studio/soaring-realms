return {
	Name = "add-experience",
	Description = "Add experience to a skill for one or more players.",
	Group = "Debug",
	Args = {
		{ Name = "players", Type = "players" },
		{ Name = "skillKind", Type = "skillKind" },
		{ Name = "amount", Type = "integer" },
	},
}
