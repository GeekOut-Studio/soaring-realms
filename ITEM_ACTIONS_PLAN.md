# Item Action System — Plan

Deferred refactor following the hotbar work. Goal: stop co-owning the "what
can be done with an item" concept across `HotbarTypes`, `HotbarServer`,
`Inventory.luau`, and `Hotbar.luau`. Adding a new action kind (Use, Consume,
MagicActivate, …) should be a single registry entry.

## Current state of the world

`ItemAction` lives in `HotbarTypes.luau` as a discriminated union:

```luau
export type ItemAction =
      { Kind: "Equip", Slot: EquipmentSlot }
    | { Kind: "Drop" }
```

Action knowledge is duplicated in four places:

1. `HotbarTypes.HotbarBinding`'s `Item` variant references the union.
2. `HotbarServer.activateItemBinding` hardcodes `Equip`/`Drop` dispatch
   against `EquipmentServer.Equip` / `InventoryServer.RemoveItem`.
3. `Inventory.luau::buildActions` constructs the inventory context-menu
   actions inline (Equip-per-slot + Drop), each with its own `OnSelect`
   calling client RPCs directly.
4. `Hotbar.luau::buildBindActionsForItem` does the same iteration but with
   `OnSelect`s that call `HotbarClient.SetBinding`.

`validateBinding` in `HotbarServer` carries the schema as a hand-rolled
`t.union`.

## Target architecture

### `Shared/ItemActionsShared.luau` (new)

Owns the action concept's types, registry of structural metadata, and the
composed `t` validator.

```luau
export type ItemAction =
      { Kind: "Equip", Slot: EquipmentSlot }
    | { Kind: "Drop" }
    -- New kinds added here.

export type ItemActionEntry = {
    Check: any,                                       -- t-validator for the action's payload
    Expand: (item: Item) -> { ItemAction },           -- 0..N concrete actions of this kind for this item
    Label: (item: Item, action: ItemAction) -> string,
    Destructive: boolean?,                            -- threads through ContextMenuActions.FindClickAction
}

ItemActionsShared.Kinds = table.freeze({ "Equip", "Drop" })  -- canonical display order
ItemActionsShared.Entries = table.freeze({
    Equip = {
        Check = t.strictInterface({
            Kind = t.literal("Equip"),
            Slot = t.keyOf(EquipmentTypes.SlotSet),
        }),
        Expand = function(item)
            local def = ItemDefs[item.Kind]
            if def == nil or def.EquipSlots == nil then return {} end
            local out = {}
            for _, slot in def.EquipSlots do
                table.insert(out, { Kind = "Equip", Slot = slot })
            end
            return out
        end,
        Label = function(_item, action)
            local label = EquipmentTypes.SlotLabels[action.Slot] or action.Slot
            return `Equip {label}`
        end,
    },
    Drop = {
        Check = t.strictInterface({ Kind = t.literal("Drop") }),
        Expand = function(_item) return { { Kind = "Drop" } } end,
        Label = function() return "Drop" end,
        Destructive = true,
    },
})

-- Composed from each entry's Check so adding a kind doesn't require editing
-- HotbarServer's validator.
ItemActionsShared.Check = t.union(
    -- iterate Entries values and unpack their Check fields
)
```

### `Server/Servers/ItemActionsServer.luau` (new)

Server-side execution registry plus a single Comm endpoint that runs an
action against an inventory slot.

```luau
type Executor = (player: Player, inventorySlot: string, action: ItemAction) -> (boolean, string?)

local EXECUTORS: { [string]: Executor } = {
    Equip = function(player, slot, action)
        local ok = EquipmentServer.Equip(player, slot, action.Slot)
        return ok, if ok then nil else "Equip failed."
    end,
    Drop = function(player, slot, _action)
        local ok = InventoryServer.RemoveItem(player, slot)
        return ok, if ok then nil else "Drop failed."
    end,
}

function ItemActionsServer.Run(player, inventorySlot, action)
    -- validate via ItemActionsShared.Check, then dispatch via EXECUTORS[action.Kind]
end

function ItemActionsServer.Init()
    local serverComm = Comm.ServerComm.new(ReplicatedStorage, "ItemActions")
    serverComm:BindFunction("Run", function(player, slot, action)
        if not t.string(slot) then return false, "Bad slot." end
        local ok, message = ItemActionsServer.Run(player, slot, action)
        return ok, message or ""
    end)
end
```

