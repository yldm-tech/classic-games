extends Area2D

## Shared projectile integrator. Velocity lives on meta so boss and turret shots
## can reuse the same motion without a unique controller per source.

func _process(delta: float) -> void:
	if not has_meta("velocity"):
		return
	position += get_meta("velocity") * delta
	set_meta("life", float(get_meta("life", 0.0)) + delta)
	if float(get_meta("life")) > 4.0:
		queue_free()
