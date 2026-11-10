class_name ShooterContent
extends RefCounted

const PLAYER := {
	"plane": [Color("58a6ff"), "triangle"], "cat": [Color("f2a65a"), "cat"],
	"ufo": [Color("a78bfa"), "disc"], "dragon": [Color("ef4444"), "diamond"],
	"tank": [Color("65a30d"), "box"], "ghost": [Color("d8b4fe"), "ghost"],
}
const WEAPONS := {
	"straight": "single", "spread": "fan", "laser": "beam",
	"missile": "homing", "boomerang": "returning", "orbit": "orbital",
}
const ENEMIES := {
	"dog": [Color("d97706"), "box"], "bird": [Color("38bdf8"), "wing"],
	"turret": [Color("64748b"), "turret"], "bomber": [Color("dc2626"), "diamond"],
	"swarm": [Color("84cc16"), "disc"],
}
const BEHAVIORS := ["chase", "sine", "static", "dive", "flock"]
const BOSSES := {
	"godzilla": [Color("16a34a"), "spike"], "kraken": [Color("7c3aed"), "tentacle"],
	"mecha": [Color("94a3b8"), "box"], "demon": [Color("b91c1c"), "diamond"],
	"worm": [Color("ca8a04"), "worm"],
}
const BOSS_SKILLS := ["fireball", "laser_sweep", "summon_minions", "bullet_hell", "charge"]
const DROPS := {
	"heal": [Color("22c55e"), "plus"], "shield": [Color("3b82f6"), "ring"],
	"power": [Color("eab308"), "bolt"], "coin": [Color("f59e0b"), "disc"],
	"bomb": [Color("111827"), "bomb"],
}
const BACKGROUNDS := {
	"space": Color("071426"), "city": Color("273449"), "ocean": Color("075985"),
	"lava": Color("7f1d1d"), "forest": Color("14532d"),
}

static func has_complete_catalog() -> bool:
	return PLAYER.size() == 6 and WEAPONS.size() == 6 and ENEMIES.size() == 5 \
		and BEHAVIORS.size() == 5 and BOSSES.size() == 5 and BOSS_SKILLS.size() == 5 \
		and DROPS.size() == 5 and BACKGROUNDS.size() == 5
