shader_type canvas_item;
render_mode unshaded, blend_disabled;
// Bounded inverse spectral sum: (kx,ky,evolving real,evolving imaginary).
uniform vec4 modes[32];
void fragment() {
	float height = 0.0;
	vec2 derivative = vec2(0.0);
	for (int i = 0; i < 32; i++) {
		vec4 mode = modes[i];
		float angle = 6.28318530718 * dot(mode.xy, UV);
		float c = cos(angle);
		float s = sin(angle);
		height += mode.z * c - mode.w * s;
		// Periodic central difference one native texel apart.
		derivative -= 2.0 * sin(6.28318530718 * mode.xy / 128.0) * (mode.z * s + mode.w * c);
	}
	// Native BGRA upload exposes (dx*200,dy*200,z*200,-height*10).
	COLOR = clamp(vec4(derivative * 200.0, 8.0, -height * 10.0) * 0.5 + 0.5, vec4(0.0), vec4(1.0));
}
