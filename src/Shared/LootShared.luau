--!strict

--[=[
	@class LootShared
	Pure roll helper for the denizen loot system. Lives shared so future
	previewers / UIs can call it without a server round-trip, even though
	the authoritative roll today happens server-side at `Denizen:Die`.

	Distinct from `WeightedRandom`: `WeightedRandom.Pick` is
	mutually-exclusive selection (one outcome wins), while
	`RollLootTable` does independent per-entry rolls (zero or more
	outcomes hit). Different probabilistic shapes, different APIs.
]=]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ItemDefs = require(ReplicatedStorage.Shared.Defs.ItemDefs)
local LootTypes = require(ReplicatedStorage.Shared.Types.LootTypes)

type LootTable = LootTypes.LootTable
type PlayerLoot = LootTypes.PlayerLoot

local LootShared = {}

local rng = Random.new()

--[=[
	Rolls a single `LootTable`. Each entry independently rolls its
	`Chance` (default `1`). On a hit, the quantity comes from one of two
	forms: range (`Min`/`Max`, uniform integer in `[Min, Max]`) or fixed
	(`Count`, default `1`). Stackable items (those whose `ItemDefs` entry
	has `MaxStackSize`) are emitted as one `Item` with `Count = quantity`;
	non-stackables are emitted as `quantity` separate `Item`s with no
	`Count` field, matching the contract `InventoryTypes.Item` documents.
	Unknown item kinds are skipped with a `warn`.
	@within LootShared
	@param lootTable LootTable
	@return PlayerLoot
]=]
function LootShared.RollLootTable(lootTable: LootTable): PlayerLoot
	local result: PlayerLoot = {}
	for _, entry in lootTable do
		local chance = entry.Chance
		if chance ~= nil and rng:NextNumber() >= chance then
			continue
		end

		local count: number
		if entry.Min ~= nil and entry.Max ~= nil then
			count = rng:NextInteger(entry.Min, entry.Max)
		else
			count = entry.Count or 1
		end
		if count <= 0 then
			continue
		end

		local def = ItemDefs[entry.Kind]
		if def == nil then
			warn(`LootShared.RollLootTable: unknown item kind "{entry.Kind}"; skipping`)
			continue
		end
		if def.MaxStackSize ~= nil then
			table.insert(result, { Kind = entry.Kind, Count = count })
		else
			for _ = 1, count do
				table.insert(result, { Kind = entry.Kind })
			end
		end
	end
	return result
end

return LootShared
