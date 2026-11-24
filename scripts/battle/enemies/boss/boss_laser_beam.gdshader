shader_type canvas_item;
render_mode unshaded;

uniform float outer_radius;
uniform float core_radius;
uniform float path_length;
uniform float age;
uniform float wind_down = 0.0;
uniform bool beam_open = true;
varying vec2 beam_point;

void vertex() {
	beam_point = VERTEX;
}

float capsule_distance(vec2 point) {
	return length(vec2(point.x - clamp(point.x, 0.0, path_length), point.y));
}

// Small, deterministic cell noise, advected along the locked beam direction.
// No per-frame RNG, extra textures, or per-particle draw calls.
float cell_hash(vec2 id) {
	vec3 h = fract(vec3(id.x, id.y, id.x) * vec3(0.1031, 0.1030, 0.0973));
	h += dot(h, h.yzx + 33.33);
	return fract((h.x + h.y) * h.z);
}

float flame_noise(vec2 uv) {
	vec2 id = floor(uv);
	vec2 t = fract(uv);
	t = t * t * (3.0 - 2.0 * t);
	return mix(mix(cell_hash(id), cell_hash(id + vec2(1.0, 0.0)), t.x),
		mix(cell_hash(id + vec2(0.0, 1.0)), cell_hash(id + vec2(1.0, 1.0)), t.x), t.y);
}

void fragment() {
	float dist = capsule_distance(beam_point);
	if (!beam_open || dist > outer_radius) {
		discard;
	}

	vec2 pixel = floor(beam_point / 3.0 + 0.5) * 3.0;
	float time = floor(age * 30.0) / 30.0;
	// Bend the stretched cells outward so the tongues emerge from the bright core.
	float shear = abs(pixel.y) * 1.1;
	float flow = flame_noise(vec2((pixel.x - shear - time * 152.0) / 27.0, pixel.y / 9.0));
	float tongues = smoothstep(0.22, 0.76, flow);
	float outer = clamp((dist - core_radius) / max(outer_radius - core_radius, 1.0), 0.0, 1.0);
	float reach = 1.0 - smoothstep(0.18, 0.99, outer - (tongues - 0.5) * 0.45);
	float glow = reach * (0.32 + 0.68 * tongues);
	float edge = 1.0 - smoothstep(0.55 + 0.24 * tongues, 1.0, outer);
	vec3 embers = mix(vec3(0.51, 0.10, 0.11), vec3(1.0, 0.33, 0.13), glow);
	vec4 fringe = vec4(embers, 0.075 + edge * (0.17 + 0.43 * glow));

	// Bright continuous core, blending into the low-damage plasma without a rail.
	float core = 1.0 - smoothstep(core_radius - 4.0, core_radius + 5.0, dist);
	float spine = 1.0 - smoothstep(0.0, core_radius, dist);
	float tip = 1.0 - smoothstep(0.0, core_radius * 0.9, length(pixel - vec2(path_length, 0.0)));
	float flash = (1.0 - smoothstep(0.0, 0.18, age)) * (1.0 - smoothstep(2.0, 18.0, length(pixel)));
	float hot = clamp(spine * (0.54 + 0.46 * tongues) + tip * 0.45 + flash * 0.50, 0.0, 1.0);
	vec3 gold = mix(vec3(1.0, 0.47, 0.13), vec3(1.0, 0.93, 0.60), hot);
	vec4 color = mix(fringe, vec4(gold, 0.87 + 0.08 * hot), core);

	// The fade still travels from muzzle to tip. Leave a textured low-light fill
	// within the same damage bands; don't bring back rigid capsule outlines.
	if (wind_down > 0.0) {
		float along = clamp(beam_point.x / path_length, 0.0, 1.0);
		float start = along * 0.80;
		float cooling = smoothstep(start, start + 0.20, wind_down);
		vec3 heat = mix(vec3(0.52, 0.13, 0.12), vec3(0.95, 0.38, 0.17), core * 0.72 + glow * 0.22);
		vec4 residual = vec4(heat, 0.075 + 0.04 * edge + 0.018 * glow + 0.052 * core);
		color = mix(color, residual, cooling);
	}
	COLOR = color;
}
