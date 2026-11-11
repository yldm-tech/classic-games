extends "res://games/crate_crew/builder.gd"

## The tree in the garden and the treehouse at its top, where the crow keeps the stolen acorns: up the trunk branch by branch, along the long branches through brambles, over rope bridges and hanging baskets, and the crow itself. Walnuts break; pinecones break.

func build(id: String) -> Dictionary:
	match id:
		"r1":
			_trunk_climb()
		"r2":
			_branch_walk()
		"r3":
			_rope_bridges()
		_:
			_crow_nest()
	return _finish()

## Level 1: up the trunk. Branches stick out to both sides; hornets patrol between them and spiders hang from the ones above.
func _trunk_climb() -> void:
	_begin("r1", "treehouse", 24 + 26, 86)
	_main(24)
	_fill(0, 0, 1, 86)
	_fill(0, 0, 24, 2)
	_ground(0, 23, 84)
	_spawn(4, 83)
	_way(4, 83)
	_thing(8, 83, "walnut")
	_crate(10, 83, "acorns")
	_foe("worm", 17, 83, -1)
	_decor("mushroom", 21, 83)
	var columns := [2, 9, 16, 9]
	var row := 82
	var board := 0
	var count := 0
	while row > 6:
		if row in [72, 60, 48, 36, 24]:
			_bough(row, board)
			board += 1
			row -= 2
			continue
		var left: int = columns[count % columns.size()]
		count += 1
		_shelf(left, row, 6)
		_way(left + 2, row - 1)
		match count % 4:
			0:
				_thing(left + 3, row - 1, "walnut")
			1:
				_acorns(left + 1, row - 1, 3)
			2:
				_thing(left + 4, row - 1, "pinecone")
			_:
				_crate(left + 1, row - 1, "acorns" if count % 3 == 0 else "")
		if count % 5 == 2:
			_foe("hornet", 12, row - 3, 1, 4)
		if count % 5 == 4:
			_hang("spider", left + 2 if left != 9 else 15, row - 5, 3)
		row -= 2
	_shelf(1, 6, 23)
	_way(12, 5)
	_foe("worm", 7, 5, 1)
	_thing(15, 5, "walnut")
	_exit(21, 5)
	_way(21, 5)

## A thick bough right across the trunk with something on it.
func _bough(row: int, which: int) -> void:
	_shelf(1, row, 23)
	var stand := row - 1
	_way(12, stand)
	match which:
		0:
			_thing(3, stand, "walnut")
			_crate(5, stand)
			_foe("worm", 15, stand, -1)
			_foe("worm", 20, stand, -1)
			_flag(11, stand)
		1:
			_steel(4, stand)
			_thing(7, stand, "pinecone")
			_foe("worm", 18, stand, -1)
			_acorns(12, stand, 4)
			# A knot high on the trunk with a burrow in it, two crates up.
			_fill(1, row - 4, 3, 1)
			_bonus(2, row - 5, 4, stand, "golden", 2)
			_crate(9, stand)
		2:
			_spawner("worm", 22, stand, -1, 3.8, 2)
			_crate(4, stand, "heart")
			_thing(6, stand, "walnut")
			_flag(10, stand)
		3:
			_foe("worm", 3, stand, 1)
			_thing(10, stand, "pinecone")
			_crate(11, stand, "acorns")
			_foe("hornet", 18, stand - 4, -1, 3)
		_:
			_crate(5, stand, "bag")
			_thing(7, stand, "walnut")
			_foe("worm", 17, stand, -1)

