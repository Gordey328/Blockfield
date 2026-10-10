shader_type canvas_item;
render_mode unshaded;
// Godot 4.7.2 Compatibility scene.glsl writes nonlinear RGB even into the
// floating-point 3D target. Invert its tonemap_inc.glsl:12-16 OETF once, before
// any native OpenSpades HDR metering, bloom or nonlinearization.
// No source_color hint: this is a viewport texture, not an authored texture.
uniform sampler2D source_texture : filter_nearest, repeat_disable;
void fragment() {
	vec3 encoded = max(texture(source_texture, UV).rgb, vec3(0.0));
	vec3 linear = pow((encoded + vec3(0.055)) / 1.055, vec3(2.4));
	// The renderer clamps the OETF below zero; preserve exact black rather than
	// manufacturing a .000834 linear floor. Lost near-black data is unrecoverable.
	linear = mix(vec3(0.0), linear, greaterThan(encoded, vec3(0.0)));
	COLOR = vec4(linear, 1.0);
}
