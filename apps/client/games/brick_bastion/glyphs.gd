extends RefCounted

## The pixel lettering of Brick Bastion: capitals, digits and a little punctuation, five pixels wide and seven tall, drawn for this game. The system font serves the Chinese text; at this stage's 480x270 pixels its Latin letters and digits come out soft or broken, so everything that has a glyph here is drawn from this table instead and stays one crisp square per pixel.
##
## Small letters are drawn as capitals, except "x", which is the small cross used for counts ("x3"); the multiplication sign shares it and the middle dot has a glyph of its own.

const WIDTH := 5
const HEIGHT := 7
## A glyph's cell in the atlas: the glyph with one pixel of margin all round, which is where its outline goes.
const CELL_W := WIDTH + 2
const CELL_H := HEIGHT + 2
## How far the pen moves after a glyph, and after a space.
const ADVANCE := 6
const SPACE := 4

const ROWS := {
	"A": [".###.", "#...#", "#...#", "#####", "#...#", "#...#", "#...#"],
	"B": ["####.", "#...#", "#...#", "####.", "#...#", "#...#", "####."],
	"C": [".###.", "#...#", "#....", "#....", "#....", "#...#", ".###."],
	"D": ["####.", "#...#", "#...#", "#...#", "#...#", "#...#", "####."],
	"E": ["#####", "#....", "#....", "####.", "#....", "#....", "#####"],
	"F": ["#####", "#....", "#....", "####.", "#....", "#....", "#...."],
	"G": [".###.", "#...#", "#....", "#.###", "#...#", "#...#", ".###."],
	"H": ["#...#", "#...#", "#...#", "#####", "#...#", "#...#", "#...#"],
	"I": [".###.", "..#..", "..#..", "..#..", "..#..", "..#..", ".###."],
	"J": ["..###", "...#.", "...#.", "...#.", "...#.", "#..#.", ".##.."],
	"K": ["#...#", "#..#.", "#.#..", "##...", "#.#..", "#..#.", "#...#"],
	"L": ["#....", "#....", "#....", "#....", "#....", "#....", "#####"],
	"M": ["#...#", "##.##", "#.#.#", "#.#.#", "#...#", "#...#", "#...#"],
	"N": ["#...#", "##..#", "#.#.#", "#.#.#", "#..##", "#...#", "#...#"],
	"O": [".###.", "#...#", "#...#", "#...#", "#...#", "#...#", ".###."],
	"P": ["####.", "#...#", "#...#", "####.", "#....", "#....", "#...."],
	"Q": [".###.", "#...#", "#...#", "#...#", "#.#.#", "#..#.", ".##.#"],
	"R": ["####.", "#...#", "#...#", "####.", "#.#..", "#..#.", "#...#"],
	"S": [".####", "#....", "#....", ".###.", "....#", "....#", "####."],
	"T": ["#####", "..#..", "..#..", "..#..", "..#..", "..#..", "..#.."],
	"U": ["#...#", "#...#", "#...#", "#...#", "#...#", "#...#", ".###."],
	"V": ["#...#", "#...#", "#...#", "#...#", "#...#", ".#.#.", "..#.."],
	"W": ["#...#", "#...#", "#...#", "#.#.#", "#.#.#", "##.##", "#...#"],
	"X": ["#...#", "#...#", ".#.#.", "..#..", ".#.#.", "#...#", "#...#"],
	"Y": ["#...#", "#...#", ".#.#.", "..#..", "..#..", "..#..", "..#.."],
	"Z": ["#####", "....#", "...#.", "..#..", ".#...", "#....", "#####"],
	"0": [".###.", "#...#", "#..##", "#.#.#", "##..#", "#...#", ".###."],
	"1": ["..#..", ".##..", "..#..", "..#..", "..#..", "..#..", ".###."],
	"2": [".###.", "#...#", "....#", "...#.", "..#..", ".#...", "#####"],
	"3": ["####.", "....#", "....#", ".###.", "....#", "....#", "####."],
	"4": ["...#.", "..##.", ".#.#.", "#..#.", "#####", "...#.", "...#."],
	"5": ["#####", "#....", "####.", "....#", "....#", "#...#", ".###."],
	"6": [".###.", "#....", "#....", "####.", "#...#", "#...#", ".###."],
	"7": ["#####", "....#", "...#.", "..#..", "..#..", "..#..", "..#.."],
	"8": [".###.", "#...#", "#...#", ".###.", "#...#", "#...#", ".###."],
	"9": [".###.", "#...#", "#...#", ".####", "....#", "....#", ".###."],
	"/": ["....#", "....#", "...#.", "..#..", ".#...", "#....", "#...."],
	"+": [".....", "..#..", "..#..", "#####", "..#..", "..#..", "....."],
	"-": [".....", ".....", ".....", "#####", ".....", ".....", "....."],
	".": [".....", ".....", ".....", ".....", ".....", ".##..", ".##.."],
	",": [".....", ".....", ".....", ".....", ".##..", ".##..", ".#..."],
	":": [".....", ".##..", ".##..", ".....", ".##..", ".##..", "....."],
	"!": ["..#..", "..#..", "..#..", "..#..", "..#..", ".....", "..#.."],
	"?": [".###.", "#...#", "....#", "...#.", "..#..", ".....", "..#.."],
	"'": ["..#..", "..#..", ".....", ".....", ".....", ".....", "....."],
	"%": ["##..#", "##.#.", "...#.", "..#..", ".#...", ".#.##", "#..##"],
	"x": [".....", ".....", "#...#", ".#.#.", "..#..", ".#.#.", "#...#"],
	"·": [".....", ".....", ".##..", ".##..", ".....", ".....", "....."],
}

