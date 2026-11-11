extends RefCounted

## The game's whole palette: 28 colours, each named by one character so sprites can be written as rows of text. '.' is transparent.

const COLORS := {
	"0": Color("120d14"),
	"1": Color("2b1b2e"),
	"2": Color("4a2a3f"),
	"3": Color("7a3b45"),
	"4": Color("b5533c"),
	"5": Color("e07a3a"),
	"6": Color("f6b24a"),
	"7": Color("ffe58a"),
	"8": Color("fff6d6"),
	"9": Color("3a2f4f"),
	"a": Color("57486b"),
	"b": Color("817390"),
	"c": Color("b9aebf"),
	"d": Color("1d2b4a"),
	"e": Color("2f4f7f"),
	"f": Color("4f86b8"),
	"g": Color("8fd0e6"),
	"h": Color("dff6ff"),
	"i": Color("1f4a44"),
	"j": Color("2f7a62"),
	"k": Color("63b889"),
	"l": Color("6b4a36"),
	"m": Color("a37a52"),
	"n": Color("e3c59a"),
	"p": Color("c93a4a"),
	"q": Color("7b2d5a"),
	"r": Color("6fe0c0"),
	"s": Color("1a1424"),
}

static func of(key: String) -> Color:
	return COLORS.get(key, Color(0, 0, 0, 0))
