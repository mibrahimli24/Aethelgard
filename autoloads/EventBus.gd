extends Node
## Global signal bus. Decouples systems (World/UI/AI) from GameState/GameMaster internals --
## nodes connect to EventBus signals instead of reaching into autoloads directly.

## Emitted by an NPC when the player presses "interact" while in range -- decouples NPC.gd
## from whichever UI node is actually listening (DialogueUI).
signal dialogue_requested(npc_id: String, display_name: String)

## Emitted whenever GameMaster finishes "processing" a dialogue turn (the mocked async LLM response).
## payload: Dictionary matching the strict JSON contract {dialogue, npc_mood, generated_lore_snippet, game_actions}
signal dialogue_ready(npc_id: String, payload: Dictionary)

## Emitted once per game_actions[] entry as GameState applies it, so UI/world nodes can react
## (e.g. spawn a camp marker, flash a quest update toast).
signal action_dispatched(action: Dictionary)

## Emitted whenever HP, hunger, or EXP changes so HUD can refresh without polling.
signal vitals_changed()

## Emitted whenever the active quest advances a stage.
signal quest_updated(quest_id: String, stage: int, objective: String)

## Emitted when the player's active class changes.
signal class_changed(new_class_id: String)

## Short on-screen message (pickups, level-ups, quest updates, mute toggle). HUD renders these as toasts.
signal toast_requested(text: String, color: Color)

## Emitted after an active class levels up.
signal level_up(class_id: String, new_level: int)

## Boss health bar plumbing: Boss.gd emits these, HUD shows/hides/updates a bar.
signal boss_engaged(display_name: String, max_hp: float)
signal boss_hp_changed(hp: float, max_hp: float)
signal boss_defeated()

## Inventory contents changed (pickups, crafting, eating) -- hotbar/inventory refresh.
signal inventory_changed()

## Fired when the player uses their class special ability; HUD uses it to run the cooldown display.
signal special_used(cooldown: float)

## Player's nearest interactable changed. Empty string = nothing in reach. HUD shows it as a prompt.
signal interact_prompt_changed(text: String)

## The player died / respawned -- HUD shows the "You Died" overlay.
signal player_died()
signal player_respawned()

## Player crossed into a new region (see data/regions.json). HUD shows a banner.
signal region_entered(region_id: String, region_name: String)
## A landmark was discovered (walked near it). Map + toast.
signal landmark_discovered(landmark_id: String, landmark_name: String)
## Open the full-screen world map (M).
signal map_requested()
## An NPC should show an overhead speech bubble.
signal npc_bubble(npc_id: String, text: String)