## Level 2a: along the long branches of the tree. Brambles grow in the forks, caterpillars crawl along the bark, hornets dive and spiders drop from the branches above.
func _branch_walk() -> void:
	_begin("r2", "treehouse", 190 + 26, 18)
	_main(190)
	_spawn(3, 14)
	_way(3, 14)
	_ground(0, 22, 15)
	_thing(7, 14, "walnut")
	_crate(9, 14, "acorns")
	_foe("worm", 16, 14, -1)
	_fill(12, 8, 10, 1)
	_hang("spider", 17, 9, 3)
	_decor("leaf", 20, 14)
	_arch(22, 14, 4)
	_ground(25, 46, 15)
	_way(25, 14)
	_hazard(30, 14, 2)
	_thing(28, 14, "pinecone")
	_foe("hornet", 36, 9, -1, 4)
	_crate(39, 14)
	_foe("worm", 43, 14, -1)
	_ground(47, 50, 13)
	_way(47, 12)
	_ground(51, 70, 11)
	_way(51, 10)
	_flag(52, 10)
	_thing(55, 10, "walnut")
	_foe("worm", 60, 10, -1)
	_fill(56, 4, 12, 1)
	_hang("spider", 63, 5, 3)
	_crate(66, 10, "heart")
	_acorns(57, 8, 6)
	_way(70, 10)
	_ground(73, 98, 13)
	_way(73, 12)
	_hazard(78, 12, 2)
	_thing(76, 12, "pinecone")
	_foe("hornet", 84, 7, 1, 4)
	_crate(88, 12, "acorns")
	_foe("worm", 93, 12, -1)
	_thing(96, 12, "walnut")
	_ground(99, 130, 15)
	_way(99, 14)
	_spawner("worm", 129, 14, -1, 3.8, 2)
	_steel(103, 14)
	_hazard(107, 14, 2)
	_crate(111, 14)
	_foe("hornet", 115, 9, -1, 4)
	_thing(118, 14, "pinecone")
	_fill(119, 8, 10, 1)
	_hang("spider", 124, 9, 3)
	_crate(126, 14, "acorns")
	_arch(130, 14, 4)
	_ground(133, 189, 15)
	_way(133, 14)
	_flag(135, 14)
	_foe("worm", 140, 14, -1)
	_thing(138, 14, "walnut")
	_hazard(144, 14, 2)
	_crate(148, 14)
	_foe("hornet", 152, 9, -1, 4)
	# A hollow in the branch, sealed with bark that is cracked: a burrow inside.
	_ground(156, 163, 13)
	_crack(156, 14, 1, 1)
	_clear(157, 14, 2, 1)
	_bonus(157, 14, 160, 12, "golden", 0)
	_way(156, 12)
	_way(164, 14)
	_thing(167, 14, "pinecone")
	_foe("worm", 172, 14, -1)
	_crate(175, 14, "acorns")
	_fill(176, 8, 8, 1)
	_hang("spider", 180, 9, 3)
	_acorns(181, 14, 3)
	_exit(186, 14)
	_way(186, 14)

## Level 2b: the rope bridges between the treehouse's platforms: bridges that can be dropped through, baskets on pulleys over the open air, spiders everywhere.
func _rope_bridges() -> void:
	_begin("r3", "treehouse", 188 + 26, 20)
	_main(188)
	_spawn(3, 16)
	_way(3, 16)
	_ground(0, 16, 17)
	_thing(6, 16, "walnut")
	_crate(9, 16, "acorns")
	_foe("worm", 13, 16, -1)
	# A rope bridge: a long one-way plank over the drop.
	_shelf(17, 17, 18)
	_way(18, 16)
	_hang("spider", 22, 10, 4)
	_hang("spider", 29, 10, 4)
	_acorns(19, 15, 14)
	_way(34, 16)
	_ground(35, 52, 17)
	_way(35, 16)
	_thing(38, 16, "pinecone")
	_foe("hornet", 43, 11, -1, 4)
	_crate(46, 16)
	_foe("worm", 50, 16, -1)
	_lift(53, 17, 62, 17, 3, 4.8)
	_way(52, 16)
	_ground(65, 84, 17)
	_way(66, 16)
	_flag(67, 16)
	_crate(70, 16, "heart")
	_thing(72, 16, "walnut")
	_foe("worm", 79, 16, -1)
	_spawner("worm", 84, 16, -1, 3.8, 2)
	# Up the ladder of the lookout and along its roof.
	_shelf(85, 15, 3)
	_shelf(88, 13, 3)
	_shelf(91, 11, 3)
	_way(86, 14)
	_way(89, 12)
	_way(92, 10)
	_ground(94, 110, 9)
	_way(95, 8)
	_foe("hornet", 100, 4, 1, 4)
	_thing(98, 8, "pinecone")
	_crate(104, 8, "acorns")
	_foe("worm", 107, 8, -1)
	_way(110, 8)
	_shelf(111, 17, 16)
	_way(112, 16)
	_hang("spider", 116, 10, 4)
	_hang("spider", 122, 10, 4)
	_way(126, 16)
	_ground(127, 146, 17)
	_way(127, 16)
	_flag(129, 16)
	_thing(131, 16, "walnut")
	_foe("hornet", 136, 11, -1, 4)
	_crate(139, 16)
	_foe("worm", 143, 16, -1)
	_lift(147, 17, 156, 17, 3, 4.4)
	_way(146, 16)
	_ground(159, 187, 17)
	_way(160, 16)
	_thing(162, 16, "pinecone")
	_foe("worm", 167, 16, -1)
	# A bird box nailed high up: the burrow is its doorway, two crates or a partner's throw up.
	_fill(170, 13, 3, 1)
	_bonus(171, 12, 174, 16, "golden", 1)
	_crate(168, 16)
	_crate(169, 16, "acorns")
	_foe("hornet", 178, 11, -1, 4)
	_acorns(176, 16, 4)
	_exit(184, 16)
	_way(184, 16)

func _crow_nest() -> void:
	_begin("rb", "treehouse", 24, 14, "boss")
	_fill(0, 0, 1, 14)
	_fill(23, 0, 1, 14)
	_ground(0, 23, 12)
	_shelf(2, 9, 5)
	_shelf(17, 9, 5)
	_spawn(4, 11)
	_steel(8, 11)
	_boss("crow")
