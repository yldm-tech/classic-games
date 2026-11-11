extends RefCounted

## Draws Brick Bastion from the simulation's state and the presentation's particles. Everything here only reads: nothing drawn can change a run. main.gd calls draw() from its _draw.
##
## The stage is 480x270. The field (18x14 cells of 16 pixels) sits in the middle; the columns left and right of it are instrument panels that the launcher's HUD corners land on, with the game's own read-outs below them.

const Stages := preload("res://games/brick_bastion/stages.gd")
const Texts := preload("res://games/brick_bastion/texts.gd")
const Sprites := preload("res://games/brick_bastion/sprites.gd")

const STAGE := Vector2i(480, 270)
const FIELD := Vector2(96, 38)
const FIELD_SIZE := Vector2(288, 224)
const INK := Color("15121f")
const GOLD := Color("ffd24a")
const CYAN := Color("5ef2ff")
const PAPER := Color("f2f4f8")
const DIM := Color("9aa3bd")
const RED := Color("d0403c")
const SLOT_COLORS := [Color("4aa8f0"), Color("f2a83a")]
const KIND_COLORS := {"grunt": Color("d0403c"), "scout": Color("d646a0"), "gunner": Color("b4d02a"), "bulwark": Color("7458b8")}
const HEADINGS: Array[Vector2] = [Vector2.UP, Vector2.RIGHT, Vector2.DOWN, Vector2.LEFT]

# ---- static pictures ----

## The panels, the bezel round the field and the gate markers, with a hole where the field shows through.
static func frame_image() -> Image:
	var image := Image.create(STAGE.x, STAGE.y, false, Image.FORMAT_RGBA8)
	image.fill(Color("121622"))
	# Plating seams and rivets.
	for x in range(0, STAGE.x, 16):
		image.fill_rect(Rect2i(x, 0, 1, STAGE.y), Color("0c0f18"))
		image.fill_rect(Rect2i(x + 1, 0, 1, STAGE.y), Color("1a2030"))
	for y in range(0, STAGE.y, 32):
		image.fill_rect(Rect2i(0, y, STAGE.x, 1), Color("0c0f18"))
		for x in range(0, STAGE.x, 16):
			image.fill_rect(Rect2i(x + 4, y + 4, 2, 2), Color("2b3348"))
			image.fill_rect(Rect2i(x + 4, y + 4, 1, 1), Color("4a5676"))
	# Read-out wells: the HUD corners at the top, the game's own panels below.
	for well: Rect2i in [Rect2i(4, 4, 84, 72), Rect2i(4, 84, 84, 176), Rect2i(392, 4, 84, 126), Rect2i(392, 138, 84, 104), Rect2i(196, 2, 88, 30)]:
		image.fill_rect(well, Color("06080d"))
		image.fill_rect(Rect2i(well.position.x + 1, well.position.y + 1, well.size.x - 2, well.size.y - 2), Color("0b0e16"))
		image.fill_rect(Rect2i(well.position.x, well.end.y, well.size.x + 1, 1), Color("2b3348"))
		image.fill_rect(Rect2i(well.end.x, well.position.y, 1, well.size.y + 1), Color("2b3348"))
	# The bezel: dark, steel, dark, around the field.
	var field := Rect2i(int(FIELD.x), int(FIELD.y), int(FIELD_SIZE.x), int(FIELD_SIZE.y))
	image.fill_rect(field.grow(3), INK)
	image.fill_rect(field.grow(2), Color("5d6480"))
	image.fill_rect(Rect2i(field.position.x - 2, field.position.y - 2, field.size.x + 4, 1), Color("9aa3bd"))
	image.fill_rect(Rect2i(field.position.x - 2, field.position.y - 2, 1, field.size.y + 4), Color("9aa3bd"))
	image.fill_rect(Rect2i(field.position.x - 2, field.end.y + 1, field.size.x + 4, 1), Color("33364a"))
	image.fill_rect(Rect2i(field.end.x + 1, field.position.y - 2, 1, field.size.y + 4), Color("33364a"))
	image.fill_rect(field.grow(1), INK)
	# Hazard stripes on the bezel above each gate.
	for gate in [0, 8, 9, 17]:
		for x in 16:
			var color := GOLD if (x / 3) % 2 == 0 else INK
			image.fill_rect(Rect2i(field.position.x + gate * 16 + x, field.position.y - 2, 1, 1), color)
	image.fill_rect(field, Color(0, 0, 0, 0))
	return image

