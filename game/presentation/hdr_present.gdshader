shader_type canvas_item;
render_mode unshaded;
#include "res://presentation/hdr_composite.gdshaderinc"
uniform sampler2D scene_texture : filter_nearest, repeat_disable;
uniform sampler2D gain_texture : filter_nearest, repeat_disable;
uniform float hdr_gamma = 2.2;
uniform bool hdr_enabled = true;
uniform bool aces_enabled = true;
uniform bool correction_enabled = true;
uniform vec3 tint = vec3(1.0);
uniform float exposure = 1.0;
uniform float saturation = 1.0;
uniform float enhancement = 0.0;
vec3 aces(vec3 value) {
	return clamp((value * (2.51 * value + 0.03)) / (value * (2.43 * value + 0.59) + 0.14), vec3(0.0), vec3(1.0));
}
void fragment() {
	vec3 value = texture(scene_texture, UV).rgb;
	if (hdr_enabled) {
		value = compose_bloom(value,UV);
		value *= texture(gain_texture, vec2(0.5)).r;
		// Native Nonlinearize.fs, then ColorCorrection.fs USE_HDR branch.
		value = pow(max(value, vec3(0.0)), vec3(1.0 / hdr_gamma));
		if (correction_enabled) {
			value *= tint * exposure;
			value = mix(vec3(dot(value,vec3(1.0/3.0))),value,saturation);
			if (aces_enabled) { value = sqrt(aces(value * value * 0.8)); }
			value = mix(value,smoothstep(vec3(0.0),vec3(1.0),value),enhancement);
		}
	}
	COLOR = vec4(value, 1.0);
}
