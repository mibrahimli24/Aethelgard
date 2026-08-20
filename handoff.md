# Aethelgard — Handoff Notes

Last updated: 2026-08-20 (session 3 — graphics/story/dialogue depth pass, on top of the "all 5 classes combat-viable + crafting + autosave fix" session before it).

## What exists and works (playtested)

The original vertical slice (see `C:\Users\user\.claude\plans\validated-seeking-puffin.md` for the original scoping/plan) is complete and confirmed working by the user:
- Full "Whispers in the Glade" quest chain (8 stages, Garrick → wolves → Garrick → Mira → camp reveal → clear camp → Skar boss → complete).
- Story-gated dialogue via the mocked `GameMaster` "LLM" (rapport + keyword + quest-flag gating).
- Swordsman fully playable, HP/hunger survival loop, class-switch UI, HUD, save/load shape.

The "session 2" work (all 5 classes combat-viable, crafting loop, autosave fix — see the section below this one) was also reported working by the user ("it worked nicely, I defeated the boss and logged out").

## What was added in session 3 (this session — not yet playtested, Godot isn't installed here)

Prompted by: "improve graphics, story, and all other aspects; NPCs don't have much to say after finishing the quest with a different role; give NPCs more freedom to speak; gradually implement other phases beyond mocked phase 1."

1. **Fixed the "NPCs don't have much to say" bug** (root cause, not a band-aid): `GameMaster._try_reveal_secret()` used to replay the *exact same* secret-reveal monologue verbatim every time a player re-mentioned the trigger keywords, and casual chat only had 3 topics with one canned line each. Fixed in `autoloads/GameMaster.gd`:
   - Added an already-revealed check: once an NPC's `reveal_story_flag` is set, repeat mentions now route to `_already_revealed_response()`, which rotates through a bank of shorter `follow_up_lines` (via `_follow_up_index`, incrementing not random, so it reads as evolving commentary rather than a shuffle).
   - Expanded casual topics from 3 to 8 (`weather`, `crafting`, `life`, `quest_hint`, `village`, `opinion_of_player`, `rumor`, `aftermath`) and converted every `casual_keywords` entry from a single string to an array of variants, picked randomly via `_pick_variant()`.
   - Expanded `lore_pool` from 5 to 12 entries.

2. **Fixed the "different role" reward bug**: the main quest's final-stage reward hardcoded `"class": "swordsman"` in `data/quests.json`, so finishing the boss fight as any other class still only granted Swordsman EXP/gear. Removed that hardcode so `GameState._apply_rewards()`'s existing `active_class` default applies correctly regardless of which class is active when the quest completes.