# ---- helpers ----

static func _disc(ci: CanvasItem, at: Vector2, radius: int, color: Color) -> void:
	for dy in range(-radius, radius + 1):
		var half := int(sqrt(float(radius * radius - dy * dy)))
		ci.draw_rect(Rect2(roundf(at.x) - half, roundf(at.y) + dy, half * 2 + 1, 1), color)

static func _ring(ci: CanvasItem, at: Vector2, radius: int, thick: int, color: Color) -> void:
	var inner := maxi(0, radius - thick)
	for dy in range(-radius, radius + 1):
		var outer_half := int(sqrt(float(radius * radius - dy * dy)))
		var inner_half := -1
		if absi(dy) < inner:
			inner_half = int(sqrt(float(inner * inner - dy * dy)))
		var y := roundf(at.y) + dy
		if inner_half < 0:
			ci.draw_rect(Rect2(roundf(at.x) - outer_half, y, outer_half * 2 + 1, 1), color)
		else:
			ci.draw_rect(Rect2(roundf(at.x) - outer_half, y, outer_half - inner_half, 1), color)
			ci.draw_rect(Rect2(roundf(at.x) + inner_half + 1, y, outer_half - inner_half, 1), color)

static func _text(ci: CanvasItem, g: Node, at: Vector2, text: String, size: int, color: Color, align: int = HORIZONTAL_ALIGNMENT_LEFT, width: float = -1.0) -> void:
	ci.draw_string_outline(g.font, at, text, align, width, size, 2, INK)
	ci.draw_string(g.font, at, text, align, width, size, color)

static func _px(units: int) -> float:
	return floorf(float(units) / 16.0)

# ---- the frame ----

static func draw(ci: CanvasItem, g: Node) -> void:
	var sim: RefCounted = g.sim
	var fx: RefCounted = g.fx
	var tex: Dictionary = g.tex
	var time: float = g.time
	ci.draw_rect(Rect2(Vector2.ZERO, Vector2(STAGE)), INK)
	ci.draw_set_transform(FIELD + fx.shake_offset)
	ci.draw_texture(g.ground_tex, Vector2.ZERO)
	for scorch: Dictionary in fx.scorches:
		_disc(ci, scorch.at, int(scorch.radius), Color(0.03, 0.02, 0.05, 0.35))
		_disc(ci, scorch.at, int(scorch.radius) / 2, Color(0.03, 0.02, 0.05, 0.3))
	_tiles(ci, sim, tex, time, false)
	_beacon(ci, sim, tex, time)
	for chip: Dictionary in sim.chips:
		if chip.t > 180 or int(time * 10.0) % 2 == 0:
			var bob := roundf(sin(time * 5.0 + float(chip.x)) * 1.2)
			ci.draw_texture(tex["chip_" + str(chip.kind)], Vector2(_px(chip.x) - 8, _px(chip.y) - 8 + bob))
			if int(time * 6.0) % 5 == 0:
				ci.draw_rect(Rect2(_px(chip.x) - 6, _px(chip.y) - 7 + bob, 2, 1), PAPER)
	for raider: Dictionary in sim.raiders:
		_raider(ci, sim, tex, time, raider)
	for rover: Dictionary in sim.rovers:
		if rover.alive and sim.active[rover.slot]:
			_rover(ci, tex, time, rover)
	_tiles(ci, sim, tex, time, true)
	for shot: Dictionary in sim.shots:
		_shot(ci, shot)
	_effects(ci, g, fx, time)
	if sim.freeze_t > 0 and sim.phase == "play":
		ci.draw_rect(Rect2(Vector2.ZERO, FIELD_SIZE), Color(0.45, 0.8, 1.0, 0.1))
	if fx.flash > 0.02:
		ci.draw_rect(Rect2(Vector2.ZERO, FIELD_SIZE), Color(fx.flash_color, fx.flash * 0.45))
	ci.draw_set_transform(Vector2.ZERO)
	ci.draw_texture(g.frame_tex, Vector2.ZERO)
	_panels(ci, g, sim, fx, tex, time)
	_banners(ci, g, sim, tex, time)

