# Denizen Behavior Plan

Plan for adding configurable AI to `Denizen` components. Read this end-to-end before starting; it captures *why* certain choices were made, not just *what* to build.

## Context

`Denizen` is the server component for non-player combat-capable entities (cows, imps, NPCs). It already has:

- Health (`GetHealth`/`SetHealth`, satisfies `DamageTarget`).
- Animation API (`AnimationPlay`/`AnimationStop`/`AnimationIsPlaying`).
- Physics-based locomotion via a programmatically-built `ControllerManager` rig (`GroundController` + `AirController` + `ControllerPartSensor` parented to PrimaryPart). Drives via `ControllerManager.MovingDirection` / `FacingDirection`.
- Movement helpers: `MoveTo(point)`, `FaceDirection(dir?)`, `StopMoving()`. Reconciliation lives in `HeartbeatUpdate`.

What's missing: the denizen has no autonomous behavior. We need to give it one.

Requirements informing the design:
- **Neutral and aggressive denizens** must both work.
- **Conditional aggression** (e.g. only when low-HP target is nearby, only at night, only on intruders).
- **Combat behaviors** vary per kind (flee at low HP, use special attacks).
- **Easily configured** — adding a new kind should mostly be data, not code.
- Will eventually have **hundreds of `DenizenKind`s**, but only ~5 distinct behavioral templates.

## Decision: FSM-led hybrid

Top-level finite state machine (legible, debuggable: `denizen.Behavior.CurrentName == "Aggressing"` answers "what is this thing doing?"). Behavior expressed as **reusable, parameterized state implementations** plus **named predicates** for transitions. Defs are pure data referencing implementations by name.

Why not pure Behavior Tree: the high-level mode (idle vs combat vs flee) is conceptually a state and you want to inspect it at a glance. BTs bury the mode in tree traversal.

Why not Utility AI: hard to debug ("why score 0.73 vs 0.71?"), and the modes here are real discrete things, not blends.

Why not GOAP: massive overkill for this scale.

Why not bespoke per-kind code: doesn't reuse across hundreds of kinds.

## Architecture: three layers

1. **State implementations** — generic, parameterizable, live in code. One file per state type (`Wander`, `MeleeAggression`, `Flee`, `ReturnToSpawn`, …).
2. **Predicate implementations** — generic conditions with parameters (`HealthBelow`, `EnemyInRange`, `RecentlyDamaged`, `IsNight`).
3. **Defs** — data-only, references states/predicates by name, supplies config. Lives in `DenizenDefs` (Shared) so client can read non-behavior fields (Name, MaxHealth, Animations).

## File layout

```
src/Server/Behavior/
  Behavior.luau                  -- FSM runner, attached per-denizen
  States/
    Wander.luau
    MeleeAggression.luau
    Flee.luau
    ReturnToSpawn.luau
  Predicates/
    HealthBelow.luau
    HealthAbove.luau
    EnemyInRange.luau
    RecentlyDamaged.luau
    NotRecentlyDamaged.luau

src/Shared/Defs/
  DenizenDefs.luau               -- Behavior config added inline; references by Kind name
```

Note: states and predicates live under `Server/` because they query world state and call server-only helpers (raycasts, damage server, etc.). Defs stay in `Shared/` because the client reads `Name`/`MaxHealth`/`Animations`. The bridge: defs reference states/predicates by string name; the server-only `Behavior.luau` runner resolves names to implementations.

## State implementation pattern

Each state file exports a factory: `(config) -> State`. The returned state has `Enter`/`Update`/`Exit`. `Update` returns the name of the next state, or `nil` to stay.

