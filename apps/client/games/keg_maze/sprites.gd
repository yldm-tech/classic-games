extends RefCounted

## The pixel art of Keg Burrow, drawn by hand as rows of palette letters and turned into textures at run time. Nothing here comes from an image file. Each letter is one pixel; '.' is see-through. A sprite may be recoloured by swapping palette entries (the second digger, the three depths, the two bosses), and the fire is painted by a small routine instead of by hand so that it can flicker.

const PALETTE := {
	"k": "1a1420", "w": "f4efe6", "g": "b9b3c4", "d": "6d6680",
	"b": "4a2f25", "n": "7a4a2d", "t": "b97a45", "y": "f6d365", "l": "fff6b0",
	"o": "ee8a2f", "r": "d1433a", "m": "7c1f33", "p": "f2a3a0",
	"f": "7a6a86", "F": "544860", "h": "f2b233", "H": "c4841d", "s": "d1433a",
	"c": "58c7d9", "C": "2b7f9e", "v": "9a6be0", "V": "55359a",
	"e": "7fc24e", "E": "3b7a3e", "u": "4a74d8", "U": "2c468f",
	"P": "b97a45", "Q": "2a2233",
	"1": "5a4332", "2": "4c3829", "3": "6e5540", "4": "a39373", "5": "7c6d55", "6": "4a3f33", "7": "dba45c", "8": "b0733a", "9": "7a4a2d",
}

## Helmet, helmet shade and scarf of each digger.
const HERO_SWAPS := [
	{},
	{"h": "4fd1c5", "H": "2c8f8c", "s": "a06be0"},
]

## Floor (1 2 3), rock (4 5 6) and block (7 8 9) colours of the three depths.
const WORLD_SWAPS := [
	{},
	{"1": "30375a", "2": "282d4a", "3": "3f4a78", "4": "8492cf", "5": "5c68a6", "6": "343b66", "7": "a6e8f0", "8": "4aa3c7", "9": "2a5f8f"},
	{"1": "3d2629", "2": "311d21", "3": "523233", "4": "94584c", "5": "6b3d38", "6": "3a2022", "7": "ffb347", "8": "c8502f", "9": "6e2424"},
]

## The Molten Claw is the Geode Claw's sprite with a hot shell.
const BOSS_SWAPS := [
	{},
	{"g": "c8502f", "d": "7c1f33", "c": "ffb347", "C": "c4841d", "v": "f6d365", "V": "ee8a2f"},
]

## Rim colour of each item's plate.
const ITEM_RIMS := {"keg": "b97a45", "blast": "ee8a2f", "boots": "58c7d9", "remote": "d1433a", "hat": "f2b233", "heart": "f2a3a0", "clock": "f4efe6", "gem": "9a6be0"}

