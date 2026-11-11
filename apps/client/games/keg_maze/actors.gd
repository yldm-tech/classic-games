extends RefCounted

## The moving things of Keg Burrow as plain data. Everything walks from cell to cell: `cell` is where a step began, `dir` where it is heading and `t` how far along it is (0 .. 1).

class Hero extends RefCounted:
	var cell := Vector2i.ZERO
	var dir := Vector2i.ZERO
	var t := 0.0
	var face := Vector2i(0, 1)
	## The direction pressed most recently, which wins while several are held.
	var pref := Vector2i.ZERO
	var lives := 3
	## Out of lives: waits for the next stage or a continue.
	var out := false
	## Seconds left of the knocked-out animation; the hero is off the field while it runs.
	var dead := 0.0
	var invuln := 0.0
	## Kegs that may be burning at once, reach of a blast in cells, speed level.
	var cap := 1
	var blast := 2
	var boots := 0
	var remote := false
	var shield := false
	var score := 0
	## Presentation timers kept in the simulation so that a frame only reads them.
	var act := 0.0
	var walk := 0.0

	func spot() -> Vector2i:
		return cell + dir if t >= 0.5 else cell

	func pos() -> Vector2:
		return Vector2(cell) + Vector2(dir) * t

	func in_field() -> bool:
		return not out and dead <= 0.0

class Foe extends RefCounted:
	var kind := "grub"
	var cell := Vector2i.ZERO
	var dir := Vector2i.ZERO
	var t := 0.0
	var speed := 1.0
	var hp := 1
	var max_hp := 1
	var points := 100
	## Cells along each side: 1, or 2 for a boss.
	var size := 1
	var invuln := 0.0
	## Seconds left of the death animation; a dying foe touches nothing.
	var dying := 0.0
	var anim := 0.0
	var rest := 0.0
	var charge := false
	## Boss only: which boss, seconds to the next attack, seconds left of the warning before a spit, how many attacks it has made.
	var tier := 0
	var attack := 0.0
	var tell := 0.0
	var cycle := 0

	func spot() -> Vector2i:
		return cell + dir if t >= 0.5 else cell

	func pos() -> Vector2:
		return Vector2(cell) + Vector2(dir) * t

	func alive() -> bool:
		return dying <= 0.0

	## Every cell the foe stands on.
	func cells() -> Array[Vector2i]:
		var out: Array[Vector2i] = []
		var base := spot()
		for y in size:
			for x in size:
				out.append(base + Vector2i(x, y))
		return out

class Keg extends RefCounted:
	var cell := Vector2i.ZERO
	var owner := 0
	var fuse := 2.4
	var blast := 2
	var remote := false
	## Id of the chain reaction this keg belongs to; 0 until a blast reaches it or it goes off by itself.
	var chain := 0
	var age := 0.0

class Flame extends RefCounted:
	var ttl := 0.5
	## Slot of the player whose keg made it, or -1 for a boss's fire.
	var owner := 0
	var chain := 0
	## 0 the heart of a blast, 1 a horizontal arm, 2 a vertical arm.
	var axis := 0
	## Direction index the arm ends in, or -1 for a middle piece.
	var tip := -1
