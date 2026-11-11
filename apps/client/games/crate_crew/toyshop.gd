extends "res://games/crate_crew/builder.gd"

## The toy shop after closing time, seen from the shelves: an alley between towers of building blocks, a climb up the tall shelf by the window, a table where toy trains carry the squirrels over the gaps, and the big wind-up robot. Toy blocks do not break: thrown, they drop and can be thrown again.

func build(id: String) -> Dictionary:
	match id:
		"t1":
			_block_alley()
		"t2":
			_shelf_tower()
		"t3":
			_train_table()
		_:
			_robot_room()
	return _finish()

## Level 1: between towers of building blocks. Wind-up mice dash along the floor, boxes spring open, a biplane patrols overhead.
func _block_alley() -> void:
	_begin("t1", "toyshop", 188 + 26, 18)
	_main(188)
	_spawn(3, 14)
	_way(3, 14)
	_ground(0, 23, 15)
	_thing(7, 14, "block")
	_thing(8, 14, "block")
	_thing(8, 13, "block")
	_foe("mouse", 16, 14, -1)
	_decor("top", 20, 14)
	_acorns(11, 12, 4)
	# The first tower, climbed by a step.
	_ground(24, 27, 13)
	_way(24, 12)
	_ground(28, 31, 11)
	_way(28, 10)
	_crate(29, 10, "acorns")
	_ground(32, 52, 15)
	_way(33, 14)
	_foe("jack", 38, 14, -1)
	_thing(35, 14, "block")
	_crate(42, 14)
	_foe("plane", 46, 9, -1, 5)
	_thing(48, 14, "block")
	_crate(49, 14, "heart")
	_arch(52, 14, 4)
	_ground(55, 80, 15)
	_way(56, 14)
	_flag(57, 14)
	_spawner("mouse", 79, 14, -1, 3.6, 2)
	_shelf(60, 13, 6)
	_acorns(60, 12, 6)
	_thing(62, 14, "block")
	_steel(64, 14)
	_crate(67, 14, "acorns")
	_foe("jack", 71, 14, -1)
	_thing(74, 14, "block")
	_ground(81, 84, 13)
	_way(81, 12)
	_ground(85, 88, 11)
	_way(85, 10)
	_foe("mouse", 87, 10, -1)
	_crate(86, 10)
	# A gap between two tables, and a stack of blocks on the far side.
	_ground(91, 120, 13)
	_way(91, 12)
	_thing(94, 12, "block")
	_thing(95, 12, "block")
	_thing(94, 11, "block")
	_foe("plane", 100, 7, 1, 5)
	_foe("jack", 104, 12, -1)
	_crate(108, 12, "acorns")
	_decor("bear", 112, 12)
	_foe("mouse", 116, 12, -1)
	_ground(121, 150, 15)
	_way(121, 14)
	_flag(123, 14)
	_hint(125, 14, "hint_stomp")
	_foe("jack", 129, 14, -1)
	_thing(127, 14, "block")
	_crate(133, 14)
	_foe("plane", 136, 9, -1, 4)
	_thing(139, 14, "block")
	_foe("mouse", 145, 14, -1)
	_crate(142, 14, "acorns")
	# The last tower has a cracked block low on its side; behind it a burrow.
	_ground(151, 158, 13)
	_crack(151, 14, 1, 1)
	_clear(152, 14, 2, 1)
	_bonus(152, 14, 155, 12, "golden", 1)
	_way(151, 12)
	_ground(159, 187, 15)
	_way(159, 14)
	_thing(162, 14, "block")
	_crate(163, 14)
	_foe("jack", 167, 14, -1)
	_foe("plane", 172, 9, -1, 4)
	_spawner("mouse", 180, 14, -1, 3.6, 2)
	_acorns(170, 14, 4)
	_exit(184, 14)
	_way(184, 14)

## Level 2a: up the tall shelf by the shop window, board by board, with a toy lift halfway.
func _shelf_tower() -> void:
	_begin("t2", "toyshop", 24 + 26, 84)
	_main(24)
	_fill(0, 0, 1, 84)
	_fill(0, 0, 24, 2)
	_ground(0, 23, 82)
	_spawn(4, 81)
	_way(4, 81)
	_thing(8, 81, "block")
	_crate(10, 81, "acorns")
	_foe("mouse", 18, 81, -1)
	var columns := [3, 10, 16, 10]
	var row := 80
	var board := 0
	var count := 0
	while row > 6:
		if row in [70, 58, 46, 34, 22]:
			_toy_board(row, board)
			board += 1
			row -= 2
			continue
		var left: int = columns[count % columns.size()]
		count += 1
		_shelf(left, row, 6)
		_way(left + 2, row - 1)
		if count % 2 == 0:
			_thing(left + 3, row - 1, "block")
		else:
			_acorns(left + 1, row - 1, 3)
		if count % 4 == 2:
			_foe("plane", 12, row - 3, 1 if left < 10 else -1, 5)
		row -= 2
	_shelf(1, 6, 23)
	_way(12, 5)
	_foe("jack", 7, 5, 1)
	_crate(15, 5, "acorns")
	_exit(21, 5)
	_way(21, 5)

