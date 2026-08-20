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