const HERO_DOWN := [
	"................",
	".....kkkkkk.....",
	"...kkhhhhhhkk...",
	"..khhhkyykhhhk..",
	"..khhhkllkhhhk..",
	".kHHHHHkkHHHHHk.",
	".kkkkkkkkkkkkkk.",
	"..kffkffffkffk..",
	"..kfffppppfffk..",
	"..kFffkppkffFk..",
	"...kssssssssk...",
	"..kpkttttttkpk..",
	"..kpkttyyttkpk..",
	"...kkttttttkk...",
]
const HERO_UP := [
	"................",
	".....kkkkkk.....",
	"...kkhhhhhhkk...",
	"..khhhhhhhhhhk..",
	"..khhhHHHHhhhk..",
	".kHHHHHHHHHHHHk.",
	".kkkkkkkkkkkkkk.",
	"..kffffffffffk..",
	"..kfFffffffFfk..",
	"..kFFffffffFFk..",
	"...kssssssssk...",
	"..kpkttttttkpk..",
	"..kpkttttttkpk..",
	"...kkttttttkk...",
]
const HERO_SIDE := [
	"................",
	".....kkkkkk.....",
	"...kkhhhhhhk....",
	"..khhhhhhhhyk...",
	"..khhhhhhhklk...",
	"..kHHHHHHHHHkk..",
	"..kkkkkkkkkkkkk.",
	"...kfffffkffk...",
	"...kffffffpppk..",
	"...kFffffffkk...",
	"...ksssssssk....",
	"....kttttpk.....",
	"....kttttpk.....",
	"....kttttk......",
]
const HERO_HURT := [
	"................",
	".....kkkkkk.....",
	"...kkhhhhhhkk...",
	"..khhhkyykhhhk..",
	"..khhhkllkhhhk..",
	".kHHHHHkkHHHHHk.",
	".kkkkkkkkkkkkkk.",
	"..kfwkffffkwfk..",
	"..kfffppppfffk..",
	"..kFffkkkkffFk..",
	"...kssssssssk...",
	".kpkkttttttkkpk.",
	".kk.kttyyttk.kk.",
	"....kttttttk....",
]
const HERO_CHEER := [
	"................",
	".....kkkkkk.....",
	"...kkhhhhhhkk...",
	"..khhhkyykhhhk..",
	"..khhhkllkhhhk..",
	".kHHHHHkkHHHHHk.",
	".kkkkkkkkkkkkkk.",
	"kpkffkffffkffkpk",
	"kpkfffppppfffkpk",
	".kkFffkkkkffFkk.",
	"...kssssssssk...",
	"...kkttttttkk...",
	"....kttyyttk....",
	"....kttttttk....",
]
const HERO_PLACE := [
	"................",
	"................",
	".....kkkkkk.....",
	"...kkhhhhhhkk...",
	"..khhhkyykhhhk..",
	"..khhhkllkhhhk..",
	".kHHHHHkkHHHHHk.",
	".kkkkkkkkkkkkkk.",
	"..kffkffffkffk..",
	"..kfffppppfffk..",
	"..kFffkppkffFk..",
	"...kssssssssk...",
	"...kktpkkptkk...",
	"...kkttppttkk...",
]
const LEGS_FRONT := [
	["....kFFkkFFk....", "....kkk..kkk...."],
	["....kFFk.kk.....", "....kkk........."],
	[".....kk.kFFk....", ".........kkk...."],
]
const LEGS_SIDE := [
	["....kFFkFFk.....", "....kkkkkkk....."],
	["...kFFk.kFFk....", "...kkk...kkk...."],
	[".....kFFFk......", ".....kkkkk......"],
]
const HERO_HELMET := [
	"................",
	"................",
	"................",
	"................",
	"................",
	"................",
	"................",
	"................",
	"................",
	"................",
	".....kkkkkk.....",
	"...kkhhhhhhkk...",
	"..khhhkyykhhhk..",
	".kHHHHHkkHHHHHk.",
	".kkkkkkkkkkkkkk.",
	"................",
]

