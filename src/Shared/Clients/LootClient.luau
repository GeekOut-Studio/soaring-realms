--!strict

--[=[
	@class LootClient
	Singleton bridge between the tag-driven `LootBagClient` component and
	the React-mounted `LootMenu`. Holds which bag (if any) is currently
	open and routes claim RPCs to it.

	Why a singleton: `LootBagClient` lives outside the React tree (it's a
	tag-driven Component instance), so React can't `useContext` it.
	Instead `LootBagClient` writes to `LootClient.OpenBag(self)` on
	prompt activation, and `LootMenu` subscribes via
	`OpenedBagChanged:Connect(setBag)`. Same shape as how the project
	bridges other Component-side state into React (e.g.
	`OutworlderClient` consumed via signals in the HUD).

	The RPCs (`ClaimOne` / `ClaimAll`) live here rather than on the React
	component itself per the convention that menus call into clients —
	keeps the menu free of Comm details and lets non-menu code path
	(future hotkey, scripted auto-loot, etc.) reuse the same calls.
]=]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Signal = require(ReplicatedStorage.Packages.Signal)

local LootClient = {}

local openedBag: any = nil
local openedBagChanged = Signal.new() :: Signal.Signal<any>

--[=[
	@prop OpenedBagChanged Signal<LootBagClient?>
	@within LootClient
	Fires with the new `OpenedBag` value (or `nil`) whenever the open
	bag changes.
]=]
LootClient.OpenedBagChanged = openedBagChanged

--[=[
	Returns the currently-open `LootBagClient` instance, or `nil`.
	@within LootClient
	@return any?
]=]
function LootClient.GetOpenedBag(): any?
	return openedBag
end

--[=[
	Sets `bag` as the currently-open loot target. No-op if `bag` is
	already open. Called by `LootBagClient` on prompt activation.
	@within LootClient
	@param bag any -- A `LootBagClient` instance.
]=]
function LootClient.OpenBag(bag: any)
	if openedBag == bag then
		return
	end
	openedBag = bag
	openedBagChanged:Fire(bag)
end

--[=[
	Clears the open bag. Called by the loot menu's close button, by
	`LootBagClient:Stop` when the active bag goes away, or any other
	external coordinator.

	`bag` is an optional filter — if provided, only closes when the
	current open bag matches. Use this from `LootBagClient:Stop` so a
	stale bag's teardown doesn't clobber a more recent OpenBag.
	@within LootClient
	@param bag any? -- Optional. Only close if this matches the open bag.
]=]
function LootClient.CloseBag(bag: any?)
	if openedBag == nil then
		return
	end
	if bag ~= nil and openedBag ~= bag then
		return
	end
	openedBag = nil
	openedBagChanged:Fire(nil)
end

--[=[
	Claims the item at `index` from the currently-open bag. No-op when
	no bag is open. Dispatches directly to the bag's Comm function
	handle so the call path doesn't bounce through a thin method
	wrapper on `LootBagClient`.

	`targetSlot` is the inventory slot the player dropped the drag onto
	(when claiming via drag); the server tries that slot first and falls
	back to auto-slot placement. Omit for click-to-loot (auto-slot
	directly).
	@within LootClient
	@param index number -- 1-based index into the local player's loot pile.
	@param targetSlot string? -- Optional inventory slot preference.
]=]
function LootClient.ClaimOne(index: number, targetSlot: string?)
	if openedBag == nil then
		return
	end
	openedBag.LootOneFunction(index, targetSlot)
end

--[=[
	Claims every item from the currently-open bag. No-op when no bag
	is open.
	@within LootClient
]=]
function LootClient.ClaimAll()
	if openedBag == nil then
		return
	end
	openedBag.LootAllFunction()
end

return LootClient
