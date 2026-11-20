# Aethelgard

A 2D medieval survival-RPG vertical slice built in **Godot 4** with a mocked LLM-driven dialogue system.

## About

Aethelgard is an experimental game that explores how an LLM can drive NPC dialogue, quest gating, and narrative progression. This vertical slice features the **Whispering Glades** biome where the player uncovers a conspiracy involving corrupted dire wolves, guides from local NPCs, and a final confrontation with the Red Fang Clan's beastmaster.

### Key Features

- **5 playable classes**: Swordsman, Bowman, Magic User, Rogue, Alchemist — each with class-specific combat stats, attack types, and equipment tiers
- **Multi-quest system**: Complete the main "Whispers in the Glade" quest chain, then unlock "Rebuilding Glenbrook" in the post-game era
- **Story-gated dialogue**: NPCs reveal secrets based on rapport, quest flags, and in-world events; dialogue diversifies after secrets are told
- **Survival mechanics**: HP/hunger system, class-based armor mitigation, dynamic speed scaling
- **Equipment progression**: Unlock and craft tiered gear for all 5 classes via quest rewards
- **Mocked LLM backend**: Deterministic, rule-based dialogue system (keyword matching, rapport counters, lore generation) shaped exactly like a real Anthropic API contract — ready for live integration later
- **Persistent saves**: JSON-file autosave + close-on-quit persistence
- **Living world**: village with houses, well, lamps and paths; forest, ridge and pond; day/night cycle with lighting, fireflies, night wisps, wandering deer and rabbits
- **Combat feel**: dodge with i-frames, per-class special abilities, hit-stop, screen shake, archers, boars, wisps, and a multi-phase boss; wild spawns scale with level
- **Survival & loot**: foraging, hunting drops, campfire cooking, chests, waystones, food that restores hunger and HP
- **Polished UI**: HUD with minimap, hotbar, toasts and boss bar; satchel, pause menu, typewriter dialogue
- **Procedural audio**: all sound effects are generated in code (no asset files); press M to mute

## Installation

1. **Install Godot 4.x** (free, [godotengine.org](https://godotengine.org))
2. **Clone this repository**:
   ```bash
   git clone https://github.com/YOUR-USERNAME/Aethelgard.git
   cd Aethelgard
   ```
3. **Open the project**: Launch Godot and select the `project.godot` file in this directory

## How to Play

- **Movement**: WASD or arrow keys
- **Attack**: Space (ranged classes aim in their facing direction)
- **Special / Dodge / Eat**: Q / Shift / F
- **Interact**: E (talk to NPCs, interact with quest markers)
- **Class Switch**: C (opens class selector)
- **Pause**: Esc (save, sound toggle, quit)
- **Satchel**: I (items, eating, crafting, stats)
- **Dialogue**: Type responses or press Enter for default greetings

### Quest Line

1. Speak with **Garrick Hale** (by the village)
2. Hunt dire wolves to prove the corruption claim
3. Report back to Garrick, then talk to **Mira Thistlewood** about the deeper mystery
4. Reveal Mira's secret and trigger the Red Fang Camp to appear
5. Clear the camp bandits and face **Skar**, the Beastmaster
6. Post-victory, visit **Old Ferris** to craft tier-2 gear with the Bloodstone Shard fragment

## Project Structure

```
Aethelgard/
├── autoloads/           # Singletons (GameState, GameMaster, EventBus, Fx)
├── data/                # JSON configs (NPCs, quests, classes, biome data)
├── scenes/              # Godot scenes and scripts
│   ├── World.*          # Main level: decor, day/night, spawner, camp
│   ├── Interactable.*   # Campfires, chests, waystones, forage nodes
│   ├── Critter.gd       # Ambient wildlife
│   ├── Player.*         # Player character
│   ├── Enemy.*, Boss.*  # Hostile creatures
│   ├── NPC.*            # Interactable NPCs
│   └── UI/              # HUD, dialogue, inventory, class switcher
├── scripts/             # Art builders, world decor, UI style
├── project.godot        # Godot project config
├── handoff.md           # Detailed session notes (see for implementation details)
└── .gitignore           # Git ignore patterns
```

## What's Implemented

✅ Full vertical slice (one biome, one class fully playable, multiple others stubbed)
✅ Mocked LLM dialogue with rapport gating and story progression
✅ Multi-quest system with game-phase transitions
✅ Equipment crafting and tier progression
✅ Combat: melee, ranged, crit chances, class-specific stats
✅ Survival: HP, hunger, speed scaling
✅ Persistent saves (autosave + close-quit save)
✅ Graphics: procedural art, day/night lighting, particles, HUD/minimap
✅ Procedural audio, pause menu, foraging/cooking/loot
✅ Large 3x3 region world (12000x9000) with 38 landmarks, lazily streamed
✅ Player guidance, world map, item info panels, token-free NPC conversations
✅ Animated characters (walk/attack/roll/hurt, NPC work gestures, critters)

## What's Not Yet Implemented

- Real Anthropic API integration (scaffolding exists; see `GameMaster.gd` for the `USE_REAL_API` seam)
- Sprite art (currently all polygon primitives)
- Save-slot UI (one fixed save file)

## Development Notes

See **[handoff.md](./handoff.md)** for:
- Detailed session-by-session progress
- Known risks and untested areas (session 4 was verified headlessly and by screenshots, not by a long human playtest)
- Suggested next steps prioritized by impact

### Verification status

The project boots cleanly on Godot 4.7 and a scripted smoke test covered combat, interactables, class switching, saves and quest stages. Balance and feel still need a human playtest; please report anything odd via Issues.

## Architecture Highlights

### GameMaster (Mocked LLM)
The `GameMaster` autoload uses keyword matching, rapport tracking, and a no-repeat rotating lore table to generate NPC dialogue. It returns the exact JSON shape a real Claude API would return, making integration seamless later.

### Multi-Quest System
Quests are data-driven from `data/quests.json` and support stage gating, game-phase requirements, and dynamic class-agnostic rewards. The system auto-unlocks quests based on `game_phase` transitions.

### Class-Driven Combat
Attack behavior (melee vs. ranged, damage, cooldown, crit) is read from `GameState.get_active_combat_stats()`, which pulls from the active class's `"combat"` block in `classes.json`. Zero combat logic lives in scripts; all balance is data.

## License

TBD — choose a license that fits your distribution plans.

## Contact

For questions or feedback, open an issue or start a discussion in this repo.

---

**Happy adventuring in the Whispering Glades!**
