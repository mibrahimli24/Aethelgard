extends RefCounted
## Landmark layouts for the southern regions: Stormcoast, Gloomfen, Ashen Wastes.

const TIMBER := Color(0.45, 0.32, 0.2)
const DRIFT := Color(0.55, 0.5, 0.42)
const PLASTER := Color(0.78, 0.72, 0.6)
const SLATE := Color(0.35, 0.38, 0.45)
const STONE := Color(0.5, 0.5, 0.52)
const MOSS := Color(0.3, 0.38, 0.28)
const BOG := Color(0.16, 0.26, 0.2)
const SWAMP_W := Color(0.28, 0.25, 0.18)
const CHAR := Color(0.25, 0.22, 0.22)
const OBS := Color(0.17, 0.14, 0.2)
const ASH_RED := Color(0.45, 0.12, 0.1)
const SEA := Color(0.2, 0.4, 0.55)
const BLUE := Color(0.2, 0.35, 0.6)
const RED := Color(0.6, 0.14, 0.14)

const L := {
	"gull_point_lighthouse": [
		["light", 0, 0], ["house", 90, 60, PLASTER, SLATE, 66, 40], ["boulder", -90, 40, 1.4, STONE], ["boulder", -120, -10, 1.2, STONE],
		["boulder", 110, -20, 1.1, STONE], ["barrel", 40, 50, 1.0], ["crate", 54, 54, 1.0], ["fence", -60, 90, 100], ["driftwood", -40, 70, 1.0],
		["shell", 20, 90], ["sign", 120, 100, TIMBER],
	],
	"driftwood_harbor": [
		["dock", -30, 160, 60, 110], ["dock", 90, 170, 40, 80],
		["house", -140, -60, DRIFT, SLATE, 76, 44], ["house", 60, -90, PLASTER, SLATE, 74, 44], ["house", 190, -20, DRIFT, Color(0.5, 0.25, 0.2), 70, 42],
		["house", -60, 70, PLASTER, Color(0.5, 0.25, 0.2), 70, 42], ["stall", 130, 70, BLUE, Color(0.55, 0.7, 0.8)], ["stall", -20, 0, RED, Color(0.8, 0.65, 0.3)],
		["boat", -60, 220, TIMBER, 90], ["boat", 70, 235, DRIFT, 70],
		["barrel", 30, 130, 1.0], ["barrel", 44, 134, 1.0], ["crate", -80, 140, 1.0], ["crate", -66, 146, 1.1],
		["lamp", 10, 60], ["lamp", 110, 130], ["lamp", -110, 130], ["cart", 160, -100, DRIFT], ["driftwood", -190, 80, 1.2], ["shell", 150, 140],
		["fence", -230, -20, 100],
	],
	"wreck_cove": [
		["wreck", 0, 30], ["driftwood", -110, 10, 1.3], ["driftwood", 120, 40, 1.1], ["shell", -60, 70], ["shell", 70, 80], ["shell", 20, -50],
		["boulder", -150, -30, 1.4, STONE], ["boulder", 150, -20, 1.3, STONE], ["bones", 90, -30, 1.0], ["barrel", -50, 20, 1.0],
		["chest", 70, -60, "wreck_cove", "pearl_shell:2,ancient_coin:2"],
	],
	"tidecaller_cave": [
		["gnd", 0, 0, Color(0.3, 0.33, 0.35, 0.55), 150, 100],
		["cave", 0, -80, Color(0.08, 0.1, 0.14), 130], ["boulder", -140, -10, 1.5, STONE], ["boulder", 140, 10, 1.4, STONE], ["boulder", -80, 80, 1.1, STONE],
		["pool", 0, 80, 70, 30, SEA, false], ["shell", -40, 40], ["shell", 60, 30], ["driftwood", 100, 90, 1.0], ["bones", -30, 10, 1.0],
		["chest", 70, -30, "tidecaller_cave", "pearl_shell:3,sea_kelp:2"],
	],
	"smugglers_camp": [
		["gnd", 0, 0, Color(0.28, 0.24, 0.18, 0.6), 150, 100],
		["fire", 0, 20], ["tent", -90, -30, Color(0.2, 0.25, 0.3), 1.0], ["tent", 90, -40, Color(0.3, 0.22, 0.18), 1.0], ["tent", 0, -90, Color(0.2, 0.25, 0.3), 1.1],
		["crate", -40, 50, 1.2], ["crate", -24, 54, 1.0], ["barrel", 50, 40, 1.0], ["barrel", 64, 44, 1.0], ["boat", 150, 80, DRIFT, 70],
		["torch", -50, -10], ["torch", 60, -10], ["logs", 100, 10],
		["chest", 0, -50, "smugglers_camp", "ancient_coin:4,pearl_shell:1"],
	],
	"mossfen_hut": [
		["gnd", 0, 0, Color(0.15, 0.2, 0.14, 0.6), 140, 90],
		["hut", 0, -44, SWAMP_W, MOSS, 72, 44, true], ["fire", 70, 20], ["pool", -140, 40, 60, 34, BOG, false], ["reed", -100, -20, 1.2], ["reed", -170, 80, 1.1],
		["reed", 120, -40, 1.0], ["barrel", -40, 20, 1.0], ["logs", 50, 70], ["tree", 150, 50, "twist"], ["tree", -150, -50, "twist"], ["mush", -60, 70, 1.2, Color(0.75, 0.7, 0.3)],
	],
	"sunken_chapel": [
		["gnd", 0, 0, Color(0.14, 0.2, 0.15, 0.6), 160, 110],
		["chapel", 0, -34], ["pool", -150, 50, 80, 40, BOG, false], ["pool", 140, 70, 60, 30, BOG, false], ["pillar", -90, 10, 50, STONE, true], ["pillar", 90, 0, 60, STONE, true],
		["rubble", -60, 80, 1.2, STONE], ["rubble", 110, -50, 1.1, STONE], ["reed", -110, -30, 1.1], ["reed", 160, 20, 1.0], ["bones", 40, 80, 1.0],
		["torch", -30, 20], ["torch", 30, 20],
		["chest", 70, -40, "sunken_chapel", "ancient_coin:2,bog_slime:2"],
	],
	"drowned_hollow": [
		["pool", 0, 20, 120, 70, Color(0.1, 0.18, 0.16), false], ["tree", -150, -40, "twist"], ["tree", 140, -50, "dead"], ["tree", -100, 100, "dead"],
		["bones", -40, -50, 1.2], ["bones", 70, -40, 1.0], ["reed", 90, 90, 1.2], ["reed", -140, 40, 1.1], ["mush", 20, -90, 1.4, Color(0.4, 0.8, 0.7)],
		["chest", -20, -70, "drowned_hollow", "bog_slime:3,ancient_coin:2"],
	],
	"leech_pools": [
		["pool", -90, -20, 80, 48, Color(0.12, 0.2, 0.15), true], ["pool", 80, 40, 90, 52, Color(0.12, 0.2, 0.15), true], ["pool", 10, -100, 60, 36, Color(0.14, 0.22, 0.16), true],
		["reed", -20, 20, 1.2], ["reed", 160, -30, 1.0], ["reed", -170, 50, 1.1], ["mush", 0, 90, 1.2, Color(0.6, 0.45, 0.75)], ["tree", 150, 110, "twist"], ["bones", 40, -10, 1.0],
	],
	"toad_mound": [
		["gnd", 0, 0, Color(0.2, 0.26, 0.16, 0.7), 130, 90],
		["cave", 0, -70, Color(0.1, 0.14, 0.1), 110], ["mush", -80, 0, 1.6, Color(0.7, 0.3, 0.25)], ["mush", 80, 10, 1.5, Color(0.4, 0.8, 0.7)], ["mush", -30, 60, 1.2, Color(0.75, 0.7, 0.3)],
		["boulder", -130, -40, 1.3, MOSS], ["boulder", 130, -30, 1.2, MOSS], ["pool", 100, 80, 50, 26, BOG, false], ["reed", -100, 70, 1.0],
		["chest", 30, -20, "toad_mound", "glowcap:2,bog_slime:2"],
	],
	"cinder_ruins": [
		["gnd", 0, 0, Color(0.14, 0.12, 0.12, 0.7), 170, 120],
		["wall", 0, -100, 190, CHAR, 44], ["wall", -100, 0, 120, CHAR, 34], ["wall", 100, 30, 110, CHAR, 28],
		["pillar", -50, -30, 80, CHAR, true], ["pillar", 40, -50, 70, CHAR, false], ["pillar", -60, 70, 60, CHAR, true],
		["rubble", 140, 90, 1.3, CHAR], ["rubble", -150, 70, 1.2, CHAR], ["torch", 20, 60], ["bones", 90, -20, 1.0],
		["chest", -60, -40, "cinder_ruins", "ember_core:1,sulfur:2"],
	],
	"ember_throne": [
		["gnd", 0, 0, Color(0.1, 0.08, 0.09, 0.75), 190, 130],
		["throne", 0, -50], ["lava", -150, 10, 50, 30], ["lava", 150, 20, 50, 30], ["spike", -100, -70, 1.3], ["spike", 100, -70, 1.3],
		["spike", -60, 70, 1.0], ["spike", 60, 80, 1.1], ["banner", -60, 10], ["banner", 60, 10], ["torch", -30, 50], ["torch", 30, 50], ["bones", 0, 100, 1.2],
		["chest", 0, 20, "ember_throne", "ember_core:2,obsidian_shard:2,ancient_coin:5"],
	],
	"obsidian_spire": [
		["gnd", 0, 0, Color(0.1, 0.08, 0.12, 0.7), 140, 100],
		["tower", 0, -20, 54, 150, OBS, false], ["spike", -90, 10, 1.4], ["spike", 90, 0, 1.5], ["spike", -50, 80, 1.1], ["spike", 60, 90, 1.2],
		["rubble", 0, 70, 1.2, OBS], ["bones", -110, 70, 1.0], ["torch", -30, 30], ["torch", 30, 30],
		["chest", 0, 40, "obsidian_spire", "obsidian_shard:3,sulfur:2"],
	],
	"lava_fields": [
		["lava", -140, -40, 80, 44], ["lava", 100, 30, 100, 54], ["lava", -30, 100, 70, 38], ["lava", 170, -70, 54, 30],
		["spike", -40, -60, 1.3], ["spike", 20, 30, 1.1], ["spike", -150, 60, 1.2], ["spike", 80, -80, 1.0], ["bones", 40, 80, 1.1], ["boulder", -80, 20, 1.3, CHAR],
	],
	"legion_camp": [
		["gnd", 0, 0, Color(0.12, 0.1, 0.1, 0.7), 170, 110],
		["fire", 0, 20], ["tent", -100, -30, ASH_RED, 1.1], ["tent", 100, -40, ASH_RED, 1.1], ["tent", 0, -100, Color(0.3, 0.1, 0.1), 1.3],
		["pal", 0, -140, 200], ["banner", -150, 40], ["banner", 150, 30], ["torch", -50, 60], ["torch", 50, 60], ["spike", -160, -60, 1.2], ["spike", 170, -50, 1.2],
		["crate", 50, -10, 1.0], ["barrel", 64, -4, 1.0], ["dummy", -60, 80], ["bones", 100, 90, 1.0],
		["chest", 0, -50, "legion_camp", "ember_core:1,obsidian_shard:2,ancient_coin:3"],
	],
}
