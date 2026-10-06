extends RefCounted

# Art rule: anything that helps the player is a cool color with an even number of sides;
# anything hostile is a warm color with an odd number of sides.
const PLAYER := Color(0.35, 0.95, 1.0)
const BULLET := Color(0.7, 0.88, 1.0)
const BULLET_PIERCE := Color(0.8, 0.7, 1.0)
const GEM := Color(0.45, 1.0, 0.8)
const HURT := Color(1.0, 0.3, 0.35)
const HOMING := Color(0.4, 1.0, 0.45)
const ORBIT := Color(0.45, 0.6, 1.0)
const NOVA := Color(0.75, 0.6, 1.0)
const LASER := Color(0.6, 1.0, 0.92)
const WINGS := Color(0.62, 0.8, 1.0)
const ELECTRIC := Color(0.55, 0.85, 1.0)
const CHAIN := Color(0.8, 0.85, 1.0)
const BOOMERANG := Color(0.25, 0.78, 0.95)
const MINE := Color(0.9, 0.55, 1.0)
const GEM_TIERS: Array[Color] = [
	Color(0.45, 1.0, 0.8),
	Color(0.4, 0.85, 1.0),
	Color(0.5, 0.6, 1.0),
	Color(0.75, 0.55, 1.0),
]
# Ordered by threat: triangle, pentagon, heptagon.
const ENEMIES: Array[Color] = [
	Color(1.0, 0.75, 0.2),
	Color(1.0, 0.45, 0.15),
	Color(1.0, 0.2, 0.35),
	Color(1.0, 0.95, 0.75),
	Color(1.0, 0.35, 0.6),
]
const ENEMY_SHOT := Color(1.0, 0.35, 0.45)
const SLOW := Color(0.6, 0.75, 1.0)


# Values above 1.0 exceed the glow threshold and bloom under the HDR 2D environment.
static func hdr(color: Color, intensity: float) -> Color:
	return Color(color.r * intensity, color.g * intensity, color.b * intensity, color.a)


static func regular_polygon(sides: int, radius: float, rotation: float) -> PackedVector2Array:
	var points := PackedVector2Array()
	for i in sides:
		points.append(Vector2.from_angle(rotation + TAU * float(i) / float(sides)) * radius)
	return points


static func closed(points: PackedVector2Array) -> PackedVector2Array:
	var result := points.duplicate()
	result.append(points[0])
	return result