static func _tiles(ci: CanvasItem, sim: RefCounted, tex: Dictionary, time: float, cover: bool) -> void:
	var water: Texture2D = tex["water%d" % (int(time * 3.0) % 3)]
	for row in Stages.ROWS:
		for col in Stages.COLS:
			var at := Vector2(col * 16, row * 16)
			match sim.tiles[row * Stages.COLS + col]:
				Stages.T_BRICK:
					if not cover:
						ci.draw_texture(tex["brick"], at)
				Stages.T_CRACKED:
					if not cover:
						ci.draw_texture(tex["cracked"], at)
				Stages.T_PLATE:
					if not cover:
						ci.draw_texture(tex["plate"], at)
				Stages.T_FORT:
					if not cover:
						# Fortified wall flickers when it is about to turn back into brick.
						ci.draw_texture(tex["brick" if (sim.fort_t < 150 and int(time * 8.0) % 2 == 0) else "fort"], at)
				Stages.T_WATER:
					if not cover:
						ci.draw_texture(water, at)
				Stages.T_THICKET:
					if cover:
						ci.draw_texture(tex["thicket"], at + Vector2(roundf(sin(time * 1.6 + col * 0.9 + row * 1.7) * 0.6), 0))
					else:
						ci.draw_rect(Rect2(at + Vector2(1, 2), Vector2(15, 14)), Color(0.02, 0.05, 0.04, 0.45))

static func _beacon(ci: CanvasItem, sim: RefCounted, tex: Dictionary, time: float) -> void:
	var at := Vector2(Stages.CORE_COL * 16, Stages.CORE_ROW * 16)
	var name := "beacon1" if sin(time * 4.0) > 0.2 else "beacon0"
	if sim.core <= 0:
		name = "beacon_dead"
	elif sim.core_grace_t > 0 and int(time * 12.0) % 2 == 0:
		name = "beacon_hurt"
	elif sim.core == 1 and int(time * 3.0) % 2 == 0:
		name = "beacon_hurt"
	ci.draw_texture(tex[name], at)
	if sim.core > 0:
		# One lamp per point of integrity along the top of the housing.
		for index in sim.core_max:
			ci.draw_rect(Rect2(at.x + 16 - sim.core_max * 2 + index * 4, at.y + 3, 3, 2), CYAN if index < sim.core else Color("33364a"))
		var pulse := fmod(time * 0.8, 1.0)
		_ring(ci, at + Vector2(16, 16), 6 + int(pulse * 14.0), 1, Color(CYAN, 0.35 * (1.0 - pulse)))

static func _vehicle_at(vehicle: Dictionary, size: int) -> Vector2:
	var at := Vector2(_px(vehicle.x) - size / 2, _px(vehicle.y) - size / 2)
	if vehicle.recoil_t > 3:
		at -= HEADINGS[vehicle.dir]
	return at

static func _rover(ci: CanvasItem, tex: Dictionary, time: float, rover: Dictionary) -> void:
	var at := _vehicle_at(rover, 16)
	var prefix := "rover%d" % int(rover.slot)
	if rover.spawn_t > 0 and int(time * 20.0) % 2 == 0:
		ci.draw_texture(tex["%s_%d_w" % [prefix, int(rover.dir)]], at, CYAN)
	else:
		ci.draw_texture(tex["%s_%d_%d" % [prefix, int(rover.dir), (int(rover.tread) / 4) % 2]], at)
	if rover.shield_t > 0 and (rover.shield_t > 90 or int(time * 14.0) % 2 == 0):
		var centre := Vector2(_px(rover.x), _px(rover.y))
		_ring(ci, centre, 10, 1, Color(CYAN, 0.9) if int(time * 8.0) % 2 == 0 else Color(PAPER, 0.8))
		ci.draw_rect(Rect2(centre + Vector2(-7, -7).rotated(time * 3.0).round(), Vector2(2, 2)), PAPER)