```lua
-- src/Server/Behavior/States/MeleeAggression.luau
export type Config = {
    AttackRange: number,
    LeashRange: number,
    AttackCooldown: number,
    Ability: string,
}

return function(config: Config)
    return {
        Enter = function(denizen)
            denizen.AttackTimer = 0
        end,
        Update = function(denizen, dt)
            local target = denizen.Target
            if target == nil or isDead(target) then return "Idle" end

            local pos = denizen.Instance:GetPivot().Position
            local distance = (target:GetPivot().Position - pos).Magnitude
            if distance > config.LeashRange then return "Returning" end

            if distance > config.AttackRange then
                denizen:MoveTo(target:GetPivot().Position)
            else
                denizen:StopMoving()
                denizen:FaceDirection((target:GetPivot().Position - pos).Unit)
                denizen.AttackTimer -= dt
                if denizen.AttackTimer <= 0 then
                    Abilities.Use(denizen, config.Ability, target)
                    denizen.AttackTimer = config.AttackCooldown
                end
            end
            return nil  -- stay
        end,
        Exit = function(denizen)
            denizen:StopMoving()
        end,
    }
end
```

## Predicate implementation pattern

Each predicate file exports a function `(denizen, args) -> boolean`.

```lua
-- src/Server/Behavior/Predicates/HealthBelow.luau
return function(denizen, args)
    return denizen.Health / denizen.MaxHealth < args.Fraction
end
```

```lua
-- src/Server/Behavior/Predicates/EnemyInRange.luau
return function(denizen, args)
    local target = findClosestEnemy(denizen, args.Range)
    if target == nil then return false end
    denizen.Target = target  -- side-effect: stash target so Aggressing can use it
    return true
end
```

The "side effect to write `denizen.Target`" pattern is OK but worth a comment: predicates are *typically* pure but a small number stash data for the about-to-fire transition. Either accept this or split into "predicate + on-fire side effect."

## Def shape

```lua
DenizenDefs.Imp = {
    Name = "Imp",
    MaxHealth = 50,
    MoveSpeed = 8,
    Animations = { Idle = "ImpIdle", Run = "ImpRun" },
    Behavior = {
        Initial = "Idle",
        States = {
            Idle = { Kind = "Wander", Radius = 12, PauseRange = { 2, 5 } },
            Aggressing = { Kind = "MeleeAggression", AttackRange = 4, LeashRange = 30,
                           AttackCooldown = 1.2, Ability = "ImpClaw" },
            Fleeing = { Kind = "Flee", Speed = 1.5, Distance = 30 },
            Returning = { Kind = "ReturnToSpawn" },
        },
        Transitions = {
            -- Checked top-to-bottom every tick; first match wins.
            -- `From` omitted = applies regardless of current state.
            { When = { Kind = "HealthBelow", Fraction = 0.25 }, Goto = "Fleeing" },
            { From = "Idle", When = { Kind = "EnemyInRange", Range = 20 }, Goto = "Aggressing" },
            { From = "Fleeing", When = { Kind = "HealthAbove", Fraction = 0.7 }, Goto = "Idle" },
        },
    },
}

DenizenDefs.Cow = {
    Name = "Cow",
    -- ...stats...
    Behavior = {
        Initial = "Idle",
        States = {
            Idle = { Kind = "Wander", Radius = 6 },
            Fleeing = { Kind = "Flee", Speed = 1.8, Distance = 25 },
        },
        Transitions = {
            { When = { Kind = "RecentlyDamaged", Seconds = 5 }, Goto = "Fleeing" },
            { From = "Fleeing", When = { Kind = "NotRecentlyDamaged", Seconds = 5 }, Goto = "Idle" },
        },
    },
}
```

Three-and-many denizens, zero per-kind code. Cow gets neutral behavior by simply *not* having an `Aggressing` state.

## Runner pattern

