extends Node2D

# Particle effects. Each particle is written once, when it is spawned, into a MultiMesh slot; the
# shader in fx_particles.gdshader animates and draws all of them in one call. Slots are reused
# oldest first, so a burst past MAX_PARTICLES cuts the oldest particles short.

enum Kind { SPARK, SHARD, RING, DOT }

const MAX_PARTICLES := 1500
const SHADER := preload("res://scripts/fx_particles.gdshader")
# Floats per instance: 2D transform (8), color (4), custom data (4).
const STRIDE := 16
# Drag used to be applied per physics step as vel *= 1 - drag * step; this is that step.
const DRAG_STEP := 1.0 / 60.0

var _multimesh := MultiMesh.new()
var _material := ShaderMaterial.new()
var _buffer := PackedFloat32Array()
var _next := 0
var _used := 0
var _time := 0.0
var _dirty := false


func _ready() -> void:
	add_to_group("fx")
	z_index = 5
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = PackedVector2Array([Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)])
	arrays[Mesh.ARRAY_INDEX] = PackedInt32Array([0, 1, 2, 0, 2, 3])
	var quad := ArrayMesh.new()
	quad.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	_multimesh.transform_format = MultiMesh.TRANSFORM_2D
	_multimesh.use_colors = true
	_multimesh.use_custom_data = true
	_multimesh.mesh = quad
	_multimesh.instance_count = MAX_PARTICLES
	_multimesh.visible_instance_count = 0
	# Instance transforms carry particle data rather than placement, so bounds can't come from them.
	_multimesh.custom_aabb = AABB(Vector3(-1.0e6, -1.0e6, -1.0), Vector3(2.0e6, 2.0e6, 2.0))
	_buffer.resize(MAX_PARTICLES * STRIDE)
	_material.shader = SHADER
	var view := MultiMeshInstance2D.new()
	view.name = "Particles"
	view.multimesh = _multimesh
	view.material = _material
	add_child(view)


func _physics_process(delta: float) -> void:
	_time += delta
	_material.set_shader_parameter("now", _time)
	if _dirty:
		_dirty = false
		_multimesh.visible_instance_count = _used
		RenderingServer.multimesh_set_buffer(_multimesh.get_rid(), _buffer)


# How many particles are still alive (for tests and profiling; walks every slot).
func live_count() -> int:
	var count := 0
	for slot in _used:
		var i := slot * STRIDE
		if _buffer[i + 12] + _buffer[i + 13] > _time:
			count += 1
	return count


func hit_sparks(at: Vector2, dir: Vector2, color: Color) -> void:
	var base := dir.angle()
	for i in 7:
		var angle := base + randf_range(-0.9, 0.9)
		_emit(Kind.SPARK, at, Vector2.from_angle(angle) * randf_range(260.0, 520.0), color, 7.0,
			randf_range(0.14, 0.26), randf_range(1.5, 2.5))
	_emit(Kind.RING, at, Vector2.ZERO, color, 0.0, 0.14, 4.0, 18.0)


func shatter(at: Vector2, color: Color, strength: float = 1.0) -> void:
	for i in int(14 * strength):
		_emit(Kind.SHARD, at, Vector2.from_angle(randf() * TAU) * randf_range(120.0, 380.0) * strength, color, 3.2,
			randf_range(0.45, 0.8), randf_range(4.0, 8.0) * sqrt(strength), 0.0, randf() * TAU, randf_range(-12.0, 12.0))
	for i in int(8 * strength):
		_emit(Kind.SPARK, at, Vector2.from_angle(randf() * TAU) * randf_range(350.0, 650.0) * strength, color, 6.0,
			randf_range(0.18, 0.32), 2.0)
	for i in int(8 * strength):
		_emit(Kind.DOT, at, Vector2.from_angle(randf() * TAU) * randf_range(40.0, 160.0), color, 2.0,
			randf_range(0.6, 1.1), randf_range(1.5, 3.0))
	_emit(Kind.RING, at, Vector2.ZERO, color, 0.0, 0.32, 6.0, 54.0 * strength)


func ring(at: Vector2, color: Color, radius: float, duration: float) -> void:
	_emit(Kind.RING, at, Vector2.ZERO, color, 0.0, duration, radius * 0.15, radius)


func burst(at: Vector2, color: Color, count: int, speed: float) -> void:
	for i in count:
		var angle := TAU * float(i) / float(count) + randf_range(-0.1, 0.1)
		_emit(Kind.SPARK, at, Vector2.from_angle(angle) * speed * randf_range(0.8, 1.2), color, 5.0,
			randf_range(0.25, 0.4), 2.0)


func _emit(kind: int, at: Vector2, vel: Vector2, color: Color, drag: float, life: float, size: float,
		end_size := 0.0, rot := 0.0, spin := 0.0) -> void:
	var i := _next * STRIDE
	_next = (_next + 1) % MAX_PARTICLES
	_used = maxi(_used, _next if _next > 0 else MAX_PARTICLES)
	# The shader integrates continuously, so convert the per-step drag into a decay rate.
	var rate := -log(maxf(0.0001, 1.0 - drag * DRAG_STEP)) / DRAG_STEP
	# HDR 2D converts draw-call colors to linear for us, but raw instance data is taken as is.
	color = color.srgb_to_linear()
	_buffer[i] = vel.x
	_buffer[i + 1] = rot
	_buffer[i + 3] = at.x
	_buffer[i + 4] = vel.y
	_buffer[i + 5] = spin
	_buffer[i + 7] = at.y
	_buffer[i + 8] = color.r
	_buffer[i + 9] = color.g
	_buffer[i + 10] = color.b
	_buffer[i + 11] = float(kind) * 16.0 + rate
	_buffer[i + 12] = _time
	_buffer[i + 13] = life
	_buffer[i + 14] = size
	_buffer[i + 15] = end_size
	_dirty = true
