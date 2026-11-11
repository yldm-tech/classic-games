extends "res://games/crate_crew/builder.gd"

## The kitchen, seen from the countertop: a breadboard run that teaches everything, a climb up the inside of a cupboard, a dash across the stove between hot burners and pots, and the toaster.

func build(id: String) -> Dictionary:
	match id:
		"k1":
			_breadboard_run()
		"k2":
			_cupboard_climb()
		"k3":
			_stovetop_dash()
		_:
			_toaster_room()
	return _finish()

## Level 1: along the counter from the breadboard to the bread bin. Every rule is shown once on a sign where it is first needed.
func _breadboard_run() -> void:
	_begin("k1", "kitchen", 176 + 26, 18)
	_main(176)
	_spawn(3, 14)
	_ground(0, 21, 15)
	_decor("jar", 1, 14)
	_hint(5, 14, "hint_move")
	_crate(10, 14, "acorns")
	_thing(12, 14, "apple")
	_hint(11, 14, "hint_lift")
	_foe("ant", 18, 14)
	_arch(21, 14, 4)
	_way(20, 14)
	# A short gap, then the first throws.
	_ground(24, 49, 15)
	_way(25, 14)
	_hint(27, 14, "hint_throw")
	_crate(28, 14)
	_thing(30, 14, "apple")
	_foe("ant", 33, 14)
	_ground(36, 42, 13)
	_way(37, 12)
	_crate(38, 12, "acorns")
	_foe("shaker", 41, 12, -1)
	_way(43, 14)
	_hint(45, 14, "hint_up")
	_crate(44, 14)
	_crate(46, 14, "acorns")
	_foe("fly", 48, 9, -1, 3)
	_decor("mug", 47, 14)
	# Up the steps of the bread board.
	_ground(50, 55, 15)
	_ground(56, 62, 13)
	_ground(63, 70, 11)
	_acorns(57, 12, 5)
	_way(56, 12)
	_way(64, 10)
	_thing(65, 10, "apple")
	_foe("ant", 68, 10)
	_ground(71, 89, 15)
	_way(72, 14)
	_flag(73, 14)
	_hint(76, 14, "hint_hide")
	_steel(78, 14)
	_crate(80, 14)
	_crate(82, 14, "acorns")
	_spawner("ant", 88, 14, -1, 3.0, 2)
	_ground(90, 92, 13)
	_way(90, 12)
	# Over the gap to the knife block shelf.
	_ground(95, 124, 15)
	_way(96, 14)
	_shelf(97, 13, 5)
	_acorns(97, 12, 5)
	_foe("fly", 104, 9, 1, 4)
	_crate(106, 14)
	_crate(107, 14, "heart")
	_foe("shaker", 110, 14, -1)
	# A slab too high to jump to: a crate set down underneath is the step up.
	_hint(111, 14, "hint_stack")
	_fill(113, 12, 5, 1)
	_acorns(113, 11, 4)
	_pickup("bag", 117, 11)
	_crate(119, 14)
	_way(122, 14)
	_ground(127, 175, 15)
	_way(127, 14)
	_flag(129, 14)
	_hint(131, 14, "hint_buddy")
	_crate(134, 14)
	_thing(136, 14, "apple")
	_foe("ant", 140, 14)
	_ground(143, 150, 13)
	_way(143, 12)
	_foe("shaker", 149, 12, -1)
	_way(151, 14)
	_crate(152, 14)
	_foe("fly", 154, 9, -1, 3)
	# The bread bin: its front panel is cracked, and behind it a burrow leads to a hoard.
	_ground(158, 165, 13)
	_crack(158, 14, 1, 1)
	_clear(159, 14, 2, 1)
	_bonus(159, 14, 162, 12, "golden", 0)
	_way(158, 12)
	_way(166, 14)
	_acorns(167, 14, 3)
	_decor("jar", 170, 14)
	_exit(173, 14)
	_way(173, 14)

## Level 2a: up the inside of a tall cupboard, shelf by shelf, past the ants on every board and the flies between them.
func _cupboard_climb() -> void:
	_begin("k2", "kitchen", 24 + 26, 80)
	_main(24)
	_fill(0, 0, 1, 80)
	_fill(0, 0, 24, 2)
	_ground(0, 23, 78)
	_spawn(4, 77)
	_way(4, 77)
	_crate(8, 77)
	_thing(10, 77, "apple")
	_foe("ant", 16, 77, -1)
	_decor("jar", 20, 77)
	var columns := [2, 9, 16, 9]
	var row := 76
	var board := 0
	var count := 0
	while row > 6:
		if row in [64, 52, 40, 28, 16]:
			_board(row, board)
			board += 1
			row -= 2
			continue
		var left: int = columns[count % columns.size()]
		count += 1
		_shelf(left, row, 6)
		_way(left + 2, row - 1)
		if count % 3 == 0:
			_thing(left + 3, row - 1, "apple")
		elif count % 3 == 1:
			_acorns(left + 1, row - 1, 3)
		else:
			_crate(left + 4, row - 1, "acorns" if count % 2 == 0 else "")
		if count % 4 == 2:
			_foe("fly", 12, row - 3, 1 if left < 9 else -1, 4)
		row -= 2
	# The top shelf of the cupboard and the way out through the gap under its door.
	_shelf(1, 6, 23)
	_way(12, 5)
	_crate(6, 5, "acorns")
	_foe("ant", 16, 5, -1)
	_exit(21, 5)
	_way(21, 5)