`Run` is also callable as a module function so `HotbarServer.activateItemBinding`
can dispatch internally without going through Comm.

### `Shared/Clients/ItemActionsClient.luau` (new)

Thin RPC wrapper around the `Run` Comm endpoint. Used by the inventory
context menu. The hotbar doesn't need it — hotbar activation routes through
`HotbarClient.Activate` → server-side `ItemActionsServer.Run`.

```luau
function ItemActionsClient.Run(inventorySlot, action)
    return runFunction(inventorySlot, action)
end
```

## Migration steps

1. **Create `ItemActionsShared.luau`** with the type, registry entries for
   `Equip` and `Drop` mirroring today's inline logic, and the composed `Check`.
2. **Create `ItemActionsServer.luau`** with `EXECUTORS` + `Run` + `Init`.
3. **Create `ItemActionsClient.luau`** with `Init` and `Run`.
4. **`HotbarTypes.luau`**: replace local `ItemAction` with
   `ItemActionsShared.ItemAction` (or re-export). `HotbarBinding`'s `Item`
   variant references the Shared type.
5. **`HotbarServer.luau`**:
   - Remove the inline `Equip`/`Drop` branches in `activateItemBinding` —
     delegate to `ItemActionsServer.Run(player, slot, binding.Action)`.
   - Change `validateBinding`'s `Item` variant to `Action = ItemActionsShared.Check`.
6. **`Inventory.luau::InventorySlot::buildActions`**: replace the inline
   Equip/Drop construction with one registry walk that calls
   `ItemActionsClient.Run(slotKey, action)` in each `OnSelect`.
7. **`Hotbar.luau::buildBindActionsForItem`**: same registry walk, but each
   `OnSelect` calls `HotbarClient.SetBinding(slotKey, {Kind="Item", ...})`
   with the action.
8. **Initializers**: add `ItemActionsServer.Init()` to `ServerInitializer`
   (after `InventoryServer`/`EquipmentServer`, before `HotbarServer`) and
   `ItemActionsClient.Init()` to `ClientInitializer`.

## Cost of adding a new action kind after the refactor (e.g. `Consume`)

1. Add variant to `ItemActionsShared.ItemAction`.
2. Add entry to `ItemActionsShared.Entries` (`Check`, `Expand`, `Label`,
   `Destructive`).
3. Add executor to `ItemActionsServer.EXECUTORS`.

That's it. Hotbar dispatch, inventory UI, hotbar bind-picker, and the binding
validator all pick the new kind up through the registry walk.

## Open questions to decide before starting

1. **Module location**: `ItemActionsShared` at `src/Shared/` (alongside
   `InventoryShared`, `AbilityShared`)? Or under `src/Shared/Defs/` if we
   treat the registry as data? Lean toward `src/Shared/ItemActionsShared.luau`
   to match the `*Shared` convention for "pure functions + shared metadata."

2. **Unified Comm-driven path for inventory click-actions** (the question
   raised earlier): today inventory's context menu calls
   `EquipmentClient.Equip` / `InventoryClient.DropItem` directly. The plan
   above migrates those to `ItemActionsClient.Run` so there's a single
   wire format for "run an action on a stack." Confirm this is the
   intended direction before doing the inventory refactor — the
   alternative is to keep the existing RPCs and only have the hotbar
   delegate to `ItemActionsServer.Run` module-internally.

3. **What about server-only callers?** E.g., a future quest reward that
   auto-equips. Those would call `ItemActionsServer.Run(player, slot, ...)`
   directly (not via Comm). The design supports this — `Run` is exposed as
   a module function in addition to being bound to Comm.

## Things this refactor does NOT change

- The hotbar's binding shape, persistence layout, or replication semantics.
- `AbilityKind` bindings — those don't go through `ItemActions`.
- Drag-drop UX or the drop-target hover system.
- Cooldown handling (still owned by `AbilityServer.Cooldowns`).

## Related future work (out of scope for this refactor)

- Pulling `ItemAction` definitions into per-item-def declarations (some
  items might want custom one-off actions). The registry pattern accommodates
  this — a `Custom` kind could read its dispatch from the `ItemDef`. Defer
  until there's a concrete need.
- Server-side cooldowns on `Item` actions. Currently item activations have
  no cooldown. If we add one, it likely lives on the executor or as a
  per-action-kind field on the registry entry.
