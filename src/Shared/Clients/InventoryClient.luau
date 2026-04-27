--[=[
	@class InventoryClient
	Client-side interface for the local player's inventory. Reflects the server-driven `Inventory` Comm property.
]=]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Comm = require(ReplicatedStorage.Packages.Comm)
local Observing = require(ReplicatedStorage.Shared.Observing)
local InventoryTypes = require(ReplicatedStorage.Shared.Types.InventoryTypes)

type Inventory = InventoryTypes.Inventory

local InventoryClient = {}

local inventoryProperty

function InventoryClient.Init()
	local clientComm = Comm.ClientComm.new(ReplicatedStorage, false, "Inventory")
	inventoryProperty = clientComm:GetProperty("Inventory")

	InventoryClient.ObserveInventory(print)
end

--[=[
	Returns the local player's current inventory.
	@within InventoryClient
	@return Inventory
]=]
function InventoryClient.Get(): Inventory
	return inventoryProperty:Get()
end

--[=[
	Observes changes to the local player's inventory.

	`callback` is called immediately with the current value and again on every change.
	It may return a cleanup function that is called before the next invocation and on disconnect.
	@within InventoryClient
	@param callback (inventory: Inventory) -> (() -> ())? -- Handler; may return a cleanup.
	@return () -> () -- Disconnects the observer when called.
]=]
function InventoryClient.ObserveInventory(callback: (inventory: Inventory) -> (() -> ())?)
	return Observing.observeCommProperty(inventoryProperty, callback)
end

return InventoryClient