static func _raider(ci: CanvasItem, sim: RefCounted, tex: Dictionary, time: float, raider: Dictionary) -> void:
	var size := 32 if raider.boss else 16
	var centre := Vector2(_px(raider.x), _px(raider.y))
	var at := _vehicle_at(raider, size)
	var kind := str(raider.kind)
	if raider.spawn_t > 0:
		# Arriving: a beam of light tightens onto the gate, then the vehicle flickers in.
		var closing := float(raider.spawn_t) / 60.0
		_ring(ci, centre, int(4 + closing * size * 0.5), 1, Color(CYAN, 0.9))
		_ring(ci, centre, int(2 + (1.0 - closing) * size * 0.4), 1, Color(PAPER, 0.7))
		if raider.spawn_t < 24 and int(time * 24.0) % 2 == 0:
			ci.draw_texture(tex["%s_%d_w" % [kind, int(raider.dir)]], at, Color(CYAN, 0.8))
		return
	if raider.boss and raider.charge_t > 0:
		# A boss charging its cross volley shows where the shells will go.
		var glow := 0.25 + 0.5 * (1.0 - float(raider.charge_t) / 45.0)
		for side in [-6, 6]:
			ci.draw_rect(Rect2(0, centre.y + side - 1, FIELD_SIZE.x, 2), Color(RED, glow * (0.5 if int(time * 20.0) % 2 == 0 else 1.0)))
			ci.draw_rect(Rect2(centre.x + side - 1, 0, 2, FIELD_SIZE.y), Color(RED, glow * (0.5 if int(time * 20.0) % 2 == 0 else 1.0)))
		_ring(ci, centre, 14 + int(float(raider.charge_t) / 3.0), 1, Color(GOLD, 0.9))
	var frame := str((int(raider.tread) / 4) % 2)
	var tint := Color.WHITE
	if raider.flash_t > 0:
		frame = "w"
	elif raider.carrier and int(time * 8.0) % 4 == 0:
		frame = "w"
		tint = GOLD
	elif sim.freeze_t > 0 or raider.stun_t > 0:
		tint = Color(0.55, 0.8, 1.0)
	elif raider.boss and raider.enraged and int(time * 10.0) % 3 == 0:
		tint = Color(1.0, 0.6, 0.5)
	ci.draw_texture(tex["%s_%d_%s" % [kind, int(raider.dir), frame]], at, tint)
	if raider.carrier:
		ci.draw_rect(Rect2(centre + Vector2(5, -8), Vector2(2, 2)), GOLD)
		ci.draw_rect(Rect2(centre + Vector2(6, -9), Vector2(1, 4)), Color(GOLD, 0.6))
	if raider.stun_t > 0 and sim.freeze_t <= 0:
		for index in 3:
			ci.draw_rect(Rect2(centre + Vector2(9, 0).rotated(time * 7.0 + index * TAU / 3.0).round(), Vector2(1, 1)), CYAN)

static func _shot(ci: CanvasItem, shot: Dictionary) -> void:
	var centre := Vector2(_px(shot.x), _px(shot.y))
	var along: Vector2 = HEADINGS[shot.dir]
	var across := Vector2(absf(along.y), absf(along.x))
	var heavy: bool = shot.power >= 3
	var head := PAPER
	var tail := CYAN if shot.team == 0 else Color("f0802a")
	if shot.team == 1 and heavy:
		tail = Color("d646a0")
	elif shot.team == 0 and heavy:
		tail = GOLD
	var half_wide := 1.5 if heavy else 1.0
	var body := Rect2(centre - across * half_wide - along.abs() * 2.0, across * half_wide * 2.0 + along.abs() * 4.0)
	ci.draw_rect(body.grow(1.0), INK)
	ci.draw_rect(body, tail)
	ci.draw_rect(Rect2(centre + along - across * 0.5 - along.abs() * 0.5, Vector2(1, 1) + across * (1.0 if heavy else 0.0)), head)
	ci.draw_rect(Rect2(centre - along * 5.0 - across * 0.5, Vector2(1, 1)), Color(tail, 0.6))

