# Ability System — Handoff Plan

This document is a self-contained briefing for picking up work on the ability
system from another workstation. It captures **what exists**, **why we made the
decisions we made** (so they don't get re-litigated), and **what's left to do**.

Read CLAUDE.md first for codebase-wide conventions; this doc lives one level up
from those rules and assumes them.

---

## What an "ability" is, in this codebase

An ability is the unit of player- (and eventually denizen-) initiated action: a
basic weapon swing, a learned skill, a craftable item placement. Each ability is
a static **def** that describes what it needs (Requirements, Costs, Cooldown)
and how to run it (Handler + Config). The runtime lives in the matching
`Server/Abilities/<Handler>.luau` module.

Three concepts are separated deliberately:

1. **Ability** — a definition. Identified by a stable string `Kind`. Has no
   opinion about who triggers it or how.
2. **Source** — the thing that grants the ability. Currently only equipment
   (`ItemDef.PrimaryAbility`). Future: skills, quests, class.
3. **Binding** — input → ability mapping. Today: M1 fires the equipped
   main-hand item's `PrimaryAbility`. Future: a hotbar layer maps user-chosen
   bindings to abilities exposed by any active source.

---

## Files in the system

### Types and shared logic (both realms)

- [`src/Shared/Types/AbilityTypes.luau`](src/Shared/Types/AbilityTypes.luau) —
  `AbilityDef` interface (`Kind`, `Handler`, `Config`, `Costs`, `Cooldown`,
  `CooldownGroup`, `Requirements`) + `Costs` interface. Intentionally has no
  `AbilityKind` string-literal union — the codebase convention is just `string`
  for kind fields (would-be-keyof, but Luau doesn't have that yet).
- [`src/Shared/AbilityShared.luau`](src/Shared/AbilityShared.luau) —
  pure-function validators called by both client and server.
  - `GetCooldownGroup(def)` — defaults to `def.Kind` if no `CooldownGroup`.
  - `IsAffordableAndReady(snapshot, def)` — cooldown + costs check. Errors are
    informative (e.g. `"Missing OreCopper: have 1, need 3."`). Requirements are
    checked separately by the existing `Requirements` system.
- [`src/Shared/Defs/AbilityDefs.luau`](src/Shared/Defs/AbilityDefs.luau) —
  data only. Currently one entry: `MeleeAttack`.

### Server runtime

- [`src/Server/Servers/AbilityServer.luau`](src/Server/Servers/AbilityServer.luau)
  — pipeline: requirements → affordability → cost deduction → handler dispatch
  → `OnWillCooldown` → set cooldown → replicate. In-memory
  `cooldownsByPlayer` table; replicates via `Cooldowns` Comm property
  (`SetFor` per player). Comm-bound `Activate(abilityKind) -> (success, reason)`.
- [`src/Server/Abilities/SingleTargetMelee.luau`](src/Server/Abilities/SingleTargetMelee.luau)
  — first handler. Returns a table:
  ```lua
  return {
      Activate = function(activator, config) ... end,
      OnWillCooldown = function(baseCooldown, activator, config) ... end?,
  }
  ```
  Reads `activator:GetCombatStats("MainHandMelee")` for power/range/damage and,
  via `OnWillCooldown`, the `Interval`. Plays animation, picks closest hostile in
  range from the activator's `CombatSession`, applies damage via `DamageServer`.

### Client

- [`src/Shared/Clients/AbilityClient.luau`](src/Shared/Clients/AbilityClient.luau)
  — owns the only reference to the server-side `Ability` Comm on the client.
  Exposes `Activate(kind)`, `GetCooldownExpiresAt(group)`,
  `GetCooldownRemaining(group)`. Mirrors the server's `Cooldowns` table via
  Comm property. Initialized in `ClientInitializer.client.luau`.
- [`src/Shared/Components/OutworlderClient.luau`](src/Shared/Components/OutworlderClient.luau)
  — local-player input. M1 → `TryFirePrimaryAbility` looks up the equipped
  `MainHandMelee`'s `PrimaryAbility` and calls `AbilityClient.Activate`. Does
  *not* hold an Ability comm directly — that lives in `AbilityClient` only.

### Touched but not authored by this system

- [`src/Shared/Defs/ItemDefs.luau`](src/Shared/Defs/ItemDefs.luau) — added
  `PrimaryAbility: string?` field on `ItemDef`. `SwordCopper.PrimaryAbility =
  "MeleeAttack"`.
- [`src/Server/Components/Outworlder.luau`](src/Server/Components/Outworlder.luau)
  — added `GetCombatStats(slot)` returning the equipped item's `CombatStats`,
  read through `EquipmentServer.GetEquipment` (the deeply-frozen, allocation-free
  authoritative source — *not* the per-character `EquipmentProperty`, which is
  for remote clients to render gear). Removed the placeholder
  `TickCombatSwing` auto-attack and its helpers.
- [`src/Shared/Requirements/HasEquipmentWithStats.luau`](src/Shared/Requirements/HasEquipmentWithStats.luau)
  — added `Combat = "weapon"` to `LabelsByClass` so the failure message reads
  "You need to equip a weapon."

### Renamed during execution (consequence of the convention work)

`Kind` is now reserved exclusively for **identity** (matching `ItemKind`,
`OreNodeKind`, `DenizenKind`). Damage's *classification* moved to
`Type`/`DamageType`:

- `DamageTypes`: `type DamageKind` → `type DamageType`; `Damage.Kind` field →
  `Damage.Type`; `Kinds`/`KindSet` props → `Types`/`TypeSet`.
- `ItemStatsTypes.CombatStats.DamageKind` → `DamageType`.
- `MeleeAggression.AttackKind` → `AttackType`, `Kind = config.AttackKind` →
  `Type = config.AttackType`.
- All call sites (`DamageServer.Damage({...})`) now use `Type = ...`.

Note: `type` is a reserved word in Luau — fine as a *field* name, but always
use `damageType` (camelCase) for locals/parameters; never shadow it.

---

## Design decisions, recorded

These were debated and settled — don't undo without a real reason.

1. **Basic attack IS an ability.** The "two parallel systems" cost of treating
   it as separate (animation, cooldown, validation, replication, input binding)
   exceeds the cost of unification. Permissive defaults (cooldown = swing time,
   cost = 0) aren't infrastructure overhead — just zero values in data.

2. **Kind + Handler split.** Mirrors the Denizen Behavior pattern: a small set
   of *handler* modules implement structural behaviors (`SingleTargetMelee`,
   future `PlaceInstance`, `PointAoE`, etc.); many *defs* compose them with
   different config. Adding a handler is rare/infrastructure work; adding a def
   is frequent/content work. **Code does NOT live in defs files.**

3. **Handler is server-only.** Handlers reach into `DamageServer`,
   `InventoryServer`, etc. Migrating them to shared territory would dramatically
   complicate every handler. The escape hatch for client-side prediction is
   `AbilityShared` for validation + the replicated `Cooldowns` property for UI.

4. **Handler module returns a table** — `{Activate, OnWillCooldown?}`. Optional
   `OnWillCooldown(baseCooldown, activator, config) -> number` lets a handler
   override the def's base cooldown using activator state (e.g. weapon
   `Interval`). Most handlers will omit it. Naming mirrors
   `OnWillDealDamage`/`OnWillTakeDamage`.

5. **`OnWillCooldown` runs AFTER `handler.Activate`.** This way the handler is
   free to mutate activator state during its run and have those changes
   reflected in the cooldown. Re-entry between Activate's start and the cooldown
   set is impossible because no handler yields. (If a future handler must yield,
   this contract needs revisiting — see Watch-items.)

6. **Cooldown groups, not per-ability cooldowns by default.** `def.CooldownGroup`
   buckets abilities that should share a single timer per player. Default
   (when unset) is `def.Kind` itself. `MeleeAttack.CooldownGroup =
   "MainHandMelee"` so a future weapon swap doesn't reset the swing rhythm.

7. **One generic `MeleeAttack` ability shared across melee weapons.** Not
   per-weapon defs. The wielder's `MainHandMelee` `CombatStats` is the source
   of variation (Power, Range, DamageType, Interval). Requirement is
   `HasEquipmentWithStats("MainHandMelee", "Combat")`. New melee weapons just
   set `PrimaryAbility = "MeleeAttack"` and define their `Stats.Combat`.

8. **`Cooldowns` replicates via Comm property, not stuffed into another
   module's comm.** `AbilityServer` owns its `Ability` ServerComm and a
   `Cooldowns` per-player property; `AbilityClient` is the sole client-side
   consumer. **`OutworlderClient` does not hold an Ability comm reference.**

9. **Validation surface duality.** `AbilityShared.IsAffordableAndReady` is the
   shared validator for cooldown + costs. Client UI calls it for affordance
   (greyed-out icons, cooldown rings); server calls it as the auth gate. Same
   function, same behavior. Requirements are checked separately by the existing
   `Requirements` system (which already has Server/Client wrappers).

10. **No Targeting / ActivationContext shapes nailed down yet.** The melee
    handler picks its own target server-side from the activator's
    `CombatSession`. This works for melee; it punts on AoE-targeted, ground-
    placed, etc. The second handler will force these decisions. Don't pre-design
    the union.

11. **Handler interface uses `(any, any)` for activator and config.** Codebase
    convention (see Denizen behavior states for the same pattern). Errors are
    runtime, not compile-time.

12. **`def.Cooldown` stays required even when `OnWillCooldown` always overrides
    it.** It's the documented base / fallback. Slight reader-confusion when both
    are present but the type system would otherwise need an awkward optional.

---

## What works today

End-to-end playable: equip Copper Sword, click M1, server validates → animation
plays → damage applies to closest hostile in `CombatSession` within range →
cooldown gates re-clicks at the weapon's `Interval`. Cooldowns replicate to the
local player.

---

## Remaining work, in priority order

### 1. Playtest the post-review changes (very brief)

The most recent changes — handler table form (`{Activate, OnWillCooldown}`),
cooldown replication via Comm, `OnWillCooldown` moved to *after* Activate,
Outworlder reading via `EquipmentServer.GetEquipment` instead of the per-character
property — were made after the last "It works fine!" check. Smoke-test in Studio
before building more on top.

### 2. Second handler — PlaceInstance for a Survivalism campfire

Picked because it exercises the most parts of the abstraction that haven't been
touched yet:

- **Item costs** (consume N logs).
- **Place-instance targeting** (ground reticle / target point input).
- **Non-combat path** (proves the system isn't accidentally combat-coupled).
- **Activation flow that doesn't have a `CombatSession` to read from.**

Likely shape:

```lua
-- src/Server/Abilities/PlaceInstance.luau
return {
    Activate = function(activator, config, context)
        -- context.GroundPoint? cast a ray, validate placement, instantiate
        -- a new copy of the configured prefab, parent to Workspace.
    end,
}
```

What this forces decisions on:

- **Targeting / ActivationContext**: server needs the ground point. Either
  client passes it in `Activate(kind, context)` (server validates), or the
  server raycasts from activator forward (less flexible). Likely the former —
  client passes the input, server validates. Means `AbilityServer.Activate` and
  the Comm signature grow a `context: any` parameter, validated per-handler.
- **Hotbar reachability for non-combat**: the campfire ability has no
  `PrimaryAbility` slot to live in. The hotbar binding layer is what reaches it.
  A first crude version: a Cmdr command or context menu entry that calls
  `AbilityClient.Activate("MakeCampfire", {GroundPoint = ...})` will prove the
  end-to-end without needing a hotbar UI yet.

### 3. Hotbar binding layer + UI affordance

Player-facing feature. A small data structure mapping hotkey → ability kind,
plus a HUD row of icons that read cooldowns from `AbilityClient` (cooldown ring
based on `GetCooldownRemaining(group) / def.Cooldown` — note: with
`OnWillCooldown`, the divisor is the *current* cooldown duration, which the
client doesn't know directly; will likely need to also replicate the most-recent
applied duration alongside `expiresAt`, or just have the client snapshot
`expiresAt` at activation time).

A natural extension: `AbilityClient.ObserveCooldowns(callback)` that wraps
`Observing.observeCommProperty` so UI doesn't poll on heartbeat.

### 4. Auto-attack opt-in layer

User-toggled. While in a `CombatSession` with a valid target, auto-fire the
bound primary ability on cooldown. Lives on top of the ability system, doesn't
touch its insides. Probably a small client-side controller component that calls
`AbilityClient.Activate(...)` when `GetCooldownRemaining(group) <= 0` and the
player has the auto-attack toggle on.

### 5. Denizen migration to abilities

Today denizens use `MeleeAggression` state, which has its own swing+damage
loop. Eventually denizens activate abilities through the same pipeline. Two
paths converge at the Combatant interface — but denizens don't have an
Equipment system, so `GetCombatStats` would need to project their per-def
combat stats instead. Either a parameterized handler (config-driven stat
source: `EquipmentSlot` vs `DenizenDef`), or a separate handler family for NPCs.

### 6. Watch-items (deferred, not blocking)

- `pickClosestHostile` uses 3D `.Magnitude` for range. Same axis-mismatch family
  as the denizen behavior cleanup, but melee-attack range was deliberately kept
  3D (hitbox semantics). Tagged "fine for now" — revisit if vertical-stealth
  becomes a real concern.
- `Cooldowns` Comm property is untyped at the wire boundary (`{}` default).
  Client casts to `{[string]: number}`. Standard Comm caveat.
- `SingleTargetMelee` hardcodes `"MainHandMelee"` rather than making the slot
  config-driven. An off-hand attack ability would force this open.
- `MeleeAttack.Cooldown = 1.0` is dead config since `OnWillCooldown` always
  wins for that handler. Reader-confusion only.
- True cross-store atomicity for cost deduction (Stamina lives outside
  `DataServer`) — currently the affordability check + no-yields invariant
  guarantees both deductions succeed, but it's not bulletproof if Stamina ever
  moves into `DataServer` or a yield gets introduced.

---

## Conventions to follow

- **`Kind`** = identity (per CLAUDE.md). Never use it for classification.
  Use `Type` (or domain-specific noun) instead.
- **Defs are data, runtime is code.** Don't put functions in def files.
- **Server-side handler modules.** Don't migrate to shared.
- **Validation in shared, runtime in server.** Cooldown/costs check goes in
  `AbilityShared`. Effect goes in the handler.
- **Camel-case locals that would shadow reserved words.** `damageType`, not
  `type`. `combatStats`, not `stats`. Don't shadow globals.
- **Run `./scripts/check.sh <files>` after every Luau change.** Don't invoke
  stylua/luau-lsp/moonwave-extractor directly.
- **Moonwave docs:** sub-table members get `@function <SubTable>.<Name>` plus
  `@within <ParentClass>`; the sub-table itself stays a plain Lua table.
- **Cylinder range checks** (`Targeting.WithinCylinder` under
  `Server/Behavior/`) are the convention for "denizen can't navigate Y" range
  predicates; not currently used in ability code, but the same module is
  available if a future ability handler needs it.

---

## Quick orientation if you're a new Claude

1. Read this doc.
2. Read [`AbilityServer.luau`](src/Server/Servers/AbilityServer.luau) end to
   end — it's the spine.
3. Read [`SingleTargetMelee.luau`](src/Server/Abilities/SingleTargetMelee.luau)
   — it's small and shows the handler shape.
4. Read [`AbilityShared.luau`](src/Shared/AbilityShared.luau) — the
   shared validator.
5. Skim [`AbilityClient.luau`](src/Shared/Clients/AbilityClient.luau) and
   `OutworlderClient.luau`'s `TryFirePrimaryAbility` — the client wiring.
6. Note CLAUDE.md and the rules around naming, requires, and documentation.

When in doubt about a design choice, check the "Design decisions, recorded"
section above before re-deciding. Most things were the result of explicit
conversation about trade-offs — re-litigating them will cost you time.
