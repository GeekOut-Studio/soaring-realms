local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Comm = require(ReplicatedStorage.Packages.Comm)
local Observing = require(ReplicatedStorage.Shared.Observing)

local TeleportClient = {}

local isTeleporting

function TeleportClient.Init()
	local clientComm = Comm.ClientComm.new(ReplicatedStorage, false, "Teleport")
	isTeleporting = clientComm:GetProperty("IsTeleporting")
end

function TeleportClient.IsTeleporting(): boolean
	return isTeleporting:Get()
end

function TeleportClient.ObserveIsTeleporting(callback: (isTeleporting: boolean) -> (() -> ())?)
	return Observing.observeCommProperty(isTeleporting, callback)
end

return TeleportClient