static func _effects(ci: CanvasItem, g: Node, fx: RefCounted, time: float) -> void:
	for particle: Dictionary in fx.particles:
		var fade := 1.0 - float(particle.age) / float(particle.span)
		var size := float(particle.size)
		if fade < 0.4 and size > 1.0:
			size -= 1.0
		ci.draw_rect(Rect2((particle.at as Vector2).round(), Vector2(size, size)), Color(particle.color, minf(1.0, fade * 2.0)))
	for ring: Dictionary in fx.rings:
		var progress := float(ring.age) / float(ring.span)
		_ring(ci, ring.at, maxi(1, int(float(ring.radius) * (0.25 + 0.75 * progress))), 2 if progress < 0.5 else 1, Color(ring.color, 1.0 - progress))
	for cloud: Dictionary in fx.clouds:
		for blob: Rect2 in cloud.blobs:
			ci.draw_rect(Rect2((cloud.at as Vector2).round() + blob.position, blob.size).intersection(Rect2(Vector2.ZERO, FIELD_SIZE)), Color(0.02, 0.02, 0.06, 0.13))
	for drop: Dictionary in fx.weather:
		if float(drop.blink) > 0.0 and sin(time * float(drop.blink) + (drop.at as Vector2).x) < 0.2:
			continue
		var at := (drop.at as Vector2).round()
		if at.x >= 0.0 and at.y >= 0.0 and at.x < FIELD_SIZE.x - 3.0 and at.y < FIELD_SIZE.y - 4.0:
			ci.draw_rect(Rect2(at, drop.size), drop.color)
	for popup: Dictionary in fx.popups:
		var rise := minf(float(popup.age), 0.9) * 14.0
		var words := str(popup.text)
		var size := 8
		var tint := GOLD
		if words.begins_with("chip_"):
			words = Texts.of(words, g.locale)
			size = 10 if g.locale == "zh" else 8
			tint = CYAN
		var at := (popup.at as Vector2).round() + Vector2(-60, -rise)
		at.x = clampf(at.x, -20.0, FIELD_SIZE.x - 100.0)
		_text(ci, g, at, words, size, Color(tint, clampf((float(popup.span) - float(popup.age)) * 3.0, 0.0, 1.0)), HORIZONTAL_ALIGNMENT_CENTER, 120.0)

# ---- the game's own read-outs in the side panels ----

static func _panels(ci: CanvasItem, g: Node, sim: RefCounted, fx: RefCounted, tex: Dictionary, time: float) -> void:
	var locale: String = g.locale
	var zh := locale == "zh"
	var body := 10 if zh else 8
	var info: Dictionary = sim.stage_info()
	# Left well: where we are and what is still coming.
	var left := Vector2(10, 88)
	_text(ci, g, left + Vector2(0, 10), Texts.of("sector", locale) % [sim.stage + 1, Stages.count()], body, GOLD)
	var name := str(info["name"][locale])
	if zh or name.length() <= 14:
		_text(ci, g, left + Vector2(0, 23), name, body, PAPER)
	else:
		var cut := name.find(" ")
		_text(ci, g, left + Vector2(0, 21), name.substr(0, cut), body, PAPER)
		_text(ci, g, left + Vector2(0, 31), name.substr(cut + 1), body, PAPER)
	ci.draw_rect(Rect2(left + Vector2(0, 36), Vector2(74, 1)), Color("2b3348"))
	_text(ci, g, left + Vector2(0, 49), Texts.of("reserve", locale), body, DIM)
	_text(ci, g, left + Vector2(0, 168), Texts.of("crews", locale) % sim.crews, body if zh else 7, CYAN if sim.crews > 0 else DIM)
	# One pip per raider still to arrive, in arrival order, coloured by kind; a gold dot marks a supply carrier.
	var shown := 0
	for position in range(sim.next_raider, sim.roster.size()):
		var at := left + Vector2((shown % 8) * 9, 55 + (shown / 8) * 9)
		ci.draw_rect(Rect2(at, Vector2(7, 7)), INK)
		ci.draw_rect(Rect2(at + Vector2(1, 1), Vector2(5, 5)), KIND_COLORS[sim.roster[position]])
		ci.draw_rect(Rect2(at + Vector2(3, 0), Vector2(1, 3)), DIM)
		if Stages.is_carrier(position):
			ci.draw_rect(Rect2(at + Vector2(2, 3), Vector2(3, 3)), GOLD)
		shown += 1
	if info.has("boss") and sim.boss_state != 3:
		var at := left + Vector2((shown % 8) * 9, 55 + (shown / 8) * 9)
		ci.draw_rect(Rect2(at, Vector2(16, 7)), INK)
		ci.draw_rect(Rect2(at + Vector2(1, 1), Vector2(14, 5)), RED if int(time * 4.0) % 2 == 0 else GOLD)
	# What each supply chip does, as a standing legend.
	ci.draw_rect(Rect2(left + Vector2(0, 92), Vector2(74, 1)), Color("2b3348"))
	_text(ci, g, left + Vector2(0, 105), Texts.of("supplies", locale), body, DIM)
	var legend: Array[String] = ["coil", "aegis", "stasis", "mason", "surge", "spare"]
	for index in legend.size():
		var at := left + Vector2((index % 2) * 39, 110 + (index / 2) * 19)
		ci.draw_texture(tex["chip_" + legend[index]], at)
		_text(ci, g, at + Vector2(17, 12), Texts.of("legend_" + legend[index], locale), body, PAPER)
	# Right well: each crew's firepower and bricks as pictures, then the effects that are running, each with a bar that drains.
	var right := Vector2(396, 142)
	for slot in 2:
		if not sim.active[slot]:
			continue
		var rover: Dictionary = sim.rovers[slot]
		var at := right + Vector2(0, slot * 28)
		ci.draw_texture(tex["rover%d_0_0" % slot], at, Color.WHITE if (rover.alive or rover.lives > 0) else Color(0.4, 0.4, 0.45))
		if not rover.alive and rover.lives <= 0:
			_text(ci, g, at + Vector2(20, 12), Texts.of("out", locale), body, RED)
			continue
		for index in 3:
			var lit: bool = index < rover.power
			ci.draw_rect(Rect2(at + Vector2(20 + index * 8, 1), Vector2(6, 6)), INK)
			ci.draw_rect(Rect2(at + Vector2(21 + index * 8, 2), Vector2(4, 4)), GOLD if lit else Color("33364a"))
			if lit:
				ci.draw_rect(Rect2(at + Vector2(21 + index * 8, 2), Vector2(2, 1)), PAPER)
		for index in 5:
			var have: bool = index < rover.bricks
			ci.draw_rect(Rect2(at + Vector2(20 + index * 10, 10), Vector2(8, 5)), Color("3d2226") if have else Color("1a1d2a"))
			if have:
				ci.draw_rect(Rect2(at + Vector2(20 + index * 10, 10), Vector2(7, 4)), Color("c0603a"))
				ci.draw_rect(Rect2(at + Vector2(20 + index * 10, 10), Vector2(7, 1)), Color("e89a62"))
		if rover.shield_t > 0:
			ci.draw_rect(Rect2(at + Vector2(0, 19), Vector2(roundf(72.0 * minf(1.0, float(rover.shield_t) / 600.0)), 2)), CYAN)
	var row := 0
	for effect: Array in [["stasis", sim.freeze_t, 360, "frozen"], ["mason", sim.fort_t, 900, "fortified"]]:
		if int(effect[1]) <= 0:
			continue
		var at := right + Vector2(0, 60 + row * 20)
		ci.draw_texture(tex["chip_" + str(effect[0])], at)
		_text(ci, g, at + Vector2(19, 9), Texts.of(str(effect[3]), locale), body, PAPER)
		ci.draw_rect(Rect2(at + Vector2(19, 12), Vector2(54, 3)), Color("33364a"))
		ci.draw_rect(Rect2(at + Vector2(19, 12), Vector2(roundf(54.0 * float(effect[1]) / float(effect[2])), 3)), CYAN)
		row += 1

