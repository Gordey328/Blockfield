shader_type canvas_item;
render_mode unshaded;
uniform sampler2D source_texture : filter_linear, repeat_disable;
uniform sampler2D coarse_texture : filter_linear, repeat_disable;
uniform int operation = 0; // 0 downsample, 1 Gaussian, 2 reverse composite
uniform vec2 range_scale = vec2(1.0);
uniform vec2 unit_shift = vec2(0.0);
uniform float coarse_weight = 0.5;
void fragment() {
	vec3 value;
	if (operation == 1) {
		// Exact Gauss1D.fs bilinear tap offsets and weights.
		value = texture(source_texture,UV-unit_shift*2.30654399138844).rgb*0.178704407070903;
		value += texture(source_texture,UV-unit_shift*0.629455560633963).rgb*0.321295592929097;
		value += texture(source_texture,UV+unit_shift*0.629455560633963).rgb*0.321295592929097;
		value += texture(source_texture,UV+unit_shift*2.30654399138844).rgb*0.178704407070903;
	} else if (operation == 2) {
		value = mix(texture(source_texture,UV).rgb,texture(coarse_texture,UV).rgb,coarse_weight);
	} else {
		value = texture(source_texture,UV*range_scale).rgb;
	}
	COLOR = vec4(value,1.0);
}