## The glyph a character is drawn with: "" when the system font must draw it, " " for a space.
static func key_of(letter: String) -> String:
	if letter == " ":
		return " "
	if letter == "x" or letter == "×":
		return "x"
	var upper := letter.to_upper()
	return upper if ROWS.has(upper) else ""

## Split a text into runs that alternate between this lettering and the system font. Each run is [pixel: bool, text: String]; in a pixel run every character is already the key of its glyph (or a space).
static func runs(text: String) -> Array:
	var out: Array = []
	var current := ""
	var current_pixel := true
	for index in text.length():
		var letter := text.substr(index, 1)
		var key := key_of(letter)
		var pixel := key != ""
		if index > 0 and pixel != current_pixel:
			out.append([current_pixel, current])
			current = ""
		current_pixel = pixel
		current += key if pixel else letter
	if current != "":
		out.append([current_pixel, current])
	return out

## How far the pen moves over a pixel run at a whole-number scale, the gap after its last glyph included.
static func advance_of(run: String, scale: int) -> int:
	var width := 0
	for index in run.length():
		width += SPACE if run.substr(index, 1) == " " else ADVANCE
	return width * scale

## Column of a glyph in the atlas, in arrival order of the table.
static func columns() -> Dictionary:
	var out := {}
	var column := 0
	for key: String in ROWS:
		out[key] = column
		column += 1
	return out

## The two atlas pictures, white on clear: "glyph" holds the letters, "outline" each letter grown by one pixel in every direction, to be drawn underneath in a dark colour.
static func images() -> Dictionary:
	var glyph := Image.create(ROWS.size() * CELL_W, CELL_H, false, Image.FORMAT_RGBA8)
	var outline := Image.create(ROWS.size() * CELL_W, CELL_H, false, Image.FORMAT_RGBA8)
	var column := 0
	for key: String in ROWS:
		var rows: Array = ROWS[key]
		for y in HEIGHT:
			for x in WIDTH:
				if str(rows[y]).substr(x, 1) != "#":
					continue
				glyph.set_pixel(column * CELL_W + 1 + x, 1 + y, Color.WHITE)
				for dy in [-1, 0, 1]:
					for dx in [-1, 0, 1]:
						outline.set_pixel(column * CELL_W + 1 + x + dx, 1 + y + dy, Color.WHITE)
		column += 1
	return {"glyph": glyph, "outline": outline}

## Problems of the table, one line each: a glyph of the wrong size or with a stray letter in it.
static func problems() -> PackedStringArray:
	var out := PackedStringArray()
	for key: String in ROWS:
		var rows: Array = ROWS[key]
		if rows.size() != HEIGHT:
			out.append("glyph %s: %d rows, wanted %d" % [key, rows.size(), HEIGHT])
			continue
		for row: String in rows:
			if row.length() != WIDTH or row.replace("#", "").replace(".", "") != "":
				out.append("glyph %s: bad row '%s'" % [key, row])
	return out

## The characters of a text that neither this table nor a Chinese font can be expected to draw well: Latin letters, digits and ASCII punctuation without a glyph.
static func missing(text: String) -> String:
	var out := ""
	for index in text.length():
		var letter := text.substr(index, 1)
		if letter.unicode_at(0) < 128 and key_of(letter) == "" and not out.contains(letter):
			out += letter
	return out