const FOE_ROWS := {
	"grub_0": [
		"................",
		"................",
		".....kkkkkk.....",
		"....kyyyyyyk....",
		"...kyyyyyyyyk...",
		"..keeeeeeeeeek..",
		"..keewkeewkeek..",
		"..keewkeewkeek..",
		"..keeeeeeeeeek..",
		"..kEeeemmeeeEk..",
		"..kyyyyyyyyyyk..",
		"..kEeeeeeeeeEk..",
		"...kyyyyyyyyk...",
		"...kEEeeeeEEk...",
		"....kkkkkkkk....",
		"................",
	],
	"grub_1": [
		"................",
		"................",
		"................",
		"....kkkkkkkk....",
		"...kyyyyyyyyk...",
		".kkeeeeeeeeeekk.",
		".keeewkeewkeeek.",
		".keeewkeewkeeek.",
		".keeeeeeeeeeeek.",
		".kEeeeemmeeeeEk.",
		".kyyyyyyyyyyyyk.",
		".kEeeeeeeeeeeEk.",
		"..kyyyyyyyyyyk..",
		"..kEEEeeeeEEEk..",
		"...kkkkkkkkkk...",
		"................",
	],
	"mite_0": [
		"................",
		"................",
		"................",
		"..k..........k..",
		"...k.kkkkkk.k...",
		"....kooooook....",
		"..kkoyooooyokk..",
		".k.kowkoowkok.k.",
		"...kooooooook...",
		"..kkorrrrrrokk..",
		".k..kooooook..k.",
		"....kkkkkkkk....",
		"...k........k...",
		"..k..........k..",
		"................",
		"................",
	],
	"mite_1": [
		"................",
		"................",
		"................",
		"...k........k...",
		"...k.kkkkkk.k...",
		"....kooooook....",
		".kkkoyooooyokkk.",
		"...kowkoowkok...",
		"...kooooooook...",
		".kkkorrrrrrokkk.",
		"....kooooook....",
		"....kkkkkkkk....",
		"..k..........k..",
		".k............k.",
		"................",
		"................",
	],
	"beetle_0": [
		"................",
		"...kk......kk...",
		"..kdk......kdk..",
		"..kdkk....kkdk..",
		"...kdkkkkkkdk...",
		"....kuuuuuuk....",
		"...kurkuukruk...",
		"..kuuuuuuuuuuk..",
		".kkuvuukkuuvukk.",
		"..kuvuukkuuvuk..",
		".kkuvuukkuuvukk.",
		"..kuuvukkuvuuk..",
		"...kuuukkuuuk...",
		"....kkuuuukk....",
		"......kkkk......",
		"................",
	],
	"beetle_1": [
		"................",
		"....kk....kk....",
		"...kdk....kdk...",
		"...kdkk..kkdk...",
		"...kdkkkkkkdk...",
		"....kuuuuuuk....",
		"...kurkuukruk...",
		"..kuuuuuuuuuuk..",
		"..kuvuukkuuvuk..",
		".kkuvuukkuuvukk.",
		"..kuvuukkuuvuk..",
		".kkuuvukkuvuukk.",
		"...kuuukkuuuk...",
		"....kkuuuukk....",
		"......kkkk......",
		"................",
	],
	"wisp_0": [
		"................",
		".......kk.......",
		"......kcck......",
		".....kccwck.....",
		"....kccwwcck....",
		"...kccwwwwcck...",
		"..kcckwwwwkcck..",
		"..kcckwwwwkcck..",
		"..kccwwwwwwcck..",
		"..kCcwwkkwwcCk..",
		"..kCccwwwwccCk..",
		"..kCCccccccCCk..",
		"...kCCckkcCCk...",
		"...kCk.kk.kCk...",
		"....k......k....",
		"................",
	],
	"wisp_1": [
		"................",
		"........kk......",
		".......kcck.....",
		".....kkccwck....",
		"....kccwwcck....",
		"...kccwwwwcck...",
		"..kcckwwwwkcck..",
		"..kcckwwwwkcck..",
		"..kccwwwwwwcck..",
		"..kCcwwkkwwcCk..",
		"..kCccwwwwccCk..",
		"..kCCccccccCCk..",
		"...kCCCkkCCCk...",
		"....kCk..kCk....",
		".....k....k.....",
		"................",
	],
	"shell_0": [
		"................",
		".....v....v.....",
		"....kVk..kVk....",
		"...kkgkkkkgkk...",
		"..kggdggggdggk..",
		".kggggggdggggdk.",
		".kgdggggggggggk.",
		"kFkgggdggggdgkFk",
		"kFkddddddddddkFk",
		".kkkkkkkkkkkkkk.",
		"...kFFFFFFFFk...",
		"...kFckFFkcFk...",
		"...kFFFFFFFFk...",
		".kFk.kkkkkk.kFk.",
		".kkk........kkk.",
		"................",
	],
	"shell_1": [
		"................",
		".....v....v.....",
		"....kVk..kVk....",
		"...kkgkkkkgkk...",
		"..kggdggggdggk..",
		".kggggggdggggdk.",
		".kgdggggggggggk.",
		"..kgggdggggdgk..",
		"kFkddddddddddkFk",
		"kkkkkkkkkkkkkkkk",
		"...kFFFFFFFFk...",
		"...kFckFFkcFk...",
		"...kFFFFFFFFk...",
		"..kk.kkkkkk.kk..",
		"................",
		"................",
	],
	"shellc_0": [
		"................",
		"..........v.....",
		".........kVk....",
		"...kkkkkkkgkk...",
		"..kggkggggdggk..",
		".kgggkkgdggggdk.",
		".kgdggkkgggkggk.",
		"kFkgggdkggkkgkFk",
		"kFkdddddkddddkFk",
		".kkkkkkkkkkkkkk.",
		"...kFFFFFFFFk...",
		"...kFrkFFkrFk...",
		"...kFFFFFFFFk...",
		".kFk.kkkkkk.kFk.",
		".kkk........kkk.",
		"................",
	],
	"shellc_1": [
		"................",
		"..........v.....",
		".........kVk....",
		"...kkkkkkkgkk...",
		"..kggkggggdggk..",
		".kgggkkgdggggdk.",
		".kgdggkkgggkggk.",
		"..kgggdkggkkgk..",
		"kFkdddddkddddkFk",
		"kkkkkkkkkkkkkkkk",
		"...kFFFFFFFFk...",
		"...kFrkFFkrFk...",
		"...kFFFFFFFFk...",
		"..kk.kkkkkk.kk..",
		"................",
		"................",
	],
}

