--[=[
	@class HotbarClient
	Client-side interface for the local player's hotbar. Reflects the
	server-driven `Hotbar` Comm property and exposes RPC wrappers for binding
	and activation. Cooldown state is intentionally not duplicated here —
	`AbilityClient` already replicates ability cooldowns, so UI code joins the
	two sources at render time.
]=]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Comm = require(ReplicatedStorage.Packages.Comm)
local Observing = require(ReplicatedStorage.Shared.Observing)
local HotbarTypes = require(ReplicatedStorage.Shared.Types.HotbarTypes)

type Hotbar = HotbarTypes.Hotbar
type HotbarBinding = HotbarTypes.HotbarBinding

local HotbarClient = {}

local hotbarProperty
local setBindingFunction
local clearBindingFunction
local activateFunction

function HotbarClient.Init()
	local clientComm = Comm.ClientComm.new(ReplicatedStorage, false, "Hotbar")
	hotbarProperty = clientComm:GetProperty("Hotbar")
	setBindingFunction = clientComm:GetFunction("SetBinding")
	clearBindingFunction = clientComm:GetFunction("ClearBinding")
	activateFunction = clientComm:GetFunction("Activate")
end

--[=[
	Returns the local player's current hotbar payload.
	@within HotbarClient
	@return Hotbar
]=]
function HotbarClient.Get(): Hotbar
	return hotbarProperty:Get()
end

--[=[
	Observes changes to the local player's hotbar.

	`callback` is called immediately with the current value and again on every
	change. It may return a cleanup function that runs before the next
	invocation and on disconnect.
	@within HotbarClient
	@param callback (hotbar: Hotbar) -> (() -> ())?
	@return () -> () -- Disconnects the observer.
]=]
function HotbarClient.ObserveHotbar(callback: (hotbar: Hotbar) -> (() -> ())?)
	return Observing.observeCommProperty(hotbarProperty, callback)
end

--[=[
	Requests the server to bind `binding` to `slotKey`. The server rejects
	requests targeting the MainHand slot (which is server-managed).
	@within HotbarClient
	@param slotKey string
	@param binding HotbarBinding
	@return (boolean, string) -- ok, message ("" on success).
]=]
function HotbarClient.SetBinding(slotKey: string, binding: HotbarBinding): (boolean, string)
	return setBindingFunction(slotKey, binding)
end

--[=[
	Requests the server to clear `slotKey`'s binding.
	@within HotbarClient
	@param slotKey string
	@return (boolean, string)
]=]
function HotbarClient.ClearBinding(slotKey: string): (boolean, string)
	return clearBindingFunction(slotKey)
end

--[=[
	Requests the server to activate the binding in `slotKey`.
	@within HotbarClient
	@param slotKey string
	@return (boolean, string)
]=]
function HotbarClient.Activate(slotKey: string): (boolean, string)
	return activateFunction(slotKey)
end

return HotbarClient