# ---- banners over the field ----

static func _band(ci: CanvasItem, top: float, height: float, edge: Color) -> void:
	ci.draw_rect(Rect2(FIELD.x, FIELD.y + top, FIELD_SIZE.x, height), Color(0.03, 0.03, 0.07, 0.84))
	ci.draw_rect(Rect2(FIELD.x, FIELD.y + top, FIELD_SIZE.x, 1), edge)
	ci.draw_rect(Rect2(FIELD.x, FIELD.y + top + height - 1, FIELD_SIZE.x, 1), edge)
	for x in range(0, int(FIELD_SIZE.x), 8):
		ci.draw_rect(Rect2(FIELD.x + x, FIELD.y + top + 2, 4, 1), Color(edge, 0.5))
		ci.draw_rect(Rect2(FIELD.x + x, FIELD.y + top + height - 3, 4, 1), Color(edge, 0.5))

static func _centred(ci: CanvasItem, g: Node, y: float, text: String, size: int, color: Color) -> void:
	_text(ci, g, Vector2(FIELD.x, FIELD.y + y), text, size, color, HORIZONTAL_ALIGNMENT_CENTER, FIELD_SIZE.x)

static func _banners(ci: CanvasItem, g: Node, sim: RefCounted, tex: Dictionary, time: float) -> void:
	var locale: String = g.locale
	var zh := locale == "zh"
	var big := 16 if zh else 14
	var body := 10 if zh else 8
	var info: Dictionary = sim.stage_info()
	match str(sim.phase):
		"intro":
			_band(ci, 78, 58, GOLD)
			_centred(ci, g, 98, Texts.of("sector", locale) % [sim.stage + 1, Stages.count()], body, GOLD)
			_centred(ci, g, 116, str(info["name"][locale]), big, PAPER)
			_centred(ci, g, 130, Texts.of("ready", locale), body, CYAN)
		"play":
			if sim.boss_state == 1 and int(time * 5.0) % 2 == 0:
				_band(ci, 82, 50, RED)
				_centred(ci, g, 104, Texts.of("warning", locale), big, RED)
				_centred(ci, g, 120, "%s · %s" % [Texts.of(str(info["boss"]), locale), Texts.of("boss_inbound", locale)], body, PAPER)
		"cleared":
			_band(ci, 88, 38, CYAN)
			_centred(ci, g, 112, Texts.of("cleared", locale), big, CYAN)
		"tally":
			_tally(ci, g, sim, tex, time)
		"won":
			_band(ci, 74, 62, GOLD)
			_centred(ci, g, 102, Texts.of("won", locale), big + 2, GOLD)
			_centred(ci, g, 122, Texts.of("won_sub", locale), body, PAPER)
		"lost":
			_band(ci, 80, 54, RED)
			_centred(ci, g, 104, Texts.of("lost_core" if sim.core <= 0 else "lost_rovers", locale), big, RED)
			if sim.crews > 0:
				_centred(ci, g, 122, Texts.of("relief", locale), body, PAPER)

