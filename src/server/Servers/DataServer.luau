--!strict

--[=[
	@class DataServer
	In-memory player data store. A persistent DataStore implementation will replace
	this — at which point the eager-load on `PlayerAdded` will become the
	`GetAsync` boundary, the `Loaded` signal will fire after that resolves, and
	`UpdateData` will queue persistence. The synchronous-with-fallbacks read API
	exposed here is intentionally designed to survive that transition.

	Lifecycle: `Init` connects `Players.PlayerAdded` and `Players.PlayerRemoving`
	directly. Because `ServerInitializer` calls `DataServer.Init` before any
	other server's `Init`, our connections are established first.

	Two access patterns:

	- For per-player setup (initialize a property, run starter logic, etc.): use
	  `DataServer.ObservePlayer((player, data) -> cleanup?)`. This is a data-gated
	  wrapper around `Observers.observePlayer` — the callback fires only after
	  the player's data is loaded, and receives the loaded data directly.
	- For ad-hoc reads / writes outside that lifecycle: use `GetData`/`UpdateData`
	  directly. Both return `nil` (rather than asserting) when the player's data
	  isn't loaded, so downstream code can substitute defaults or refuse.
]=]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Sift = require(ReplicatedStorage.Packages.Sift)
local Signal = require(ReplicatedStorage.Packages.Signal)

local PlayerDataTypes = require(ReplicatedStorage.Shared.Types.PlayerDataTypes)

type PlayerData = PlayerDataTypes.PlayerData

local DataServer = {}

local dataByPlayer: { [Player]: PlayerData } = {}
local loaded = Signal.new() :: Signal.Signal<Player, PlayerData>

--[=[
	@prop Loaded Signal<Player, PlayerData>
	@within DataServer
	Fires when a player's data finishes loading. Useful for `ObservePlayer`
	internally; external callers should usually use `ObservePlayer` instead so
	currently-loaded players are also delivered.
]=]
DataServer.Loaded = loaded

local function loadFor(player: Player)
	if dataByPlayer[player] ~= nil then
		return
	end
	local data = table.freeze(Sift.Dictionary.copyDeep(PlayerDataTypes.Template))
	dataByPlayer[player] = data
	loaded:Fire(player, data)
end

local function unloadFor(player: Player)
	dataByPlayer[player] = nil
end

function DataServer.Init()
	for _, player in Players:GetPlayers() do
		loadFor(player)
	end
	Players.PlayerAdded:Connect(loadFor)
	Players.PlayerRemoving:Connect(unloadFor)
end

--[=[
	Returns whether `player`'s data is currently loaded.
	@within DataServer
	@param player Player
	@return boolean
]=]
function DataServer.IsLoaded(player: Player): boolean
	return dataByPlayer[player] ~= nil
end

--[=[
	Returns the player's frozen `PlayerData`, or `nil` if their data isn't
	loaded yet. Callers that read are expected to substitute a sensible default;
	callers that write are expected to refuse.
	@within DataServer
	@param player Player
	@return PlayerData?
]=]
function DataServer.GetData(player: Player): PlayerData?
	return dataByPlayer[player]
end

--[=[
	Applies `updater` to the player's current data, freezes the result, stores it,
	and returns it. Returns `nil` (without invoking `updater`) when the player's
	data isn't loaded — so write paths can refuse cleanly rather than corrupting
	later when real data lands.

	The updater must be pure: do not mutate its argument. Return a new table
	(typically via `Sift.Dictionary.merge(data, {...})`).
	@within DataServer
	@param player Player
	@param updater (PlayerData) -> PlayerData
	@return PlayerData? -- The new, frozen data, or `nil` if not loaded.
]=]
function DataServer.UpdateData(player: Player, updater: (PlayerData) -> PlayerData): PlayerData?
	local current = dataByPlayer[player]
	if current == nil then
		return nil
	end
	local newData = table.freeze(updater(current))
	dataByPlayer[player] = newData
	return newData
end

--[=[
	Like `Observers.observePlayer`, but data-gated: `callback` fires only after
	the player's data is loaded, and receives `(player, data)` directly.

	For players whose data is already loaded at subscribe time, the callback fires
	(via `task.spawn`) for each. For future joins, the callback fires after their
	`Loaded` event. The optional cleanup function returned by `callback` runs when
	the player leaves or the observer is disconnected.
	@within DataServer
	@server
	@param callback (player: Player, data: PlayerData) -> (() -> ())?
	@return () -> () -- Disconnects the observer.
]=]
function DataServer.ObservePlayer(callback: (player: Player, data: PlayerData) -> (() -> ())?): () -> ()
	local cleanups: { [Player]: () -> () } = {}
	local active = true

	local function trigger(player: Player, data: PlayerData)
		if not active then
			return
		end
		task.spawn(function()
			local cleanup = callback(player, data)
			if typeof(cleanup) ~= "function" then
				return
			end
			if active and player.Parent ~= nil then
				cleanups[player] = cleanup
			else
				task.spawn(cleanup)
			end
		end)
	end

	local function release(player: Player)
		local cleanup = cleanups[player]
		cleanups[player] = nil
		if cleanup ~= nil then
			task.spawn(cleanup)
		end
	end

	for player, data in dataByPlayer do
		trigger(player, data)
	end

	local loadedConn = loaded:Connect(trigger)
	local removingConn = Players.PlayerRemoving:Connect(release)

	return function()
		active = false
		loadedConn:Disconnect()
		removingConn:Disconnect()
		local player = next(cleanups)
		while player ~= nil do
			release(player)
			player = next(cleanups)
		end
	end
end

return DataServer