## Left half of the 32x32 boss; the right half is its mirror image.
const BOSS_HALF := [
	"................",
	"....kkk.........",
	"...kccckk.......",
	"..kccwcck...kk..",
	"..kcwcckk..kvvk.",
	".kccckk...kvVvk.",
	".kcck..k..kvVvkk",
	".kcck.kck.kVVvkv",
	".kcckkcck..kVkvv",
	".kcccccck...kkvV",
	"..kcccckkkkkkkVV",
	"...kkcckddddddkk",
	"....kkkdggggdddd",
	"....kdgggggggggd",
	"...kdgggdggggggg",
	"..kdgggggggggdgg",
	"..kdggggggkkkkgg",
	"..kdgggggkwwwwkg",
	"..kdgggggkwwrrkg",
	"..kddggggkwwrrkg",
	"..kdddggggkkkkgg",
	"...kdddggggggggk",
	"...kddddgggggkkm",
	"....kdddddggkmmw",
	"..kkkkdddddddkmm",
	".kdgkkkkddddddkk",
	"kdgk.kdkkkkkkkkk",
	"kdk.kdgk.kdgk...",
	"kk..kdk..kdk....",
	"....kk...kk.....",
	"................",
	"................",
]
## The same half with the claw snapped shut and the legs shifted, for the second frame.
const BOSS_HALF_B := [
	"................",
	"................",
	"....kkkk........",
	"...kcccck...kk..",
	"..kccwcck..kvvk.",
	"..kcwccck.kvVvk.",
	".kcccckk..kvVvkk",
	".kccckck..kVVvkv",
	".kccckcck..kVkvv",
	".kcccccck...kkvV",
	"..kcccckkkkkkkVV",
	"...kkcckddddddkk",
	"....kkkdggggdddd",
	"....kdgggggggggd",
	"...kdgggdggggggg",
	"..kdgggggggggdgg",
	"..kdggggggkkkkgg",
	"..kdgggggkwwwwkg",
	"..kdgggggkwrrwkg",
	"..kddggggkwrrwkg",
	"..kdddggggkkkkgg",
	"...kdddggggggggk",
	"...kddddgggggkkm",
	"....kdddddggkmmw",
	"..kkkkdddddddkmm",
	"..kkkkkkddddddkk",
	".kdgkkdkkkkkkkkk",
	".kdk.kdgk.kdgk..",
	".kk...kdk..kdk..",
	"......kk...kk...",
	"................",
	"................",
]

const TILE_ROWS := {
	"floor_a": [
		"1111111111111111",
		"1121111111111311",
		"1111111111111111",
		"1111113111111111",
		"1111111111121111",
		"1311111111111111",
		"1111111122111111",
		"1111111111111111",
		"1111211111111131",
		"1111111111111111",
		"1111111311111111",
		"1211111111111111",
		"1111111111112111",
		"1111131111111111",
		"1111111111111111",
		"1111111112111111",
	],
	"floor_b": [
		"1111111111111111",
		"1111111111111111",
		"1113311111111111",
		"1133331111122111",
		"1113311111222211",
		"1111111111122111",
		"1111111111111111",
		"1111111111111111",
		"1111112111111111",
		"1111122211111111",
		"1111112111113311",
		"1111111111133331",
		"1211111111113311",
		"1111111111111111",
		"1111111111111111",
		"1111111111111111",
	],
	"pillar": [
		"6444444444444446",
		"4444544444444445",
		"4445444444454445",
		"4444444444544445",
		"4444444444444445",
		"4454444444444445",
		"4444444544444445",
		"4444445444444445",
		"4444444444454445",
		"4544444444444445",
		"5555555555555555",
		"5565555555655556",
		"5655555556555556",
		"5555565555555566",
		"6555655555565566",
		"6666666666666666",
	],
	"wall": [
		"6666666666666666",
		"4444446444444464",
		"4544446445444464",
		"4444446444444464",
		"6666666666666666",
		"4464444444644444",
		"4464454444644544",
		"4464444444644444",
		"6666666666666666",
		"4444446444444464",
		"4445446444454464",
		"5555556555555565",
		"6666666666666666",
		"5565555555655555",
		"5565555555655555",
		"6666666666666666",
	],
	"rock": [
		"6666666666666666",
		"6656666666666566",
		"6566666666665666",
		"6666666566666666",
		"6666665666666666",
		"6666666666666666",
		"6666666666656666",
		"5666666666566665",
		"6666666666666666",
		"6666566666666666",
		"6665666666666666",
		"6666666665666666",
		"6666666656666666",
		"6666666666666656",
		"6566666666666566",
		"6666666666666666",
	],
}

