shader_type canvas_item;

void fragment() {
	float shade = clamp(dot(COLOR.rgb, vec3(0.2126, 0.7152, 0.0722)), 0.0, 1.0);
	vec3 rose = mix(vec3(0.18, 0.07, 0.09), vec3(1.0, 0.76, 0.74), sqrt(shade));
	COLOR.rgb = mix(COLOR.rgb, rose, 0.74);
}
