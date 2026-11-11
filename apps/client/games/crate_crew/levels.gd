extends RefCounted

## The map of a run of Crate Crew and the index of its levels. A run goes from the squirrels' stump through four places: the kitchen, the toy shop, the sewer and the treehouse. Each place has an opening level, two second levels of which the players pick one on the map, and a boss; so one route is twelve levels long. The levels themselves are written in the theme scripts.

const Builder := preload("res://games/crate_crew/builder.gd")
const Kitchen := preload("res://games/crate_crew/kitchen.gd")
const Toyshop := preload("res://games/crate_crew/toyshop.gd")
const Sewer := preload("res://games/crate_crew/sewer.gd")
const Treehouse := preload("res://games/crate_crew/treehouse.gd")

const TILE := Builder.TILE
const EMPTY := Builder.EMPTY
const SOLID := Builder.SOLID
const SHELF := Builder.SHELF
const HAZARD := Builder.HAZARD
const CRACK := Builder.CRACK

const THEMES := ["kitchen", "toyshop", "sewer", "treehouse"]

## Every node of the map: where it sits on the 384 x 216 map screen, its theme, what it is ("start", "level", "boss") and the nodes that open once it is cleared. A level's id is its node's id.
const NODES := {
	"home": {"at": Vector2(46, 136), "theme": "", "kind": "start", "next": ["k1"]},
	"k1": {"at": Vector2(62, 88), "theme": "kitchen", "kind": "level", "next": ["k2", "k3"]},
	"k2": {"at": Vector2(104, 62), "theme": "kitchen", "kind": "level", "next": ["kb"]},
	"k3": {"at": Vector2(108, 108), "theme": "kitchen", "kind": "level", "next": ["kb"]},
	"kb": {"at": Vector2(150, 82), "theme": "kitchen", "kind": "boss", "next": ["t1"]},
	"t1": {"at": Vector2(208, 70), "theme": "toyshop", "kind": "level", "next": ["t2", "t3"]},
	"t2": {"at": Vector2(250, 52), "theme": "toyshop", "kind": "level", "next": ["tb"]},
	"t3": {"at": Vector2(254, 98), "theme": "toyshop", "kind": "level", "next": ["tb"]},
	"tb": {"at": Vector2(310, 74), "theme": "toyshop", "kind": "boss", "next": ["s1"]},
	"s1": {"at": Vector2(338, 124), "theme": "sewer", "kind": "level", "next": ["s2", "s3"]},
	"s2": {"at": Vector2(304, 150), "theme": "sewer", "kind": "level", "next": ["sb"]},
	"s3": {"at": Vector2(334, 186), "theme": "sewer", "kind": "level", "next": ["sb"]},
	"sb": {"at": Vector2(270, 180), "theme": "sewer", "kind": "boss", "next": ["r1"]},
	"r1": {"at": Vector2(210, 170), "theme": "treehouse", "kind": "level", "next": ["r2", "r3"]},
	"r2": {"at": Vector2(160, 150), "theme": "treehouse", "kind": "level", "next": ["rb"]},
	"r3": {"at": Vector2(164, 194), "theme": "treehouse", "kind": "level", "next": ["rb"]},
	"rb": {"at": Vector2(104, 172), "theme": "treehouse", "kind": "boss", "next": []},
}
## How many levels one route through the map takes.
const ROUTE_LENGTH := 12
## Every level id, in map order.
const LEVELS := ["k1", "k2", "k3", "kb", "t1", "t2", "t3", "tb", "s1", "s2", "s3", "sb", "r1", "r2", "r3", "rb"]
const FINAL := "rb"

static func build(id: String) -> Dictionary:
	match str(NODES[id]["theme"]):
		"kitchen":
			return Kitchen.new().build(id)
		"toyshop":
			return Toyshop.new().build(id)
		"sewer":
			return Sewer.new().build(id)
		_:
			return Treehouse.new().build(id)

## The node before `id` on the map (its first parent), or "".
static func parent_of(id: String) -> String:
	for other: String in NODES:
		if id in NODES[other]["next"]:
			return other
	return ""

static func theme_index(theme: String) -> int:
	return maxi(0, THEMES.find(theme))