## The block of each depth: a banded crate, a crystal-studded ore block, a slab of cracked slag.
const BLOCK_ROWS := [
	[
		"kkkkkkkkkkkkkkkk",
		"k77777777777777k",
		"k78888888888887k",
		"k7k8888888888k7k",
		"k78k88888888k87k",
		"k788k888888k887k",
		"k7888k8888k8887k",
		"k78888k88k88887k",
		"k788888kk888887k",
		"k78888k88k88887k",
		"k7888k8888k8887k",
		"k788k888888k887k",
		"k78k88888888k87k",
		"k79999999999997k",
		"k99999999999999k",
		"kkkkkkkkkkkkkkkk",
	],
	[
		".kkkkkkkkkkkkkk.",
		"k55555555555555k",
		"k5557k5555555k5k",
		"k557w7k55555k75k",
		"k55787k5555k787k",
		"k55788k555k7887k",
		"k55k99k55k79889k",
		"k555kk5555k999kk",
		"k5555555k555kk5k",
		"k55k5555k7k5555k",
		"k5k7k55k7w8k555k",
		"k5k78kk7788k555k",
		"k5k899k7889k556k",
		"k66kkk6k999k666k",
		"k66666666kk6666k",
		".kkkkkkkkkkkkkk.",
	],
	[
		".kkkkkkkkkkkkkk.",
		"k66666666666666k",
		"k655555655555556",
		"k65555k755555k5k",
		"k6555k7k5555k75k",
		"k655k78k555k785k",
		"k65k788k55k7885k",
		"k6k7889kkk78895k",
		"k6k899k555k8995k",
		"k65k9k55555k995k",
		"k655k5555555k95k",
		"k6555557k5555k5k",
		"k655555k8k55555k",
		"k66666666666666k",
		"k99999999999999k",
		".kkkkkkkkkkkkkk.",
	],
]

const KEG := [
	"................",
	"................",
	"................",
	"....kkkkkkkk....",
	"...knnttttnnk...",
	"..knttttttttnk..",
	"..kntttkktttnk..",
	"..kknttttttnkk..",
	"..kdkkkkkkkkdk..",
	"..knttnttnttnk..",
	"..knttnttnttnk..",
	"..kddddddddddk..",
	"..knttnttnttnk..",
	"..kbnnbnnbnnbk..",
	"...kkkkkkkkkk...",
	"................",
]
const BOULDER := [
	"................",
	".....kkkkkk.....",
	"...kkggggggkk...",
	"..kggggggdgggk..",
	".kgggdgggggggdk.",
	".kggggggggdgggk.",
	"kgggggdggggggddk",
	"kggdgggggggggddk",
	"kgggggggdggggddk",
	"kggggggggggdgddk",
	"kdggggdgggggdddk",
	".kdgggggggddddk.",
	".kdddgggddddddk.",
	"..kkddddddddkk..",
	"....kkkkkkkk....",
	"................",
]
const HATCH_SHUT := [
	"kkkkkkkkkkkkkkkk",
	"kddddddddddddddk",
	"kdnnnnnkknnnnndk",
	"kdnttttkkttttndk",
	"kdnttttkkttttndk",
	"kddddddkkddddddk",
	"kdnttttkkttttndk",
	"kdntttykkytttndk",
	"kdntttykkytttndk",
	"kdnttttkkttttndk",
	"kddddddkkddddddk",
	"kdnttttkkttttndk",
	"kdnttttkkttttndk",
	"kdnnnnnkknnnnndk",
	"kddddddddddddddk",
	"kkkkkkkkkkkkkkkk",
]
const HATCH_OPEN := [
	"kkkkkkkkkkkkkkkk",
	"kyyyyyyyyyyyyyyk",
	"kykkkkkkkkkkkkyk",
	"kykktkkkkkktkkyk",
	"kykkttttttttkkyk",
	"kykktkkkkkktkkyk",
	"kykktkkkkkktkkyk",
	"kykkttttttttkkyk",
	"kykktkkkkkktkkyk",
	"kykktkkkkkktkkyk",
	"kykkttttttttkkyk",
	"kykktkkkkkktkkyk",
	"kykkbkkkkkkbkkyk",
	"kykkkkkkkkkkkkyk",
	"kyyyyyyyyyyyyyyk",
	"kkkkkkkkkkkkkkkk",
]
const PLATE := [
	"................",
	"..kkkkkkkkkkkk..",
	".kPPPPPPPPPPPPk.",
	".kPQQQQQQQQQQPk.",
	".kPQQQQQQQQQQPk.",
	".kPQQQQQQQQQQPk.",
	".kPQQQQQQQQQQPk.",
	".kPQQQQQQQQQQPk.",
	".kPQQQQQQQQQQPk.",
	".kPQQQQQQQQQQPk.",
	".kPQQQQQQQQQQPk.",
	".kPQQQQQQQQQQPk.",
	".kPQQQQQQQQQQPk.",
	".kPPPPPPPPPPPPk.",
	"..kkkkkkkkkkkk..",
	"................",
]
## 10x10 pictures that go on a plate.
const ICON_ROWS := {
	"keg": [
		"..kkkkkk..",
		".kttttttk.",
		".kddddddk.",
		".kntntntk.",
		".kntntntk.",
		".kntntntk.",
		".kddddddk.",
		".kntntntk.",
		"..kkkkkk..",
		"..........",
	],
	"blast": [
		"....o.....",
		"...oo.....",
		"...oyo.o..",
		"..oyyo.oo.",
		".ooyyyooo.",
		".oyylyyyo.",
		".oyllllyo.",
		".oylwwlyo.",
		"..oylwyo..",
		"...oooo...",
	],
	"boots": [
		"..kkkk....",
		"..kcck....",
		"..kcck....",
		"..kcck....",
		"..kcckk...",
		"..kcccckk.",
		".kccccccck",
		".kCCCCCCCk",
		".kkkkkkkkk",
		"..........",
	],
	"remote": [
		".kkkkkkkk.",
		".krrrrrrk.",
		".kkkkkkkk.",
		"....kk....",
		"....kk....",
		".kkkkkkkk.",
		".kddddddk.",
		".kdyddydk.",
		".kddddddk.",
		".kkkkkkkk.",
	],
	"hat": [
		"..........",
		"...kkkk...",
		"..khhhhk..",
		".khhyyhhk.",
		".khhllhhk.",
		".khhhhhhk.",
		"kHHHHHHHHk",
		"kkkkkkkkkk",
		"..........",
		"..........",
	],
	"heart": [
		"..........",
		"..kk..kk..",
		".krrkkrrk.",
		"krwrrrrrrk",
		"krrrrrrrrk",
		"krrrrrrrrk",
		".krrrrrrk.",
		"..krrrrk..",
		"...krrk...",
		"....kk....",
	],
	"clock": [
		"...kkkk...",
		"....kk....",
		"..kkkkkk..",
		".kwwkwwwk.",
		"kwwwkwwwwk",
		"kwwwkkkwwk",
		"kwwwwwwwwk",
		".kwwwwwwk.",
		"..kkkkkk..",
		"..........",
	],
	"gem": [
		"..........",
		"..kkkkkk..",
		".kcwcccCk.",
		"kcwccccCCk",
		"kcccccCCCk",
		".kcccCCCk.",
		"..kccCCk..",
		"...kcCk...",
		"....kk....",
		"..........",
	],
}