## A board across the whole cupboard with something to fight on it. `which` picks what.
func _board(row: int, which: int) -> void:
	_shelf(1, row, 23)
	var stand := row - 1
	_way(12, stand)
	match which:
		0:
			_crate(3, stand, "acorns")
			_thing(5, stand, "apple")
			_foe("ant", 14, stand, -1)
			_foe("ant", 20, stand, -1)
			_flag(11, stand)
		1:
			_steel(4, stand)
			_foe("shaker", 21, stand, -1)
			_crate(8, stand)
			_acorns(13, stand, 4)
			# A ledge high on the left wall, out of reach without a step: the cupboard's secret.
			_fill(1, row - 4, 3, 1)
			_bonus(2, row - 5, 4, stand, "golden", 1)
			_crate(6, stand)
		2:
			_spawner("ant", 22, stand, -1, 3.2, 2)
			_crate(4, stand, "heart")
			_thing(6, stand, "apple")
			_flag(10, stand)
		3:
			_foe("shaker", 3, stand, 1)
			_crate(10, stand)
			_crate(11, stand, "acorns")
			_foe("ant", 18, stand, -1)
		_:
			_crate(5, stand, "bag")
			_foe("ant", 9, stand, 1)
			_foe("shaker", 20, stand, -1)

## Level 2b: across the stove. Burners glow between the pots, and in the middle a tower of pans is climbed to the cooker hood and left at the far end.
func _stovetop_dash() -> void:
	_begin("k3", "kitchen", 184 + 26, 22)
	_main(184)
	_spawn(3, 18)
	_way(3, 18)
	_ground(0, 26, 19)
	_crate(7, 18)
	_thing(9, 18, "apple")
	_foe("ant", 12, 18)
	_hazard(15, 18, 2)
	_arch(14, 17, 4)
	_way(18, 18)
	_steel(19, 18)
	_foe("shaker", 25, 18, -1)
	_crate(22, 18, "acorns")
	_ground(27, 34, 17)
	_way(27, 16)
	_foe("fly", 31, 13, -1, 3)
	_ground(35, 60, 19)
	_way(36, 18)
	_hazard(38, 18, 2)
	_crate(41, 18)
	_steel(43, 18)
	_hazard(45, 18, 2)
	_foe("ant", 49, 18)
	_thing(51, 18, "apple")
	_hazard(53, 18, 2)
	_crate(56, 18, "heart")
	_flag(58, 18)
	_way(58, 18)
	# The tower of pans: shelves up to the hood.
	_ground(61, 70, 19)
	_shelf(63, 17, 4)
	_shelf(67, 15, 4)
	_shelf(63, 13, 4)
	_shelf(67, 11, 4)
	_way(64, 16)
	_way(68, 14)
	_way(64, 12)
	_way(68, 10)
	_foe("fly", 66, 12, 1, 3)
	_acorns(63, 12, 4)
	_ground(71, 102, 9)
	_way(72, 8)
	_crate(74, 8)
	_foe("ant", 79, 8)
	_hazard(82, 8, 2)
	_steel(86, 8)
	_foe("shaker", 92, 8, -1)
	_thing(89, 8, "apple")
	_crate(96, 8, "acorns")
	_foe("fly", 98, 4, -1, 3)
	_way(101, 8)
	# Down from the hood onto the back of the stove.
	_ground(103, 140, 19)
	_way(104, 18)
	_flag(106, 18)
	_spawner("ant", 118, 18, -1, 3.0, 2)
	_crate(109, 18)
	_crate(110, 18, "acorns")
	_hazard(113, 18, 2)
	_ground(119, 124, 17)
	_way(119, 16)
	_foe("shaker", 123, 16, -1)
	_way(126, 18)
	_steel(127, 18)
	_hazard(130, 18, 2)
	_foe("fly", 134, 14, -1, 4)
	_thing(136, 18, "apple")
	_ground(143, 183, 19)
	_way(143, 18)
	_crate(146, 18)
	_foe("ant", 150, 18)
	_hazard(153, 18, 2)
	_crate(157, 18)
	# A pot lid hangs high over the floor with a burrow on it: two crates, or a partner thrown up, get a squirrel there.
	_fill(160, 15, 3, 1)
	_bonus(161, 14, 165, 18, "golden", 2)
	_crate(158, 18, "acorns")
	_way(164, 18)
	_foe("shaker", 170, 18, -1)
	_foe("ant", 174, 18)
	_hazard(167, 18, 1)
	_acorns(176, 18, 3)
	_exit(180, 18)
	_way(180, 18)

## The toaster's corner of the counter.
func _toaster_room() -> void:
	_begin("kb", "kitchen", 24, 14, "boss")
	_fill(0, 0, 1, 14)
	_fill(23, 0, 1, 14)
	_ground(0, 23, 12)
	_shelf(2, 9, 5)
	_shelf(17, 9, 5)
	_spawn(4, 11)
	_steel(8, 11)
	_boss("toaster")