func _toy_board(row: int, which: int) -> void:
	_shelf(1, row, 23)
	var stand := row - 1
	_way(12, stand)
	match which:
		0:
			_thing(3, stand, "block")
			_crate(5, stand)
			_foe("jack", 16, stand, -1)
			_foe("mouse", 21, stand, -1)
			_flag(11, stand)
		1:
			_steel(4, stand)
			_thing(7, stand, "block")
			_foe("jack", 18, stand, -1)
			_acorns(12, stand, 4)
			# A ledge up on the left with a burrow, two crates high.
			_fill(1, row - 4, 3, 1)
			_bonus(2, row - 5, 4, stand, "golden", 0)
			_crate(9, stand)
		2:
			_spawner("mouse", 22, stand, -1, 3.4, 2)
			_crate(4, stand, "heart")
			_thing(6, stand, "block")
			_flag(10, stand)
		3:
			_foe("jack", 3, stand, 1)
			_thing(10, stand, "block")
			_crate(11, stand, "acorns")
			_foe("mouse", 19, stand, -1)
		_:
			_crate(5, stand, "bag")
			_thing(7, stand, "block")
			_foe("jack", 17, stand, -1)

## Level 2b: across the train table. Toy carriages run on rails between the islands of track, and a pile of picture books in the middle is climbed and jumped down.
func _train_table() -> void:
	_begin("t3", "toyshop", 190 + 26, 20)
	_main(190)
	_spawn(3, 16)
	_way(3, 16)
	_ground(0, 20, 17)
	_thing(6, 16, "block")
	_crate(8, 16, "acorns")
	_foe("mouse", 15, 16, -1)
	_decor("top", 18, 16)
	# The first train: a carriage that shuttles across the first gap.
	_lift(21, 17, 32, 17, 3, 5.0)
	_way(20, 16)
	_acorns(23, 14, 6)
	_ground(35, 60, 17)
	_way(36, 16)
	_foe("jack", 41, 16, -1)
	_thing(38, 16, "block")
	_crate(45, 16)
	_foe("plane", 49, 11, -1, 4)
	_thing(52, 16, "block")
	_foe("mouse", 57, 16, -1)
	_lift(61, 17, 72, 17, 3, 5.0)
	_way(60, 16)
	_ground(75, 88, 17)
	_way(76, 16)
	_flag(77, 16)
	_crate(80, 16, "heart")
	_thing(82, 16, "block")
	# The pile of books.
	_ground(89, 92, 15)
	_way(89, 14)
	_ground(93, 96, 13)
	_way(93, 12)
	_ground(97, 100, 11)
	_way(97, 10)
	_ground(101, 112, 9)
	_way(101, 8)
	_foe("jack", 106, 8, -1)
	_thing(103, 8, "block")
	_crate(109, 8, "acorns")
	_foe("plane", 107, 4, 1, 4)
	_way(112, 8)
	_ground(113, 140, 17)
	_way(114, 16)
	_spawner("mouse", 139, 16, -1, 3.4, 2)
	_thing(117, 16, "block")
	_steel(120, 16)
	_crate(122, 16)
	_foe("jack", 126, 16, -1)
	_thing(130, 16, "block")
	_foe("plane", 133, 11, -1, 4)
	_crate(135, 16, "acorns")
	_lift(141, 17, 152, 17, 3, 4.6)
	_way(140, 16)
	_ground(155, 189, 17)
	_way(156, 16)
	_flag(157, 16)
	_foe("mouse", 162, 16, -1)
	_thing(160, 16, "block")
	_crate(165, 16)
	# A high signal box over the line, with a burrow on its roof: reached by a partner's throw or two crates.
	_fill(168, 13, 3, 1)
	_bonus(169, 12, 172, 16, "golden", 2)
	_crate(166, 16)
	_foe("jack", 175, 16, -1)
	_thing(177, 16, "block")
	_foe("plane", 180, 11, -1, 4)
	_acorns(178, 16, 4)
	_exit(186, 16)
	_way(186, 16)

func _robot_room() -> void:
	_begin("tb", "toyshop", 24, 14, "boss")
	_fill(0, 0, 1, 14)
	_fill(23, 0, 1, 14)
	_ground(0, 23, 12)
	_shelf(2, 9, 5)
	_shelf(17, 9, 5)
	_spawn(4, 11)
	_steel(9, 11)
	_boss("robot")