## A 3x5 pixel face for the numbers in the side panels and the floating scores.
const GLYPHS := {
	"0": ["www", "w.w", "w.w", "w.w", "www"],
	"1": [".w.", "ww.", ".w.", ".w.", "www"],
	"2": ["www", "..w", "www", "w..", "www"],
	"3": ["www", "..w", "www", "..w", "www"],
	"4": ["w.w", "w.w", "www", "..w", "..w"],
	"5": ["www", "w..", "www", "..w", "www"],
	"6": ["www", "w..", "www", "w.w", "www"],
	"7": ["www", "..w", ".w.", ".w.", ".w."],
	"8": ["www", "w.w", "www", "w.w", "www"],
	"9": ["www", "w.w", "www", "..w", "www"],
	"x": ["...", "w.w", ".w.", "w.w", "..."],
	"P": ["ww.", "w.w", "ww.", "w..", "w.."],
	"+": ["...", ".w.", "www", ".w.", "..."],
}

const FLAME_RAMP := ["w", "l", "y", "o", "r"]
const FLAME_FRAMES := 3

## Every texture of the game: { name: ImageTexture }.
##   hero<slot>_<down|up|right|left>_<0|1|2>, hero<slot>_<hurt|cheer|place|helmet>
##   <foe>_<0|1> and <foe>_<0|1>_flash, boss<tier>_<0|1> and boss<tier>_<0|1>_flash
##   w<world>_<floor_a|floor_b|pillar|wall|rock|block>
##   keg, boulder, hatch_shut, hatch_open, item_<name>, icon_<name>, glyph_<char>
##   flame_<c|h|v|tip0..tip3>_<frame>
static func build() -> Dictionary:
	var out := {}
	for slot in HERO_SWAPS.size():
		var swap: Dictionary = HERO_SWAPS[slot]
		for frame in 3:
			out["hero%d_down_%d" % [slot, frame]] = _texture(_image(HERO_DOWN + LEGS_FRONT[frame], swap))
			out["hero%d_up_%d" % [slot, frame]] = _texture(_image(HERO_UP + LEGS_FRONT[frame], swap))
			var side := _image(HERO_SIDE + LEGS_SIDE[frame], swap)
			out["hero%d_right_%d" % [slot, frame]] = _texture(side)
			var mirrored: Image = side.duplicate()
			mirrored.flip_x()
			out["hero%d_left_%d" % [slot, frame]] = _texture(mirrored)
		out["hero%d_hurt" % slot] = _texture(_image(HERO_HURT + LEGS_FRONT[0], swap))
		out["hero%d_cheer" % slot] = _texture(_image(HERO_CHEER + LEGS_FRONT[0], swap))
		out["hero%d_place" % slot] = _texture(_image(HERO_PLACE + LEGS_FRONT[0], swap))
		out["hero%d_helmet" % slot] = _texture(_image(HERO_HELMET, swap))
	for sprite: String in FOE_ROWS:
		var image := _image(FOE_ROWS[sprite], {})
		out[sprite] = _texture(image)
		out[sprite + "_flash"] = _texture(_silhouette(image))
	for tier in BOSS_SWAPS.size():
		var halves := [BOSS_HALF, BOSS_HALF_B]
		for frame in 2:
			var image := _mirror(_image(halves[frame], BOSS_SWAPS[tier]))
			out["boss%d_%d" % [tier, frame]] = _texture(image)
			out["boss%d_%d_flash" % [tier, frame]] = _texture(_silhouette(image))
	for world in WORLD_SWAPS.size():
		for tile: String in TILE_ROWS:
			out["w%d_%s" % [world, tile]] = _texture(_image(TILE_ROWS[tile], WORLD_SWAPS[world]))
		out["w%d_block" % world] = _texture(_image(BLOCK_ROWS[world], WORLD_SWAPS[world]))
	out["keg"] = _texture(_image(KEG, {}))
	out["boulder"] = _texture(_image(BOULDER, {}))
	out["hatch_shut"] = _texture(_image(HATCH_SHUT, {}))
	out["hatch_open"] = _texture(_image(HATCH_OPEN, {}))
	for item: String in ICON_ROWS:
		var icon := _image(ICON_ROWS[item], {})
		out["icon_" + item] = _texture(icon)
		var plate := _image(PLATE, {"P": ITEM_RIMS[item]})
		plate.blend_rect(icon, Rect2i(0, 0, 10, 10), Vector2i(3, 3))
		out["item_" + item] = _texture(plate)
	for glyph: String in GLYPHS:
		out["glyph_" + glyph] = _texture(_image(GLYPHS[glyph], {}))
	for frame in FLAME_FRAMES:
		var arm := _flame("h", frame)
		var heart := _flame("c", frame)
		var tip := _flame("t", frame)
		out["flame_c_%d" % frame] = _texture(heart)
		out["flame_h_%d" % frame] = _texture(arm)
		var upright: Image = arm.duplicate()
		upright.rotate_90(CLOCKWISE)
		out["flame_v_%d" % frame] = _texture(upright)
		# The tip is painted pointing right (direction index 1); the others are turns of it.
		for d in 4:
			var turned: Image = tip.duplicate()
			for quarter in (d + 3) % 4:
				turned.rotate_90(CLOCKWISE)
			out["flame_tip%d_%d" % [d, frame]] = _texture(turned)
	return out

