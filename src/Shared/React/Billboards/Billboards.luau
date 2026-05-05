--!strict

--[=[
	@class Billboards
	Generic registry of world-anchored UI billboards. Domain-agnostic: providers
	register an entry with a `BasePart` adornee, optional `BillboardGui` overrides
	(`Native`), and a `Render` callback returning the React subtree to draw inside
	the billboard. The App-level `BillboardsHost` reads the registry and renders
	one `BillboardGui` portal per entry.

	`Set`/`Remove` produce a fresh entries table (immutable update), so `GetAll`
	returns a different reference every time the registry changes. Subscribers can
	therefore mirror the registry into React state directly via `setState(GetAll())`
	on each `Changed` fire without manual copying or version tracking.

	Entries are keyed by an opaque string the provider chooses. A common pattern
	is `<class>:<unique>` (e.g. `OreNode:<guid>`) so different providers can't
	collide.
]=]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Sift = require(ReplicatedStorage.Packages.Sift)
local Signal = require(ReplicatedStorage.Packages.Signal)

--[=[
	@interface Entry
	@within Billboards
	@field Adornee BasePart -- The part the BillboardGui anchors to. Always wins over `Native.Adornee`.
	@field Native any -- Props merged into the `BillboardGui` defaults.
	@field Render () -> any -- Callback returning the React element to render inside the billboard.
]=]
export type Entry = {
	Adornee: BasePart,
	Native: any,
	Render: () -> any,
}

local Billboards = {}

local entries: { [string]: Entry } = {}
local changed = Signal.new() :: Signal.Signal<()>

--[=[
	@prop Changed Signal<()>
	@within Billboards
	Fires whenever the registry's contents change (add / replace / remove).
]=]
Billboards.Changed = changed

--[=[
	Adds or replaces the entry for `key`.
	@within Billboards
	@param key string
	@param entry Entry
]=]
function Billboards.Set(key: string, entry: Entry)
	entries = Sift.Dictionary.merge(entries, { [key] = entry })
	changed:Fire()
end

--[=[
	Removes the entry for `key`. No-op if no entry exists.
	@within Billboards
	@param key string
]=]
function Billboards.Remove(key: string)
	if entries[key] == nil then
		return
	end
	local next = Sift.Dictionary.copy(entries)
	next[key] = nil
	entries = next
	changed:Fire()
end

--[=[
	Returns the current entries table. Treat as read-only — mutations would
	bypass the immutable-update contract that subscribers rely on.
	@within Billboards
	@return {[string]: Entry}
]=]
function Billboards.GetAll(): { [string]: Entry }
	return entries
end

return Billboards
