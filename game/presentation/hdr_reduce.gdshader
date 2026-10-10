shader_type canvas_item;
render_mode unshaded;
#include "res://presentation/hdr_composite.gdshaderinc"
uniform sampler2D source_texture : filter_linear, repeat_disable;
uniform bool preprocess = false;
uniform vec2 logical_size = vec2(2.0);
void fragment() {
	// Godot's minimum SubViewport extent is 2. Replicate a native one-pixel
	// row/column, and its final 1x1 average, across the physical 2x2 target.
	vec2 coordinate = (floor(UV * logical_size) + vec2(0.5)) / logical_size;
	vec3 value = texture(source_texture, coordinate).rgb;
	if (preprocess) {
		if (bloom_enabled) {
			// Native first meter pass bilinearly samples the full-resolution
			// composited radiance before its nonlinear brightness preprocessing.
			// Evaluate those four source texels here to avoid another full HDR FBO.
			vec2 texel = coordinate*bloom_source_size-vec2(0.5);
			vec2 base = floor(texel);
			vec2 blend = fract(texel);
			vec2 a = (base+vec2(0.5))/bloom_source_size;
			vec2 b = a+vec2(1.0/bloom_source_size.x,0.0);
			vec2 c = a+vec2(0.0,1.0/bloom_source_size.y);
			vec2 d = a+1.0/bloom_source_size;
			vec3 aa = compose_bloom(texture(source_texture,a).rgb,a);
			vec3 bb = compose_bloom(texture(source_texture,b).rgb,b);
			vec3 cc = compose_bloom(texture(source_texture,c).rgb,c);
			vec3 dd = compose_bloom(texture(source_texture,d).rgb,d);
			value = mix(mix(aa,bb,blend.x),mix(cc,dd,blend.x),blend.y);
		}
		float brightness = max(max(value.r, value.g), value.b);
		if (!(brightness >= 0.0 && brightness <= 16.0)) { brightness = 0.05; }
		brightness = clamp(brightness, 0.05, 1.3);
		brightness *= brightness;
		brightness *= brightness;
		value = vec3(brightness);
	}
	COLOR = vec4(value, 1.0);
}
