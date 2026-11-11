extends "res://games/crate_crew/builder.gd"

## Under the street: down a drain shaft ledge by ledge, along the pipe works between channels of sludge, across the sluice on floating planks, and the old crayfish in its pool. Slime clings under ledges and pipes and drops on whoever passes; the sludge itself stings.

func build(id: String) -> Dictionary:
	match id:
		"s1":
			_drain_drop()
		"s2":
			_pipe_works()
		"s3":
			_sluice_run()
		_:
			_crayfish_pool()
	return _finish()

## Level 1: down the drain. Ledges step down from side to side; under each one slime waits, on each one something to throw.
func _drain_drop() -> void:
	var ledges := 15
	var height := 8 + ledges * 5 + 6
	_begin("s1", "sewer", 24 + 26, height)
	_main(24)
	_fill(0, 0, 1, height)
	_fill(22, 0, 2, height)
	_fill(0, 0, 24, 2)
	_fill(1, 3, 16, 1)
	_spawn(3, 2)
	_crate(8, 2, "acorns")
	_way(16, 2)
	for index in ledges:
		var row := 8 + index * 5
		# Ledges hang from the walls in turn and overlap in the middle: land near the wall, cross, step off the open end.
		var left := index % 2 == 1
		var from := 1 if left else 5
		var to := 16 if left else 21
		_fill(from, row, to - from + 1, 1)
		var stand := row - 1
		_way(3 if left else 18, stand)
		_way(to if left else from, stand)
		match index % 5:
			0:
				_thing(13 if left else 9, stand, "nut")
				_foe("rat", 9 if left else 12, stand, 1 if left else -1)
				_hang("slime", 8, row + 1)
			1:
				_crate(6 if left else 15, stand, "acorns")
				_thing(12 if left else 8, stand, "can")
				_foe("frog", 9, stand, 1, 3)
			2:
				_thing(5 if left else 16, stand, "nut")
				_hazard(9 if left else 11, stand, 2)
				_acorns(8 if left else 10, stand - 2, 4)
				_hang("slime", 13 if left else 7, row + 1)
			3:
				_crate(13 if left else 8, stand, "heart" if index == 8 else "")
				_foe("rat", 7 if left else 14, stand, 1 if left else -1)
				_thing(10, stand, "can")
			_:
				_steel(6 if left else 15, stand)
				_crate(14 if left else 7, stand, "acorns")
				_foe("frog", 10, stand, -1, 3)
				_hang("slime", 11, row + 1)
		if index == 5 or index == 10:
			_flag(11 if left else 14, stand)
		if index == 9:
			_spawner("rat", 1, stand, 1, 3.6, 2)
		if index == 10:
			# A cracked brick in the shaft wall at the end of this ledge, at waist height: behind it a burrow.
			_crack(22, stand, 1, 1)
			_clear(23, stand, 1, 1)
			_bonus(23, stand, 20, stand, "golden", 0)
	var bottom := height - 3
	_ground(1, 21, bottom + 1)
	_way(4, bottom)
	_thing(8, bottom, "nut")
	_foe("frog", 14, bottom, -1, 4)
	_exit(19, bottom)
	_way(19, bottom)

## Level 2a: along the pipe works. Narrow channels of sludge cut the walkway; pipes overhead carry slime; the middle climbs over a pumping station.
func _pipe_works() -> void:
	_begin("s2", "sewer", 186 + 26, 18)
	_main(186)
	_spawn(3, 14)
	_way(3, 14)
	_ground(0, 18, 15)
	_thing(7, 14, "nut")
	_crate(9, 14, "acorns")
	_foe("rat", 15, 14, -1)
	_fill(12, 9, 8, 1)
	_hang("slime", 16, 10)
	_channel(19, 2)
	_ground(21, 40, 15)
	_way(21, 14)
	_thing(24, 14, "can")
	_foe("frog", 28, 14, -1, 3)
	_crate(31, 14)
	_fill(30, 9, 10, 1)
	_hang("slime", 34, 10)
	_hang("slime", 38, 10)
	_thing(36, 14, "nut")
	_channel(41, 2)
	_ground(43, 64, 15)
	_way(43, 14)
	_flag(44, 14)
	_foe("rat", 50, 14, -1)
	_crate(47, 14, "heart")
	_thing(53, 14, "can")
	_spawner("rat", 63, 14, -1, 3.4, 2)
	_steel(56, 14)
	_decor("valve", 59, 14)
	# The pumping station: up two steps and over its roof.
	_ground(65, 68, 13)
	_way(65, 12)
	_ground(69, 72, 11)
	_way(69, 10)
	_ground(73, 90, 9)
	_way(73, 8)
	_thing(75, 8, "nut")
	_foe("frog", 80, 8, -1, 3)
	_crate(84, 8, "acorns")
	_acorns(77, 6, 6)
	_way(90, 8)
	_ground(91, 112, 15)
	_way(92, 14)
	_foe("rat", 97, 14, -1)
	_thing(95, 14, "can")
	_fill(98, 9, 10, 1)
	_hang("slime", 101, 10)
	_hang("slime", 105, 10)
	_crate(108, 14)
	_channel(113, 2)
	_ground(115, 140, 15)
	_way(115, 14)
	_flag(117, 14)
	_thing(119, 14, "nut")
	_foe("frog", 124, 14, -1, 3)
	_crate(127, 14, "acorns")
	_foe("rat", 133, 14, -1)
	_decor("grate", 130, 10)
	_thing(136, 14, "can")
	_channel(141, 2)
	_ground(143, 185, 15)
	_way(143, 14)
	_crate(146, 14)
	_foe("rat", 151, 14, -1)
	_fill(150, 9, 12, 1)
	_hang("slime", 154, 10)
	_hang("slime", 158, 10)
	_thing(155, 14, "nut")
	# A pipe high over the floor ends in a burrow: two crates or a partner's throw.
	_fill(164, 11, 4, 1)
	_bonus(166, 10, 170, 14, "golden", 1)
	_crate(162, 14)
	_crate(163, 14, "acorns")
	_foe("frog", 172, 14, -1, 3)
	_spawner("rat", 182, 14, -1, 3.4, 2)
	_acorns(174, 14, 4)
	_exit(179, 14)
	_way(179, 14)

