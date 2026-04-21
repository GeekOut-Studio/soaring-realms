local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Comm = require(ReplicatedStorage.Packages.Comm)
local Observing = require(ReplicatedStorage.Shared.Observing)

local TeleportClient = {}

local isTeleportingProperty

function TeleportClient.Init()
	local clientComm = Comm.ClientComm.new(ReplicatedStorage, false, "Teleport")
	isTeleportingProperty = clientComm:GetProperty("IsTeleporting")
end

function TeleportClient.IsTeleporting(): boolean
	return isTeleportingProperty:Get()
end

function TeleportClient.ObserveIsTeleporting(callback: (isTeleporting: boolean) -> (() -> ())?)
	return Observing.observeCommProperty(isTeleportingProperty, callback)
end

return TeleportClient