static func _tally(ci: CanvasItem, g: Node, sim: RefCounted, tex: Dictionary, time: float) -> void:
	var locale: String = g.locale
	var zh := locale == "zh"
	var body := 10 if zh else 8
	var lines: Array = sim.tally_lines
	var box := Rect2(FIELD.x + 54, FIELD.y + 14, 180, 78 + lines.size() * 18)
	ci.draw_rect(box.grow(2), INK)
	ci.draw_rect(box.grow(1), GOLD)
	ci.draw_rect(box, Color("0b0e16"))
	_text(ci, g, box.position + Vector2(0, 16), "%s · %s" % [Texts.of("sector", locale) % [sim.stage + 1, Stages.count()], Texts.of("tally", locale)], body, GOLD, HORIZONTAL_ALIGNMENT_CENTER, box.size.x)
	ci.draw_rect(Rect2(box.position + Vector2(10, 22), Vector2(box.size.x - 20, 1)), Color("2b3348"))
	var shown := int(sim.phase_t) / 26
	var y := box.position.y + 28
	for index in lines.size():
		if index >= shown:
			break
		var line: Dictionary = lines[index]
		var kind := str(line["kind"])
		var picture: Texture2D = tex[kind + "_0_0"]
		ci.draw_texture_rect(picture, Rect2(box.position.x + 14, y, 16, 16), false)
		_text(ci, g, Vector2(box.position.x + 38, y + 12), "x %d" % int(line["count"]), body, PAPER)
		_text(ci, g, Vector2(box.position.x + 60, y + 12), "%d" % int(line["points"]), body, PAPER, HORIZONTAL_ALIGNMENT_RIGHT, box.size.x - 74)
		y += 18
	y = box.position.y + 28 + lines.size() * 18
	if shown > lines.size():
		_disc(ci, Vector2(box.position.x + 22, y + 8), 6, Color("145a66"))
		_disc(ci, Vector2(box.position.x + 22, y + 8), 4, CYAN)
		_disc(ci, Vector2(box.position.x + 21, y + 7), 1, PAPER)
		_text(ci, g, Vector2(box.position.x + 38, y + 12), Texts.of("bonus", locale), body, CYAN)
		_text(ci, g, Vector2(box.position.x + 60, y + 12), "%d" % int(sim.tally_bonus), body, CYAN, HORIZONTAL_ALIGNMENT_RIGHT, box.size.x - 74)
	if shown > lines.size() + 1:
		ci.draw_rect(Rect2(box.position.x + 10, y + 19, box.size.x - 20, 1), Color("2b3348"))
		_text(ci, g, Vector2(box.position.x + 14, y + 33), Texts.of("total", locale), body, GOLD)
		_text(ci, g, Vector2(box.position.x + 60, y + 33), "%d" % int(sim.score_total), body, GOLD, HORIZONTAL_ALIGNMENT_RIGHT, box.size.x - 74)
		if int(time * 2.5) % 2 == 0:
			_text(ci, g, Vector2(box.position.x, y + 46), Texts.of("next", locale), body, DIM, HORIZONTAL_ALIGNMENT_CENTER, box.size.x)
