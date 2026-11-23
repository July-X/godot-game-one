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

void fragment() {
	float dist = capsule_distance(beam_point);
	if (!beam_open || dist > outer_radius) {
		discard;
	}

	// Keep segmentation and movement inside the same fixed lethal and burn boundaries.
	vec2 pixel = floor(beam_point / 3.0 + 0.5) * 3.0;
	float band = capsule_distance(pixel);
	float time = floor(age * 30.0) / 30.0;
	float ribbon = fract((pixel.x + pixel.y * 3.0 - time * 185.0) / 182.0);
	vec4 color = vec4(0.53, 0.10, 0.055, 0.30);
	if (band < core_radius + 13.0) {
		color = vec4(0.70, 0.15, 0.075, 0.39);
	}
	if (band < core_radius + 19.0 && ribbon < 0.18) {
		color = vec4(0.76, 0.22, 0.09, 0.43);
	}
	if (dist >= outer_radius - 3.0) {
		color = vec4(0.90, 0.36, 0.15, 0.75);
	}

	if (dist <= core_radius) {
		color = vec4(0.76, 0.22, 0.085, 0.85);
		if (dist >= core_radius - 2.2) {
			color = vec4(1.0, 0.49, 0.19, 0.88);
		} else {
			if (band <= 4.0) {
				color = vec4(0.96, 0.48, 0.18, 0.89);
			}
			if (ribbon < 0.22 && band <= 11.0) {
				color = vec4(1.0, 0.68, 0.31, 0.92);
			}
		}
		float tip_cell = length(pixel - vec2(path_length, 0.0));
		if (tip_cell < core_radius * 0.75) {
			color = vec4(1.0, 0.65, 0.27, 0.92);
			if (tip_cell < core_radius * 0.38) {
				color.rgb = vec3(1.0, 0.86, 0.57);
			}
		}
		float ignition = (1.0 - smoothstep(0.0, 0.18, age)) * (1.0 - smoothstep(2.0, 18.0, length(pixel)));
		color.rgb = mix(color.rgb, vec3(1.0, 0.86, 0.57), ignition);
	}
	// The fade starts at the muzzle and travels with the outgoing beam.
	// Behind it, static rails still mark both hit bands until damage stops.
	if (wind_down > 0.0) {
		float along = clamp(beam_point.x / path_length, 0.0, 1.0);
		float start = along * 0.80;
		float cooling = smoothstep(start, start + 0.20, wind_down);
		vec4 residual = vec4(0.38, 0.12, 0.08, 0.10);
		if (dist >= outer_radius - 3.0) {
			residual = vec4(0.70, 0.31, 0.16, 0.55);
		} else if (dist >= core_radius - 3.4 && dist <= core_radius) {
			residual = vec4(0.84, 0.39, 0.20, 0.76);
		}
		color = mix(color, residual, cooling);
	}
	COLOR = color;
}