3. **New post-quest content ("Rebuilding Era")** — closes the "nothing to do/say after the quest ends" gap directly:
   - `GameState.game_phase` (existed before, but nothing ever set it) now actually transitions `"Story_Mode" → "Rebuilding_Era"` when the main quest's final stage completes, via a new data-driven `triggers_game_phase` field on quest stages.
   - New second quest, **"Rebuilding Glenbrook"** (`data/quests.json`), auto-unlocks on that phase transition (`requires_game_phase` gate) and introduces a new NPC, **Old Ferris** (Glenbrook's blacksmith, `data/npcs.json` + a new instance in `World.tscn`). Turn in the `bloodstone_shard_fragment` trophy (previously an inert item) for a **new tier-2 equipment recipe for whichever class is currently active** (`unlock_recipe_for_active_class` reward type — dynamically resolved, so this doesn't reintroduce the Swordsman-only bug).
   - `data/classes.json` — added `<class>_tier2` recipes for all 5 classes, so every class now has a real gear-upgrade path (previously flagged as a gap in this file's "Suggested next steps").
   - Mira and Garrick both gained `epilogue_greeting` / `epilogue_follow_up_lines` / `epilogue_casual_keywords` so their dialogue actually reads differently once the world has moved into the Rebuilding Era, plus a 4-entry `epilogue_lore_pool` rolled preferentially in that phase.
   - **Architecture change**: `GameState` went from a single hardcoded quest (`quest_def`) to a proper multi-quest system (`quest_defs: Dictionary`, keyed by `quest_id`; every quest-related function is now `qid`-parameterized: `get_current_stage(qid)`, `force_advance_if_at_stage(qid, ...)`, etc.). `data/quests.json`'s top-level shape changed from a single quest object to `{"quests": [...]}` — this was a breaking shape change, all readers were updated. New `GameState.get_display_objective()` centralizes which quest's objective the HUD shows (whichever of the two quests is currently incomplete).

4. **Phase 2 (real LLM) seam, documented but not implemented** (no API key exists, so this is scaffolding only): `autoloads/GameMaster.gd` now has a `USE_REAL_API := false` constant and a top-of-file "PHASING NOTE" doc comment spelling out exactly what a real Anthropic API integration would replace (only the body of `process_dialogue()`) and what it must keep returning (the same `{dialogue, npc_mood, generated_lore_snippet, game_actions[]}` shape) so that swap-in is additive later, not a rewrite. This directly addresses "gradually implement other phases" without fabricating network/API code that can't be tested or authenticated here.

5. **Graphics polish pass** (still all `Polygon2D` primitives — no external art/sprites added, that's a bigger undertaking flagged in next steps below):
   - `scenes/World.tscn` — added a warm `CanvasModulate` atmosphere tint; decorative non-interactive props (dirt path strip, 2 rocks, 3 bushes) scattered around Glenbrook Hollow/Old Barrow Ridge; two torch-glow `Polygon2D` accents on `CampMarker`.
   - `scenes/NPC.gd` / `NPC.tscn` — added an `@export var body_color: Color`, applied to the NPC's `Polygon2D` in `_ready()`. Mira, Garrick, and the new Old Ferris each get a distinct color in `World.tscn` instead of sharing one hardcoded tan.
   - `scenes/Player.gd` / `Player.tscn` — added a small triangular `FacingIndicator` `Polygon2D` that tracks the player's `_facing` vector every physics frame (rotation + offset), so the player's aim direction (relevant for ranged classes) is visible on-screen. Added a white hit-flash tween on `take_damage()`.
   - `scenes/Enemy.gd` — added the same hit-flash pattern (flash to white, tween back to the enemy's base polygon color over 0.18s) on `take_damage()`, and a `_spawn_death_burst()` that builds a one-shot `CPUParticles2D` in code (no new scene file needed) on `_die()`, colored to match the enemy, then self-frees after its lifetime. `Boss.gd` inherits both for free since it extends `Enemy.gd` and has its own `$Polygon2D`.

### Known incomplete/untested risk in this session's work
- **Nothing in this session has been opened in the Godot editor.** Godot is still not installed on this machine. All of the above is unverified by actual execution — the previous session's disclosed risks apply doubly now given the larger surface area touched (especially the `quests.json` shape change and the qid-parameterized `GameState` API — a typo in any call site would be a hard crash, not a silent bug).
- Double-check `data/npcs.json`'s new fields (`follow_up_lines`, `epilogue_*`, array-valued `casual_keywords`) parsed correctly — this file was fully rewritten this session.
- `Ferris`'s spawn position in `World.tscn` (420, 480) was chosen to sit near the Hollow without obviously overlapping other NPCs/props, but wasn't visually verified.

## What was added in session 2 (playtested/confirmed working by the user)

1. **All 5 classes are now combat-viable**, not just Swordsman:
   - `data/classes.json` — added a `"combat"` block per class (`attack_type`, `attack_damage`, `attack_cooldown`, plus `projectile_speed`/`projectile_range`/`projectile_color` for ranged, or `crit_chance`/`crit_multiplier` for Rogue). `content_complete` flipped to `true` for all 5 (flag is data-only, nothing reads it yet).
   - `scenes/Player.gd` — refactored `_perform_attack()` to branch on `GameState.get_active_combat_stats()` instead of hardcoded constants. Tracks a `_facing` vector from the last nonzero movement input, used to aim ranged attacks.
   - `scenes/Projectile.gd` / `Projectile.tscn` (new) — simple Area2D that flies in a straight line, damages the first enemy body it touches (`collision_mask = 2`, matching the Enemy layer), despawns past `max_range`. Spawned via `PROJECTILE_SCENE.instantiate()` and added to `get_tree().current_scene` (i.e. World) so its transform isn't parented to the player.
   - Bowman/Alchemist/Magic User = ranged (arrow/flask/bolt, differentiated only by damage/speed/range/color right now — no distinct sprites). Rogue = fast melee with a crit chance. Swordsman unchanged.

2. **Equipment crafting loop closed**:
   - `data/classes.json` — added a top-level `"recipes"` map: `recipe_id -> {class_id, tier_index}`. Currently only `"iron_tier_swordsman_armor"` (the quest's stage-7 reward) is defined.
   - `autoloads/GameState.gd` — added `recipe_defs` (loaded in `_ready()`), `get_active_combat_stats()`, and `craft_equipment(recipe_id)` (checks `unlocked_recipes`, applies the recipe's `equipped_tier_index` directly — no raw-material cost in this slice, the quest-reward gate stands in for that).
   - `scenes/UI/InventoryUI.gd` / `InventoryUI.tscn` (new) — toggled with the **I** key (new `toggle_inventory` input action in `project.godot`, physical keycode 73). Lists carried items and any unlocked recipes as buttons; pressing one calls `craft_equipment()` and refreshes.
   - Wired into `scenes/World.tscn` as an 8th ext_resource / node instance alongside HUD/DialogueUI/ClassSwitchUI.

3. **Fixed a real persistence bug**: `GameState.save_to_disk()` existed but was **never called anywhere** — quitting the game silently discarded all progress (the user's "I logged out" moment would not have actually persisted anything). Fixed in `autoloads/GameState.gd`:
   - Added a 20-second autosave `Timer` (created in code in `_ready()`, no scene file needed since `GameState` is a script-only autoload).
   - Added `_notification(NOTIFICATION_WM_CLOSE_REQUEST)` to save-then-quit when the window is closed.
   - **This has not been tested.** Please verify: play a bit, close the window (X button), relaunch, and confirm progress (level, quest stage, story flags) survived. If the window-close path doesn't fire the notification reliably in your Godot version, an alternative is hooking `get_tree().auto_accept_quit` or a manual "Save & Quit" menu item.

## Suggested next steps

Roughly in priority order:
1. **Verify everything in session 3 actually runs** — this is the most important next step. Open the project, and specifically watch for: the `quests.json` shape change (make sure both quests load), the boss fight → Rebuilding Era phase transition actually firing after the final quest stage, Old Ferris's dialogue hooks (`meet_ferris` → `bring_shard` → turn in the shard fragment → recipe unlock for whatever class is active), the new casual-topic variety not silently falling back to the "can't say I have much to add" default, and the graphics additions (torch glow, NPC colors, facing indicator, hit-flash, death-burst particles) rendering without console errors.
2. **Real sprites/art** — everything is still colored `Polygon2D` primitives; this is the single biggest visual upgrade left and wasn't attempted this session since it requires either an art pipeline decision (import assets? procedural shapes only?) or actual asset sourcing, both of which are bigger scope/require your input on direction and licensing.
3. **Second biome** (Sunken Coast & Marshes per the original spec) — would need a new `data/biome_*.json`, a new World-like scene (or an exit trigger from the current World scene), and probably a simple overworld/biome-transition mechanism, since right now `World.tscn` *is* the entire game.
4. **Real Anthropic API swap-in** for `GameMaster.process_dialogue()` — the seam is now explicitly documented (`USE_REAL_API` constant + phasing note at the top of `GameMaster.gd`), and the JSON contract is unchanged, so this is a scoped, additive follow-up whenever an API key + network layer are available. Nothing else in the codebase needs to change for this.
5. **Deeper inventory** (stacking limits, consumables like food items — `eat_food()` exists in `GameState` but nothing in the game currently grants/uses food items).
6. **Save-slot UI** — saves are still a single fixed `user://save.json`, no multiple-save support.
7. A third quest/epilogue beat beyond "Rebuilding Glenbrook" if the Rebuilding Era needs more content once tier-2 gear is live — right now that quest is the entirety of post-main-quest content.

## Environment reminder

Godot is still not installed on this dev machine. All verification needs to happen on your end — open the project, run it, and report back anything that errors or feels wrong. Given the scope of session 3 (multi-quest architecture, rewritten `npcs.json`, rewritten `GameMaster.gd`), a full playtest pass (both quests, a couple of classes, closing/reopening a save) is worth doing before trusting this is stable, rather than spot-checking just the new bits.
