--[=[
	@class TeleportClient
	Client-side interface for teleport state. Reflects the server-driven `IsTeleporting` Comm property.
]=]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Comm = require(ReplicatedStorage.Packages.Comm)
local Observing = require(ReplicatedStorage.Shared.Observing)

local TeleportClient = {}

local isTeleportingProperty

function TeleportClient.Init()
	local clientComm = Comm.ClientComm.new(ReplicatedStorage, false, "Teleport")
	isTeleportingProperty = clientComm:GetProperty("IsTeleporting")
end

--[=[
	Returns the current teleporting state for the local player.
	@within TeleportClient
	@return boolean
]=]
function TeleportClient.IsTeleporting(): boolean
	return isTeleportingProperty:Get()
end

--[=[
	Observes changes to the local player's teleporting state.

	`callback` is called immediately with the current value and again on every change.
	It may return a cleanup function that is called before the next invocation and on disconnect.
	@within TeleportClient
	@param callback (isTeleporting: boolean) -> (() -> ())? -- Handler; may return a cleanup.
	@return () -> () -- Disconnects the observer when called.
]=]
function TeleportClient.ObserveIsTeleporting(callback: (isTeleporting: boolean) -> (() -> ())?)
	return Observing.observeCommProperty(isTeleportingProperty, callback)
end

return TeleportClient
