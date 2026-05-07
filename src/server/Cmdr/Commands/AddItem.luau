return {
	Name = "add-item",
	Description = "Add an item to the inventory of one or more players.",
	Group = "Debug",
	Args = {
		{ Name = "players", Type = "players" },
		{ Name = "itemKind", Type = "itemKind" },
		{ Name = "count", Type = "integer", Default = 1 },
	},
}
