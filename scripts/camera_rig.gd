extends Camera2D

# Leads toward the direction of travel and shakes with accumulated trauma.
# The game drives both updates explicitly so their order within a tick stays fixed.
const LOOK_AHEAD := Vector2(80.0, 80.0)
const LOOK_SMOOTH_MOVING := 0.7
const LOOK_SMOOTH_STOPPING := 0.4
const SHAKE_MAX := 9.0
const SHAKE_DECAY := 2.2

var trauma := 0.0
var look_offset := Vector2.ZERO
var look_velocity := Vector2.ZERO


func _init() -> void:
	name = "Camera"
	process_callback = Camera2D.CAMERA2D_PROCESS_PHYSICS


func add_trauma(amount: float) -> void:
	trauma = minf(1.0, trauma + amount)


func update_shake(delta: float) -> void:
	trauma = maxf(0.0, trauma - SHAKE_DECAY * delta)
	var strength := trauma * trauma * SHAKE_MAX
	offset = Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)) * strength


func follow(target: Node2D, velocity: Vector2, max_speed: float, delta: float) -> void:
	var move_ratio: Vector2 = velocity / maxf(1.0, max_speed)
	# Standing still keeps the current lead: drifting back to centre on its own
	# scrolls the world forward and reads as the ship backing up.
	if move_ratio == Vector2.ZERO:
		_smooth_damp_look(look_offset, LOOK_SMOOTH_STOPPING, delta)
	else:
		_smooth_damp_look(move_ratio * LOOK_AHEAD, LOOK_SMOOTH_MOVING, delta)
	global_position = target.global_position + look_offset


func view_rect() -> Rect2:
	var size := get_viewport_rect().size
	return Rect2(get_screen_center_position() - size * 0.5, size)


# Critically damped spring, so the camera eases in and out without overshoot.
func _smooth_damp_look(target: Vector2, smooth_time: float, delta: float) -> void:
	var omega := 2.0 / smooth_time
	var x := omega * delta
	var decay := 1.0 / (1.0 + x + 0.48 * x * x + 0.235 * x * x * x)
	var change := look_offset - target
	var temp := (look_velocity + omega * change) * delta
	look_velocity = (look_velocity - omega * temp) * decay
	look_offset = target + (change + temp) * decay
