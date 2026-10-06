extends Node2D

enum Kind { SPARK, SHARD, RING, DOT }

const MAX_PARTICLES := 1500


class Particle:
	var kind := 0
	var pos := Vector2.ZERO
	var vel := Vector2.ZERO
	var drag := 4.0
	var life := 0.0
	var max_life := 0.5
	var size := 4.0
	var end_size := 0.0
	var rot := 0.0
	var spin := 0.0
	var color := Color.WHITE


var _particles: Array[Particle] = []


func _ready() -> void:
	add_to_group("fx")
	z_index = 5
	var mat := CanvasItemMaterial.new()
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	material = mat


func _physics_process(delta: float) -> void:
	if _particles.is_empty():
		return
	var alive: Array[Particle] = []
	for p in _particles:
		p.life += delta
		if p.life >= p.max_life:
			continue
		p.vel *= maxf(0.0, 1.0 - p.drag * delta)
		p.pos += p.vel * delta
		p.rot += p.spin * delta
		alive.append(p)
	_particles = alive
	queue_redraw()


func hit_sparks(at: Vector2, dir: Vector2, color: Color) -> void:
	var base := dir.angle()
	for i in 7:
		var p := _spawn(Kind.SPARK, at, color)
		var angle := base + randf_range(-0.9, 0.9)
		p.vel = Vector2.from_angle(angle) * randf_range(260.0, 520.0)
		p.drag = 7.0
		p.max_life = randf_range(0.14, 0.26)
		p.size = randf_range(1.5, 2.5)
	var flash := _spawn(Kind.RING, at, color)
	flash.size = 4.0
	flash.end_size = 18.0
	flash.max_life = 0.14


func shatter(at: Vector2, color: Color, strength: float = 1.0) -> void:
	var shards := int(14 * strength)
	for i in shards:
		var p := _spawn(Kind.SHARD, at, color)
		p.vel = Vector2.from_angle(randf() * TAU) * randf_range(120.0, 380.0) * strength
		p.drag = 3.2
		p.max_life = randf_range(0.45, 0.8)
		p.size = randf_range(4.0, 8.0) * sqrt(strength)
		p.rot = randf() * TAU
		p.spin = randf_range(-12.0, 12.0)
	for i in int(8 * strength):
		var p := _spawn(Kind.SPARK, at, color)
		p.vel = Vector2.from_angle(randf() * TAU) * randf_range(350.0, 650.0) * strength
		p.drag = 6.0
		p.max_life = randf_range(0.18, 0.32)
		p.size = 2.0
	for i in int(8 * strength):
		var p := _spawn(Kind.DOT, at, color)
		p.vel = Vector2.from_angle(randf() * TAU) * randf_range(40.0, 160.0)
		p.drag = 2.0
		p.max_life = randf_range(0.6, 1.1)
		p.size = randf_range(1.5, 3.0)
	var ring := _spawn(Kind.RING, at, color)
	ring.size = 6.0
	ring.end_size = 54.0 * strength
	ring.max_life = 0.32


func ring(at: Vector2, color: Color, radius: float, duration: float) -> void:
	var p := _spawn(Kind.RING, at, color)
	p.size = radius * 0.15
	p.end_size = radius
	p.max_life = duration


func burst(at: Vector2, color: Color, count: int, speed: float) -> void:
	for i in count:
		var p := _spawn(Kind.SPARK, at, color)
		p.vel = Vector2.from_angle(TAU * float(i) / float(count) + randf_range(-0.1, 0.1)) * speed * randf_range(0.8, 1.2)
		p.drag = 5.0
		p.max_life = randf_range(0.25, 0.4)
		p.size = 2.0


func _spawn(kind: int, at: Vector2, color: Color) -> Particle:
	if _particles.size() >= MAX_PARTICLES:
		_particles.pop_front()
	var p := Particle.new()
	p.kind = kind
	p.pos = at
	p.color = color
	_particles.append(p)
	return p


func _draw() -> void:
	for p in _particles:
		var t := p.life / p.max_life
		var fade := 1.0 - t
		var c := p.color
		match p.kind:
			Kind.SPARK:
				c.a = fade
				var tail := p.vel * 0.035
				draw_line(p.pos - tail, p.pos, c, p.size * (0.4 + fade), true)
			Kind.SHARD:
				c.a = fade * fade
				var r := p.size * (0.5 + 0.5 * fade)
				var a := Vector2.from_angle(p.rot) * r
				# draw_primitive skips triangulation, which can reject tiny triangles.
				draw_primitive(PackedVector2Array([
					p.pos + a,
					p.pos + a.rotated(2.3) * 0.7,
					p.pos + a.rotated(-2.3) * 0.7,
				]), PackedColorArray([c, c, c]), PackedVector2Array())
			Kind.RING:
				c.a = fade * 0.9
				var radius := lerpf(p.size, p.end_size, 1.0 - pow(1.0 - t, 3.0))
				draw_arc(p.pos, radius, 0.0, TAU, 32, c, 2.0 * fade + 0.5, true)
			Kind.DOT:
				c.a = fade * 0.8
				draw_rect(Rect2(p.pos - Vector2.ONE * p.size * 0.5, Vector2.ONE * p.size), c)