## Rows that are not as wide as the first row of their sprite, or use a letter the palette does not have.
static func problems() -> PackedStringArray:
	var out := PackedStringArray()
	var sheets := {
		"hero_down": HERO_DOWN, "hero_up": HERO_UP, "hero_side": HERO_SIDE, "hero_hurt": HERO_HURT, "hero_cheer": HERO_CHEER, "hero_place": HERO_PLACE, "hero_helmet": HERO_HELMET,
		"boss_half": BOSS_HALF, "boss_half_b": BOSS_HALF_B, "keg": KEG, "boulder": BOULDER, "hatch_shut": HATCH_SHUT, "hatch_open": HATCH_OPEN, "plate": PLATE,
	}
	for frame in 3:
		sheets["legs_front_%d" % frame] = LEGS_FRONT[frame]
		sheets["legs_side_%d" % frame] = LEGS_SIDE[frame]
	for sprite: String in FOE_ROWS:
		sheets[sprite] = FOE_ROWS[sprite]
	for sprite: String in TILE_ROWS:
		sheets[sprite] = TILE_ROWS[sprite]
	for world in BLOCK_ROWS.size():
		sheets["block_%d" % world] = BLOCK_ROWS[world]
	for sprite: String in ICON_ROWS:
		sheets["icon_" + sprite] = ICON_ROWS[sprite]
	for sprite: String in GLYPHS:
		sheets["glyph_" + sprite] = GLYPHS[sprite]
	var sizes := {"hero_down": Vector2i(16, 14), "hero_up": Vector2i(16, 14), "hero_side": Vector2i(16, 14), "hero_hurt": Vector2i(16, 14), "hero_cheer": Vector2i(16, 14), "hero_place": Vector2i(16, 14), "boss_half": Vector2i(16, 32), "boss_half_b": Vector2i(16, 32)}
	for sprite: String in sheets:
		var rows: Array = sheets[sprite]
		var wanted: Vector2i = sizes.get(sprite, Vector2i(str(rows[0]).length(), rows.size()))
		if sprite.begins_with("legs_"):
			wanted = Vector2i(16, 2)
		elif sprite.begins_with("icon_"):
			wanted = Vector2i(10, 10)
		elif sprite.begins_with("glyph_"):
			wanted = Vector2i(3, 5)
		elif not sizes.has(sprite):
			wanted = Vector2i(16, 16)
		if rows.size() != wanted.y:
			out.append("%s: %d rows, wanted %d" % [sprite, rows.size(), wanted.y])
		for y in rows.size():
			var row := str(rows[y])
			if row.length() != wanted.x:
				out.append("%s row %d: %d wide, wanted %d" % [sprite, y, row.length(), wanted.x])
			for x in row.length():
				if row[x] != "." and not PALETTE.has(row[x]):
					out.append("%s row %d: unknown colour '%s'" % [sprite, y, row[x]])
	return out

