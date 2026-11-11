class_name GameRng
extends RefCounted

## A tiny deterministic random number generator (xorshift32) for game logic. The same seed always produces the same sequence on every platform, which Godot's global randf()/randi() do not promise across runs, so a test can replay a run exactly. Use the instance GameModule hands out as `rng`; make more with GameRng.new(seed) when two systems must not disturb each other's sequence.

var _state := 1

func _init(seed_value: int = 1) -> void:
	reseed(seed_value)

## Restart the sequence. Any integer is a valid seed; it is scrambled first so that small or similar seeds still give unrelated sequences.
func reseed(seed_value: int) -> void:
	var mixed := (seed_value ^ 0x9E3779B9) & 0xFFFFFFFF
	mixed = ((mixed ^ (mixed >> 16)) * 0x45D9F3B) & 0xFFFFFFFF
	mixed = ((mixed ^ (mixed >> 16)) * 0x45D9F3B) & 0xFFFFFFFF
	mixed = (mixed ^ (mixed >> 16)) & 0xFFFFFFFF
	_state = mixed if mixed != 0 else 0x6D2B79F5

## The generator's whole state, for saving and restoring a sequence position.
func state() -> int:
	return _state

func restore(saved_state: int) -> void:
	_state = (saved_state & 0xFFFFFFFF) if (saved_state & 0xFFFFFFFF) != 0 else 0x6D2B79F5

## The next raw value, 0 .. 4294967295.
func next_u32() -> int:
	var x := _state
	x = (x ^ (x << 13)) & 0xFFFFFFFF
	x = x ^ (x >> 17)
	x = (x ^ (x << 5)) & 0xFFFFFFFF
	_state = x
	return x

## A float in [0, 1).
func unit() -> float:
	return float(next_u32()) / 4294967296.0

## An integer in [low, high], both ends included.
func int_range(low: int, high: int) -> int:
	if high <= low:
		return low
	return low + int(next_u32() % (high - low + 1))

## A float in [low, high).
func float_range(low: float, high: float) -> float:
	return low + (high - low) * unit()

## True with the given probability (0 never, 1 always).
func chance(probability: float) -> bool:
	return unit() < probability

## One element of a non-empty array; null for an empty one.
func pick(items: Array) -> Variant:
	if items.is_empty():
		return null
	return items[int_range(0, items.size() - 1)]

## Shuffle an array in place (Fisher-Yates) and return it.
func shuffle(items: Array) -> Array:
	for index in range(items.size() - 1, 0, -1):
		var other := int_range(0, index)
		var held: Variant = items[index]
		items[index] = items[other]
		items[other] = held
	return items