```lua
-- src/Server/Behavior/Behavior.luau
local STATE_FACTORIES = {
    Wander = require(script.Parent.States.Wander),
    MeleeAggression = require(script.Parent.States.MeleeAggression),
    Flee = require(script.Parent.States.Flee),
    ReturnToSpawn = require(script.Parent.States.ReturnToSpawn),
}
local PREDICATES = {
    HealthBelow = require(script.Parent.Predicates.HealthBelow),
    HealthAbove = require(script.Parent.Predicates.HealthAbove),
    EnemyInRange = require(script.Parent.Predicates.EnemyInRange),
    RecentlyDamaged = require(script.Parent.Predicates.RecentlyDamaged),
    NotRecentlyDamaged = require(script.Parent.Predicates.NotRecentlyDamaged),
}

local Behavior = {}
Behavior.__index = Behavior

function Behavior.new(denizen, behaviorDef)
    local self = setmetatable({}, Behavior)
    self.Denizen = denizen
    self.Transitions = behaviorDef.Transitions
    self.States = {}
    for name, config in behaviorDef.States do
        local factory = STATE_FACTORIES[config.Kind]
        assert(factory ~= nil, `Unknown state kind: {config.Kind}`)
        self.States[name] = factory(config)
    end
    self.CurrentName = behaviorDef.Initial
    local initial = self.States[self.CurrentName]
    if initial.Enter then initial.Enter(denizen) end
    return self
end

function Behavior:Tick(dt)
    -- 1. Global transition check, in priority order.
    for _, t in self.Transitions do
        if (t.From == nil or t.From == self.CurrentName)
           and PREDICATES[t.When.Kind](self.Denizen, t.When)
        then
            self:TransitionTo(t.Goto)
            break
        end
    end

    -- 2. Tick the (possibly newly-set) current state.
    local state = self.States[self.CurrentName]
    local nextName = state.Update(self.Denizen, dt)
    if nextName ~= nil then
        self:TransitionTo(nextName)
    end
end

function Behavior:TransitionTo(nextName)
    if nextName == self.CurrentName then return end
    local current = self.States[self.CurrentName]
    if current.Exit then current.Exit(self.Denizen) end
    self.CurrentName = nextName
    local next_ = self.States[nextName]
    assert(next_ ~= nil, `Transition to unknown state: {nextName}`)
    if next_.Enter then next_.Enter(self.Denizen) end
end

return Behavior
```

## Wiring into the Denizen component

In `Denizen:Construct` (or `Start` — wherever the controller setup happens):

```lua
if self.Def.Behavior ~= nil then
    self.Behavior = Behavior.new(self, self.Def.Behavior)
end
```

In `Denizen:HeartbeatUpdate(dt)`, before the existing movement reconciliation:

```lua
if self.Behavior ~= nil then
    self.Behavior:Tick(dt)
end
```

Order matters: behavior runs first to set `MoveTarget`/`FacingTarget`/etc., then the existing reconciliation in `HeartbeatUpdate` writes those into `ControllerManager.MovingDirection`/`FacingDirection`.

The current debug random-walk loop in `Start` should be removed when wiring real behavior in.

## Open decisions

These weren't pinned down and need a call before/during implementation:

1. **Predicates: named-by-Kind vs inline functions.**
   The plan above uses `When = { Kind = "HealthBelow", Fraction = 0.25 }` (named). Alternative: `When = function(d) return d.Health / d.MaxHealth < 0.25 end` directly in the def. Named is more declarative and inspectable; inline is fewer files. **Recommendation:** named. Lets you log "transition fired because predicate `HealthBelow` returned true."

2. **Where the behavior config lives.**
   Plan above puts it in `DenizenDefs.luau` (Shared). Alternative: split into `DenizenDefs.luau` (Shared, stats only) and `DenizenBehaviorDefs.luau` (Server, FSM stuff). Split keeps the Shared def small and keeps server-only config off the client. Single file is simpler. **Recommendation:** start single, split if behavior config grows large or starts referencing server-only types.

3. **Target selection.**
   Plan assumes `denizen.Target` gets set as a side effect of the `EnemyInRange` predicate. The cleaner design is a separate "perception" layer that updates `denizen.Target` regardless of state, and `EnemyInRange` is a pure read. The shortcut works for now; revisit if multiple states need different targeting rules.