static func color(letter: String, swap: Dictionary = {}) -> Color:
	return Color(str(swap.get(letter, PALETTE.get(letter, "ff00ff"))))

static func _image(rows: Array, swap: Dictionary) -> Image:
	var width := str(rows[0]).length()
	var image := Image.create(width, rows.size(), false, Image.FORMAT_RGBA8)
	for y in rows.size():
		var row := str(rows[y])
		for x in mini(width, row.length()):
			if row[x] != ".":
				image.set_pixel(x, y, color(row[x], swap))
	return image

static func _texture(image: Image) -> ImageTexture:
	return ImageTexture.create_from_image(image)

## The image and its mirror image side by side.
static func _mirror(half: Image) -> Image:
	var size := half.get_size()
	var image := Image.create(size.x * 2, size.y, false, Image.FORMAT_RGBA8)
	image.blit_rect(half, Rect2i(Vector2i.ZERO, size), Vector2i.ZERO)
	var other: Image = half.duplicate()
	other.flip_x()
	image.blit_rect(other, Rect2i(Vector2i.ZERO, size), Vector2i(size.x, 0))
	return image

## The shape of a sprite in plain white, for the flash when it is hit.
static func _silhouette(image: Image) -> Image:
	var out: Image = image.duplicate()
	for y in out.get_height():
		for x in out.get_width():
			if out.get_pixel(x, y).a > 0.0:
				out.set_pixel(x, y, Color.WHITE)
	return out

## One 16x16 piece of fire: "h" an arm running left to right, "t" an arm ending on the right, "c" the heart of a blast. The colour of a pixel follows how far it is from the hot middle; the outline wobbles with `frame`.
static func _flame(piece: String, frame: int) -> Image:
	var image := Image.create(16, 16, false, Image.FORMAT_RGBA8)
	var phase := float(frame) * 2.1
	for y in 16:
		for x in 16:
			var across := absf(float(y) - 7.5)
			var along := absf(float(x) - 7.5)
			var wide := 5.6 + sin(float(x) * 1.3 + phase) * 1.1 + sin(float(x) * 0.6 + phase * 1.7) * 0.7
			var tall := 5.6 + sin(float(y) * 1.3 + phase + 1.0) * 1.1 + sin(float(y) * 0.6 + phase * 1.7) * 0.7
			var heat := 1.0
			match piece:
				"h":
					heat = across / wide
				"t":
					var shrink := pow(maxf(0.0, 1.0 - float(x) / 14.0), 0.55)
					heat = across / maxf(0.01, wide * shrink)
				"c":
					heat = minf(minf(across / wide, along / tall), Vector2(along, across).length() / 8.2)
			if heat < 1.0:
				image.set_pixel(x, y, color(FLAME_RAMP[clampi(int(heat * heat * 5.0), 0, 4)]))
	return image