## A channel of sludge `width` cells wide cut into the walkway at column x: its floor is a cell lower and the sludge stings.
func _channel(x: int, width: int) -> void:
	_ground(x, x + width - 1, 16)
	_hazard(x, 15, width)
	_arch(x - 1, 14, width + 2)

## Level 2b: across the sluice. Planks float back and forth over a long pool of sludge between islands, and the gate at the end is climbed.
func _sluice_run() -> void:
	_begin("s3", "sewer", 184 + 26, 20)
	_main(184)
	_spawn(3, 16)
	_way(3, 16)
	_ground(0, 22, 17)
	_crate(7, 16, "acorns")
	_thing(9, 16, "nut")
	_foe("rat", 16, 16, -1)
	_fill(10, 11, 10, 1)
	_hang("slime", 14, 12)
	# The pool: sludge all along its bottom, islands and floating planks.
	_ground(23, 183, 19)
	_hazard(23, 18, 150)
	_lift(23, 17, 32, 17, 3, 4.6)
	_way(22, 16)
	_island(35, 44, 1)
	_lift(45, 17, 54, 17, 3, 4.6)
	_way(44, 16)
	_island(57, 68, 2)
	_way(68, 16)
	_flag(59, 16)
	_lift(69, 17, 78, 17, 3, 4.2)
	_island(81, 92, 3)
	_way(92, 16)
	# The sluice gate: climbed by its crossbars, and walked along its top.
	_ground(93, 96, 17)
	_way(93, 16)
	_shelf(96, 15, 3)
	_shelf(99, 13, 3)
	_shelf(102, 11, 3)
	_way(97, 14)
	_way(100, 12)
	_way(103, 10)
	_ground(105, 120, 9)
	_way(106, 8)
	_thing(108, 8, "nut")
	_foe("frog", 109, 8, -1, 3)
	_crate(113, 8, "heart")
	_foe("rat", 117, 8, -1)
	_way(120, 8)
	_island(121, 134, 4)
	_way(122, 16)
	_flag(123, 16)
	_lift(135, 17, 144, 17, 3, 4.2)
	_way(134, 16)
	_island(147, 183, 5)
	_way(147, 16)
	_foe("frog", 160, 16, -1, 3)
	# A floating crate cage high over the last island: the burrow is on top.
	_fill(166, 13, 3, 1)
	_bonus(167, 12, 170, 16, "golden", 2)
	_crate(163, 16)
	_crate(164, 16, "acorns")
	_spawner("rat", 182, 16, -1, 3.4, 2)
	_exit(179, 16)
	_way(179, 16)

## An island in the sludge pool from column `from` to `to`, with something on it chosen by `which`.
func _island(from: int, to: int, which: int) -> void:
	_ground(from, to, 17)
	var stand := 16
	_way(from + 1, stand)
	_way(to - 1, stand)
	match which % 5:
		1:
			_thing(from + 2, stand, "nut")
			_foe("frog", from + 6, stand, -1, 3)
			_crate(to - 2, stand, "acorns")
		2:
			_crate(from + 2, stand)
			_foe("rat", from + 7, stand, -1)
			_fill(from + 3, 11, 6, 1)
			_hang("slime", from + 5, 12)
			_thing(to - 2, stand, "can")
		3:
			_steel(from + 2, stand)
			_foe("frog", from + 7, stand, -1, 3)
			_acorns(from + 4, stand - 2, 4)
		4:
			_thing(from + 2, stand, "can")
			_foe("rat", from + 8, stand, -1)
			_crate(from + 5, stand, "acorns")
		_:
			_thing(from + 2, stand, "nut")
			_crate(from + 4, stand)
			_foe("rat", from + 12, stand, -1)
			_fill(from + 14, 11, 8, 1)
			_hang("slime", from + 16, 12)
			_hang("slime", from + 20, 12)

func _crayfish_pool() -> void:
	_begin("sb", "sewer", 24, 14, "boss")
	_fill(0, 0, 1, 14)
	_fill(23, 0, 1, 14)
	_ground(0, 23, 12)
	_shelf(2, 10, 5)
	_shelf(17, 10, 5)
	_spawn(4, 11)
	_boss("crayfish")
