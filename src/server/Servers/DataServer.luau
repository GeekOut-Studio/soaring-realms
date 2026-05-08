--!strict

--[=[
	@class DataServer
	Player data store backed by ProfileStore (MAD Studio / loleris) for persistence and
	session locking. Wraps ProfileStore so the rest of the codebase reads and writes
	through the same immutable, frozen-table API regardless of the persistence backend.

	Lifecycle: `Init` connects `Players.PlayerAdded` and `Players.PlayerRemoving`
	directly. Because `ServerInitializer` calls `DataServer.Init` before any
	other server's `Init`, our connections are established first.

	The `Loaded` signal fires after `ProfileStore:StartSessionAsync` resolves, which
	yields. Callers that observe per-player setup should use `ObservePlayer` rather than
	connecting `Players.PlayerAdded` directly so they don't fire before data is ready.

	Two access patterns:

	- For per-player setup (initialize a property, run starter logic, etc.): use
	  `DataServer.ObservePlayer((player, data) -> cleanup?)`. This is a data-gated
	  wrapper around `Observers.observePlayer` — the callback fires only after
	  the player's data is loaded, and receives the loaded data directly.
	- For ad-hoc reads / writes outside that lifecycle: use `GetData`/`UpdateData`
	  directly. Both return `nil` (rather than asserting) when the player's data
	  isn't loaded, so downstream code can substitute defaults or refuse.

	On the inside, `Profile.Data` is the live mutable table ProfileStore auto-saves; we
	mirror it as a frozen snapshot in `dataByPlayer` for the API. `UpdateData` mutates
	`Profile.Data` in place to match the updater's result so auto-saves carry the change.
]=]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")

local Sift = require(ReplicatedStorage.Packages.Sift)
local Signal = require(ReplicatedStorage.Packages.Signal)

local ProfileStore = require(ServerScriptService.ServerPackages.ProfileStore)
local PlayerDataTypes = require(ReplicatedStorage.Shared.Types.PlayerDataTypes)

type PlayerData = PlayerDataTypes.PlayerData

local DataServer = {}

local PROFILE_STORE_NAME = "PlayerData"

local dataByPlayer: { [Player]: PlayerData } = {}
local profileByPlayer: { [Player]: any } = {}
-- Players for whom we're voluntarily ending the session ahead of a teleport. The
-- `OnSessionEnd` handler reads this to suppress its kick, since the player is on
-- their way to another place rather than being yanked out from under us.
local teleportingOut: { [Player]: true } = {}
local loaded = Signal.new() :: Signal.Signal<Player, PlayerData>

-- One ProfileStore for the whole game. We pass the template so first-time profiles
-- start with the same shape as `PlayerDataTypes.Template`, and `Profile:Reconcile()`
-- backfills any newly added top-level fields on existing profiles. Studio runs
-- against `.Mock` so test sessions don't pollute the live DataStore; live servers
-- use the real one.
local realStore = ProfileStore.New(PROFILE_STORE_NAME, PlayerDataTypes.Template)
local profileStore = if RunService:IsStudio() then realStore.Mock else realStore

--[=[
	@prop Loaded Signal<Player, PlayerData>
	@within DataServer
	Fires when a player's data finishes loading. Useful for `ObservePlayer`
	internally; external callers should usually use `ObservePlayer` instead so
	currently-loaded players are also delivered.
]=]
DataServer.Loaded = loaded

-- Replaces the contents of `profile.Data` with an unfrozen deep copy of `newData`.
-- Mutates in place so ProfileStore's auto-save sees the change — replacing the
-- table reference would orphan ProfileStore's tracking.
local function syncToProfile(profile: any, newData: PlayerData)
	for key in profile.Data do
		profile.Data[key] = nil
	end
	for key, value in newData :: any do
		profile.Data[key] = Sift.Dictionary.copyDeep(value)
	end
end

-- Recursively freezes `t` and every nested table, returning the same reference.
-- The `isfrozen` short-circuit makes this cheap on incremental updates where most
-- of the tree is structurally shared from the prior frozen snapshot — unchanged
-- sub-trees are skipped entirely.
local function deepFreeze<T>(t: T): T
	if typeof(t) == "table" and not table.isfrozen(t :: any) then
		for _, v in t :: any do
			deepFreeze(v)
		end
		table.freeze(t :: any)
	end
	return t
end

local function freezeSnapshot(source: any): PlayerData
	return deepFreeze(Sift.Dictionary.copyDeep(source)) :: PlayerData
end

local function loadFor(player: Player)
	if profileByPlayer[player] ~= nil then
		return
	end

	local profile = profileStore:StartSessionAsync(`Player_{player.UserId}`, {
		Cancel = function()
			return player.Parent ~= Players
		end,
	})

	if profile == nil then
		-- Either the player left during the load, or another server held the session
		-- past `START_SESSION_TIMEOUT`. Kick so they can rejoin and retry cleanly.
		player:Kick("Failed to load profile data. Please rejoin.")
		return
	end

	profile:AddUserId(player.UserId)
	profile:Reconcile()

	profile.OnSessionEnd:Connect(function()
		profileByPlayer[player] = nil
		dataByPlayer[player] = nil
		if teleportingOut[player] then
			-- We ended the session ourselves to hand off cleanly to another place;
			-- don't kick — the player is mid-teleport.
			teleportingOut[player] = nil
			return
		end
		-- Another server stole the session, or ProfileStore decided to end ours
		-- (shutdown, critical state). Either way, this server can no longer write
		-- to this profile, so kick the player off this server.
		player:Kick("Profile session ended. Please rejoin.")
	end)

	if player.Parent ~= Players then
		-- Player left while we were yielding. End the session so another server
		-- (or a future rejoin) can pick it up immediately.
		profile:EndSession()
		return
	end

	profileByPlayer[player] = profile
	local data = freezeSnapshot(profile.Data)
	dataByPlayer[player] = data
	loaded:Fire(player, data)
end

local function unloadFor(player: Player)
	local profile = profileByPlayer[player]
	profileByPlayer[player] = nil
	dataByPlayer[player] = nil
	if profile ~= nil then
		profile:EndSession()
	end
end

function DataServer.Init()
	for _, player in Players:GetPlayers() do
		task.spawn(loadFor, player)
	end
	Players.PlayerAdded:Connect(loadFor)
	Players.PlayerRemoving:Connect(unloadFor)
end

--[=[
	Ends `player`'s ProfileStore session and yields until the final save lands. Call
	this immediately before `TeleportService:TeleportAsync` so the destination server
	can `StartSessionAsync` with no session-steal wait.

	No-op when the player has no active session. Suppresses the usual "session ended"
	kick from the `OnSessionEnd` handler — the player is on their way to another
	place, not being booted.
	@within DataServer
	@yields
	@param player Player
]=]
function DataServer.EndSessionForTeleport(player: Player)
	local profile = profileByPlayer[player]
	if profile == nil then
		return
	end
	teleportingOut[player] = true
	profile:EndSession()
	-- Block until ProfileStore actually flushes and releases. `EndSession` itself
	-- is fire-and-forget; the `OnSessionEnd` signal is what tells us we're done.
	if profile:IsActive() then
		profile.OnSessionEnd:Wait()
	end
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
	local profile = profileByPlayer[player]
	if current == nil or profile == nil then
		return nil
	end
	local newData = deepFreeze(updater(current))
	syncToProfile(profile, newData)
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
