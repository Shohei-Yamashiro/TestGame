shader_type canvas_item;
// Every particle is one MultiMesh instance that only stores how it was spawned; this works out
// where it is now, so the CPU writes each particle once instead of redrawing all of them per frame.
// Instance layout (written by fx.gd):
//   MODEL_MATRIX x axis = start velocity, y axis = (rotation, spin), origin = start position
//   INSTANCE_CUSTOM     = (spawn time, lifetime, size, end size)
//   COLOR               = rgb, with alpha = kind * 16 + drag rate
render_mode blend_add, skip_vertex_transform;

uniform float now;

varying vec2 local;
varying flat vec4 shape;
varying flat float kind;

vec2 rotated(vec2 v, float a) {
	return vec2(v.x * cos(a) - v.y * sin(a), v.x * sin(a) + v.y * cos(a));
}

// Signed distance to a triangle (negative inside).
float sd_triangle(vec2 p, vec2 p0, vec2 p1, vec2 p2) {
	vec2 e0 = p1 - p0;
	vec2 e1 = p2 - p1;
	vec2 e2 = p0 - p2;
	vec2 v0 = p - p0;
	vec2 v1 = p - p1;
	vec2 v2 = p - p2;
	vec2 pq0 = v0 - e0 * clamp(dot(v0, e0) / dot(e0, e0), 0.0, 1.0);
	vec2 pq1 = v1 - e1 * clamp(dot(v1, e1) / dot(e1, e1), 0.0, 1.0);
	vec2 pq2 = v2 - e2 * clamp(dot(v2, e2) / dot(e2, e2), 0.0, 1.0);
	float s = sign(e0.x * e2.y - e0.y * e2.x);
	vec2 d = min(min(vec2(dot(pq0, pq0), s * (v0.x * e0.y - v0.y * e0.x)),
			vec2(dot(pq1, pq1), s * (v1.x * e1.y - v1.y * e1.x))),
			vec2(dot(pq2, pq2), s * (v2.x * e2.y - v2.y * e2.x)));
	return -sqrt(d.x) * sign(d.y);
}

void vertex() {
	vec2 v0 = MODEL_MATRIX[0].xy;
	float rot0 = MODEL_MATRIX[1].x;
	float spin = MODEL_MATRIX[1].y;
	vec2 p0 = MODEL_MATRIX[3].xy;
	float born = INSTANCE_CUSTOM.x;
	float life = INSTANCE_CUSTOM.y;
	float size = INSTANCE_CUSTOM.z;
	float end_size = INSTANCE_CUSTOM.w;
	kind = floor(COLOR.a / 16.0);
	float drag = COLOR.a - kind * 16.0;
	float age = now - born;
	vec2 corner = VERTEX;
	local = vec2(0.0);
	shape = vec4(0.0);
	if (life <= 0.0 || age < 0.0 || age >= life) {
		VERTEX = vec2(0.0);
		COLOR = vec4(0.0);
	} else {
		float t = age / life;
		float fade = 1.0 - t;
		float decay = exp(-drag * age);
		vec2 pos = p0 + v0 * (drag > 0.0 ? (1.0 - decay) / drag : age);
		vec2 vel = v0 * decay;
		float alpha = 1.0;
		if (kind < 0.5) {
			// Spark: a streak trailing behind its motion.
			float speed = length(vel);
			vec2 dir = speed > 0.001 ? vel / speed : vec2(1.0, 0.0);
			vec2 half_size = vec2(speed * 0.035, size * (0.4 + fade)) * 0.5;
			local = corner * (half_size + 1.0);
			VERTEX = pos - vel * 0.0175 + dir * local.x + vec2(-dir.y, dir.x) * local.y;
			shape = vec4(half_size, 0.0, 0.0);
			alpha = fade;
		} else if (kind < 1.5) {
			// Shard: a spinning sliver of a triangle.
			float r = size * (0.5 + 0.5 * fade);
			float rot = rot0 + spin * age;
			local = corner * (r + 1.0);
			VERTEX = pos + local;
			shape = vec4(cos(rot) * r, sin(rot) * r, 0.0, 0.0);
			alpha = fade * fade;
		} else if (kind < 2.5) {
			// Ring: expands quickly, then settles.
			float radius = mix(size, end_size, 1.0 - pow(1.0 - t, 3.0));
			float half_width = (2.0 * fade + 0.5) * 0.5;
			local = corner * (radius + half_width + 1.0);
			VERTEX = pos + local;
			shape = vec4(radius, half_width, 0.0, 0.0);
			alpha = fade * 0.9;
		} else {
			// Dot: a small square that lingers.
			local = corner * size * 0.5;
			VERTEX = pos + local;
			alpha = fade * 0.8;
		}
		COLOR = vec4(COLOR.rgb, alpha);
	}
}

void fragment() {
	float d = -1.0;
	if (kind < 0.5) {
		vec2 q = abs(local) - shape.xy;
		d = max(q.x, q.y);
	} else if (kind < 1.5) {
		vec2 a = shape.xy;
		d = sd_triangle(local, a, rotated(a, 2.3) * 0.7, rotated(a, -2.3) * 0.7);
	} else if (kind < 2.5) {
		d = abs(length(local) - shape.x) - shape.y;
	}
	COLOR.a *= clamp(0.5 - d, 0.0, 1.0);
}
