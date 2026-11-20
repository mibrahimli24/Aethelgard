extends RefCounted
## Landmark layouts for the northern and central regions. Spec: [kind, dx, dy, params...] (see WorldLandmarks._place).

const TIMBER := Color(0.45, 0.32, 0.2)
const THATCH := Color(0.7, 0.58, 0.3)
const PLASTER := Color(0.78, 0.7, 0.55)
const TILE := Color(0.55, 0.25, 0.18)
const SLATE := Color(0.35, 0.38, 0.45)
const STONE := Color(0.5, 0.5, 0.52)
const RUIN := Color(0.48, 0.47, 0.44)
const ICE := Color(0.7, 0.76, 0.84)
const SAND_W := Color(0.85, 0.72, 0.5)
const SAND_R := Color(0.7, 0.35, 0.25)
const CANVAS := Color(0.8, 0.72, 0.55)
const RED := Color(0.6, 0.14, 0.14)
const BLUE := Color(0.2, 0.35, 0.6)
const GREEN := Color(0.2, 0.45, 0.25)
const WATER := Color(0.2, 0.42, 0.62)
const OASIS := Color(0.15, 0.5, 0.55)

const L := {
	"thornwood_lodge": [
		["gnd", 0, 0, Color(0.2, 0.17, 0.12, 0.7), 170, 110],
		["fire", 0, 24], ["hut", -120, -26, TIMBER, Color(0.25, 0.3, 0.2), 76, 44, false],
		["hut", 118, -44, TIMBER, Color(0.3, 0.22, 0.16), 70, 42, false], ["tent", -52, -96, GREEN, 1.0],
		["logs", 76, 40], ["barrel", -64, 44, 1.0], ["crate", -80, 56, 1.0], ["torch", -52, 0], ["torch", 52, 0],
		["sign", -30, 120, TIMBER], ["fence", -150, 60, 90], ["bones", 130, 80, 1.0],
	],
	"moonwell": [
		["gnd", 0, 0, Color(0.3, 0.45, 0.5, 0.35), 150, 100],
		["moonwell", 0, 0], ["stone", -110, -40, 1.2, Color(0.5, 0.8, 1.0)], ["stone", 110, -40, 1.2, Color(0.5, 0.8, 1.0)],
		["stone", -70, 70, 1.0, Color(0.5, 0.8, 1.0)], ["stone", 70, 70, 1.0, Color(0.5, 0.8, 1.0)], ["stone", 0, -100, 1.3, Color(0.5, 0.8, 1.0)],
		["mush", -50, -60, 1.1, Color(0.6, 0.45, 0.75)], ["mush", 60, -66, 0.9, Color(0.6, 0.45, 0.75)],
	],
	"hollow_ruins": [
		["gnd", 0, 0, Color(0.15, 0.2, 0.15, 0.6), 160, 110],
		["wall", 0, -90, 180, RUIN, 40], ["wall", -90, 10, 120, RUIN, 28], ["wall", 90, 40, 100, RUIN, 34],
		["pillar", -50, -20, 60, RUIN, true], ["pillar", 50, -20, 70, RUIN, false], ["pillar", 0, 60, 50, RUIN, true],
		["rubble", -120, 60, 1.2, RUIN], ["rubble", 120, -30, 1.0, RUIN], ["bones", 30, 30, 1.0],
		["chest", 0, -50, "hollow_ruins", "ancient_coin:2,old_key:1,bone_dust:2"],
	],
	"spider_den": [
		["web", 0, 0, 150], ["web", -90, 50, 70], ["web", 100, -40, 80],
		["cave", 0, -100, Color(0.1, 0.1, 0.12), 110], ["bones", -60, 30, 1.2], ["bones", 70, 20, 1.0],
		["bones", 20, 70, 0.9], ["tree", -150, -20, "dead"], ["tree", 150, 30, "dead"], ["mush", -30, -40, 1.2, Color(0.55, 0.2, 0.55)],
	],
	"old_watchtower": [
		["tower", 0, 0, 60, 120, STONE, true], ["rubble", -60, 20, 1.3, STONE], ["rubble", 54, 28, 1.0, STONE],
		["wall", 0, 70, 90, RUIN, 22], ["banner", -90, 40], ["torch", 80, 20], ["boulder", 100, -20, 1.0, STONE],
	],
	"frostwatch_outpost": [
		["gnd", 0, 0, Color(0.6, 0.66, 0.74, 0.55), 180, 120],
		["tower", -120, -70, 56, 110, SLATE, false], ["pal", 0, -110, 220], ["pal", -150, 20, 120], ["pal", 150, 20, 120],
		["fire", 0, 20], ["tent", -60, -34, BLUE, 1.0], ["tent", 70, -50, BLUE, 1.0], ["house", 112, 40, TIMBER, SLATE, 64, 38],
		["banner", -170, 50], ["banner", 170, 50], ["torch", -40, 60], ["torch", 40, 60], ["crate", 30, -30, 1.0], ["barrel", 44, -24, 1.0],
		["sign", 0, 130, SLATE],
	],
	"hermit_cave": [
		["cave", 0, -50, Color(0.12, 0.12, 0.16), 120], ["fire", 36, 30], ["logs", -70, 10], ["boulder", -120, -20, 1.3, STONE],
		["boulder", 120, -10, 1.1, STONE], ["crystal", 80, 60, 0.9], ["tree", -150, 50, "spine"], ["tree", 150, 60, "spine"], ["barrel", -30, 20, 1.0],
	],
	"frozen_lake": [
		["gnd", 0, 0, Color(0.72, 0.84, 0.92), 230, 140], ["gnd", -30, -10, Color(0.82, 0.92, 0.98, 0.8), 150, 80],
		["crystal", -170, -60, 1.2], ["crystal", 150, 70, 1.0], ["crystal", 200, -40, 0.9], ["crystal", -100, 100, 1.1],
		["bones", 40, 20, 1.0], ["boulder", 0, 140, 1.2, ICE],
	],
	"rimefang_den": [
		["gnd", 0, 0, Color(0.5, 0.58, 0.68, 0.5), 150, 100],
		["cave", 0, -90, Color(0.1, 0.14, 0.2), 130], ["crystal", -100, -30, 1.3], ["crystal", 100, -20, 1.2], ["crystal", -60, 70, 1.0],
		["bones", -30, 20, 1.3], ["bones", 40, 40, 1.1], ["boulder", 140, 60, 1.2, ICE],
		["chest", 20, -30, "rimefang_den", "frost_fang:2,ancient_coin:3"],
	],
	"summit_shrine": [
		["gnd", 0, 0, Color(0.88, 0.92, 0.98, 0.7), 110, 80],
		["stone", -60, -10, 1.3, Color(0.5, 0.8, 1.0)], ["stone", 60, -10, 1.3, Color(0.5, 0.8, 1.0)], ["stone", 0, -50, 1.5, Color(0.5, 0.8, 1.0)],
		["crystal", -30, 40, 1.0], ["crystal", 40, 50, 0.9], ["torch", -20, 20], ["torch", 20, 20],
	],
	"kingsford": [
		["gnd", 0, 0, Color(0.5, 0.42, 0.3, 0.5), 290, 190],
		["well", 0, 20], ["house", -250, -90, PLASTER, TILE, 78, 46], ["house", -150, 110, PLASTER, THATCH, 70, 42],
		["house", 120, -170, PLASTER, TILE, 74, 44], ["house", 250, -50, TIMBER, TILE, 76, 46], ["house", 200, 140, PLASTER, THATCH, 70, 42],
		["house", -60, 160, TIMBER, THATCH, 72, 44], ["house", 250, 230, PLASTER, SLATE, 70, 42], ["house", -250, 200, TIMBER, TILE, 70, 44],
		["house", 20, -230, PLASTER, SLATE, 90, 54], ["stall", -90, -50, RED, Color(0.85, 0.3, 0.2)], ["stall", 90, 20, BLUE, Color(0.8, 0.65, 0.3)],
		["lamp", -60, 10], ["lamp", 60, 10], ["lamp", 0, -80], ["lamp", 0, 90], ["barrel", 120, 80, 1.0], ["crate", 136, 84, 1.0],
		["cart", -180, -10, THATCH], ["fence", -300, 40, 120], ["tree", -300, -160, "loak"], ["tree", 300, 120, "loak"], ["sign", 0, 270, TIMBER],
	],
	"harvest_farm": [
		["field", -150, 20, 150, 90], ["field", 0, 120, 160, 80], ["field", 170, 30, 110, 90],
		["barn", -20, -90, Color(0.6, 0.2, 0.15), Color(0.4, 0.25, 0.18), 110, 70], ["house", 120, -80, PLASTER, THATCH, 70, 42],
		["hay", -110, -60, 1.0], ["hay", -90, -40, 0.8], ["scare", -100, 30], ["scare", 90, 120], ["fence", -230, -20, 120],
		["cart", 70, 0, THATCH], ["well", 190, -30], ["tree", 230, -100, "loak"], ["tree", -250, 110, "loak"],
	],
	"old_windmill": [
		["mill", 0, 0], ["hay", -70, 30, 1.0], ["hay", -52, 44, 0.8], ["cart", 80, 40, THATCH],
		["fence", -120, 70, 100], ["field", 40, 110, 140, 70], ["tree", 120, -50, "loak"],
	],
	"bandit_lookout": [
		["gnd", 0, 0, Color(0.3, 0.24, 0.15, 0.6), 150, 100],
		["tower", -100, -60, 50, 100, TIMBER, false], ["pal", 0, -90, 180], ["pal", -110, 40, 90],
		["tent", 40, -30, RED, 1.0], ["tent", 100, 30, Color(0.4, 0.2, 0.15), 0.9], ["fire", -20, 30], ["banner", 140, -50],
		["crate", -50, 20, 1.0], ["barrel", -62, 28, 1.0], ["bones", 60, 80, 1.0],
		["chest", 70, -60, "bandit_lookout", "bandit_insignia:1,cooked_meat:2,iron_ore:2"],
	],
	"ironhold_quarry": [
		["gnd", 0, 0, Color(0.5, 0.47, 0.42, 0.55), 170, 110],
		["hut", -90, -50, TIMBER, SLATE, 72, 44, false], ["mine", 80, -60], ["cart", 10, 10, STONE], ["logs", -40, 70],
		["boulder", -150, 20, 1.5, STONE], ["boulder", 160, 40, 1.4, STONE], ["rubble", -20, -30, 1.3, STONE], ["rubble", 130, 80, 1.2, STONE],
		["crate", 50, 50, 1.0], ["barrel", 66, 54, 1.0], ["torch", -20, 30], ["torch", 40, 20], ["sign", 0, 120, TIMBER],
	],
	"deepvein_mine": [
		["gnd", 0, 0, Color(0.25, 0.23, 0.22, 0.6), 160, 100],
		["mine", 0, -80], ["cart", -90, 10, STONE], ["cart", 100, 30, STONE], ["house", -130, -60, TIMBER, SLATE, 68, 42],
		["torch", -40, -20], ["torch", 40, -20], ["boulder", -160, 70, 1.3, STONE], ["boulder", 150, -30, 1.2, STONE], ["rubble", 30, 70, 1.2, STONE],
		["crate", 60, 10, 1.0], ["barrel", 76, 14, 1.0],
		["chest", -50, 60, "deepvein_mine", "iron_ore:3,coal:3"],
	],
	"dwarven_ruin": [
		["gnd", 0, 0, Color(0.32, 0.3, 0.3, 0.55), 170, 120],
		["wall", 0, -100, 200, RUIN, 46], ["wall", -100, 10, 130, RUIN, 36], ["wall", 100, 20, 130, RUIN, 30],
		["pillar", -50, -30, 80, RUIN, false], ["pillar", 50, -30, 80, RUIN, true], ["pillar", -50, 60, 70, RUIN, true], ["pillar", 50, 60, 60, RUIN, false],
		["throne", 0, -50], ["rubble", -150, 70, 1.4, RUIN], ["rubble", 150, -40, 1.2, RUIN], ["torch", 0, 20], ["bones", 0, 100, 1.0],
		["chest", 80, -70, "dwarven_ruin", "ancient_coin:3,iron_ore:3"],
	],
	"slag_camp": [
		["gnd", 0, 0, Color(0.12, 0.1, 0.1, 0.65), 170, 110],
		["fire", 0, 20], ["tent", -90, -30, Color(0.3, 0.25, 0.22), 1.0], ["tent", 90, -40, Color(0.3, 0.25, 0.22), 1.0],
		["pal", 0, -100, 180], ["banner", -140, 40], ["banner", 140, 30], ["torch", -40, 60], ["torch", 40, 60],
		["cart", -40, -80, STONE], ["crate", 40, -20, 1.0], ["barrel", 54, -14, 1.0], ["rubble", 120, 90, 1.2, STONE],
		["chest", 0, -40, "slag_camp", "iron_ore:3,coal:2,ancient_coin:1"],
	],
	"iron_tarn": [
		["pool", 0, 0, 130, 80, Color(0.18, 0.3, 0.4), true], ["boulder", -150, 50, 1.4, STONE], ["boulder", 160, -30, 1.3, STONE],
		["rubble", 100, 100, 1.2, STONE], ["reed", -120, -70, 1.0], ["reed", 120, 80, 1.0],
	],
	"dust_bazaar": [
		["gnd", 0, 0, Color(0.78, 0.62, 0.4, 0.6), 270, 180],
		["mtent", -150, -90, RED, 1.2], ["mtent", 140, -100, BLUE, 1.2], ["mtent", 0, -140, GREEN, 1.3], ["mtent", -230, 40, SAND_R, 1.1],
		["stall", -70, -10, RED, Color(0.8, 0.65, 0.3)], ["stall", 80, 0, BLUE, Color(0.85, 0.3, 0.2)], ["stall", -150, 70, GREEN, Color(0.8, 0.65, 0.3)], ["stall", 150, 80, RED, Color(0.85, 0.3, 0.2)],
		["house", 230, -40, SAND_W, SAND_R, 76, 46], ["house", -240, -50, SAND_W, SAND_R, 74, 44], ["house", 220, 170, SAND_W, SAND_R, 70, 42],
		["house", -30, 170, SAND_W, SAND_R, 78, 46], ["well", 0, 50], ["cart", 40, 110, THATCH], ["lamp", -40, 60], ["lamp", 40, 60],
		["tree", 290, 100, "palm"], ["tree", -290, 140, "palm"], ["barrel", 100, 110, 1.0], ["crate", 114, 114, 1.0],
	],
	"oasis_of_tamsin": [
		["pool", -10, 0, 120, 70, OASIS, true], ["tree", -130, -40, "palm"], ["tree", 100, -60, "palm"], ["tree", 120, 50, "palm"], ["tree", -90, 70, "palm"],
		["reed", 90, -10, 1.1], ["reed", -120, 20, 1.0], ["tent", 70, 100, SAND_R, 1.0], ["barrel", 40, 90, 1.0], ["fire", 140, 100],
	],
	"sun_temple": [
		["gnd", 0, 0, Color(0.7, 0.58, 0.4, 0.55), 180, 120],
		["wall", 0, -100, 200, SAND_W, 50], ["wall", -100, 10, 130, SAND_W, 36], ["wall", 100, 20, 120, SAND_W, 40],
		["pillar", -60, -30, 90, SAND_W, false], ["pillar", 60, -30, 90, SAND_W, false], ["pillar", -60, 60, 80, SAND_W, true], ["pillar", 60, 60, 70, SAND_W, true],
		["stone", 0, -40, 1.5, Color(0.5, 0.8, 1.0)], ["rubble", -150, 80, 1.3, SAND_W], ["rubble", 150, -60, 1.2, SAND_W], ["bones", 20, 100, 1.1],
		["chest", 0, 20, "sun_temple", "amber:2,ancient_coin:3"],
	],
	"scorpion_pit": [
		["gnd", 0, 0, Color(0.45, 0.33, 0.2, 0.7), 140, 100], ["gnd", 0, 0, Color(0.3, 0.22, 0.14, 0.8), 90, 60],
		["bones", -80, 20, 1.3], ["bones", 70, -20, 1.2], ["bones", 30, 60, 1.0], ["boulder", -130, -50, 1.4, SAND_R], ["boulder", 130, 50, 1.3, SAND_R],
		["tree", -160, 40, "cactus"], ["tree", 160, -40, "cactus"],
		["chest", 0, -40, "scorpion_pit", "scorpion_chitin:3,ancient_coin:2"],
	],
}