4. **Multi-target / squad coordination.**
   Plan assumes solo brain. If pack tactics matter (two imps flanking), that's a layer above per-denizen — a `Squad` controller that influences members' `Target` and movement. **Defer until needed**; nothing in this design precludes it.

5. **Cooldown bookkeeping for abilities.**
   Plan stashes `denizen.AttackTimer` ad-hoc. If multiple abilities need independent cooldowns, an `Abilities` system on the denizen with a cooldown table is cleaner. **Defer until the second ability lands.**

## Pitfalls / warnings

**The config-grows-into-a-language trap.** Data-driven systems classically die when the config slowly reinvents code: first you need `Or`, then `Add`, then variables, then conditionals. Five years later you've reimplemented Lua, badly, in JSON. **The escape hatch is: when a predicate or state would require config gymnastics, add a new predicate or state file in code instead.** Adding `Predicates/HealthBelowOrPanicked.luau` as a 10-line composite is far better than adding a generic `Or` combinator to the config grammar. Keep the data shallow; reach for code the moment expressions want to grow.

**Yielding in state Update or predicates.** Don't. The runner ticks every heartbeat and assumes synchronous execution. Async work (sounds, VFX, network) is fine but should be `task.spawn`'d off, not awaited inline.

**Predicate side effects.** The `EnemyInRange` predicate stashes the found target on the denizen. Document this clearly; predicates that mutate state are a debugging hazard if they fire and then the transition doesn't happen (because something earlier in the priority list already fired).

**Transition order is a contract.** First-match-wins means later transitions need their predicates to be subsets of earlier ones, or you'll get unreachable transitions. Comment why each transition is in its position; don't reorder casually.

## Suggested implementation order

Build incrementally; each step is independently testable.

1. **Skeleton runner.** Just `Behavior.luau` with empty registries, `new`/`Tick`/`TransitionTo`. Wire into Denizen. Verify it runs without crashing with an empty def.
2. **First state: `Wander`.** Pick a random nearby point, walk to it, pause for a beat, pick another. Reuse the helper logic that's currently in the debug random-walk in `Start`. Imp def gets `Behavior = { Initial = "Idle", States = { Idle = { Kind = "Wander", ... } }, Transitions = {} }`.
3. **First predicate + transition: `RecentlyDamaged` + Cow.** Cow def: wanders, flees if hit. Tests the transition path end-to-end.
4. **Combat states: `MeleeAggression`, `Flee`, `ReturnToSpawn`.** Imp def gets full behavior. Requires the damage pipeline already in place (it is).
5. **Polishing predicates:** `HealthBelow`/`HealthAbove`, `EnemyInRange`. Already partly sketched above.
6. **Remove debug random-walk** from `Denizen:Start`.
7. **One additional behavioral template** to validate reusability — e.g. a `Guard` that aggros only when an intruder enters a radius around its spawn point. New predicate `IsIntruder`, possibly new state `PatrolBetween`.

## Current state of the codebase (when this plan was written)

- `src/Server/Components/Denizen.luau` exists with movement helpers and a debug random-walk in `Start`.
- `src/Shared/Defs/DenizenDefs.luau` has Imp def with `Animations.Idle = "ImpIdle"`, `Animations.Run = "ImpRun"`, no `Behavior` field yet.
- `src/Shared/Defs/AnimationDefs.luau` has `ImpIdle`, `ImpRun`, `ImpAttack` registered.
- `src/Server/Servers/DamageServer.luau` is in place; Denizen satisfies `DamageTarget`. Hook from Denizen as `DamageSource` not yet wired (would live on the abilities system).
- `Workspace.Imp` is tagged `Denizen` with `DenizenKind = "Imp"`.

Smoke-tested: imp wanders via the debug loop. Movement, animations, and physics rig confirmed working.
