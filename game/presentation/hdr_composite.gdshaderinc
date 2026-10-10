// GLLensDustFilter/LensDust.fs LINEAR_FRAMEBUFFER branch. Applied before
// metering/gamma/tone. Shared function keeps the two consumers consistent.
uniform bool bloom_enabled = false;
uniform sampler2D bloom_texture : filter_linear, repeat_disable;
uniform sampler2D bloom_dust_texture : filter_linear, repeat_disable;
uniform vec2 bloom_source_size = vec2(1.0);
uniform float bloom_frame = 0.0;
uniform bool grain_enabled = true;
float bloom_noise(vec2 point) {
	// Source uploads fresh128x128 RNG noise. Keep its amplitude/frequencies,
	// replacing the random byte texture with a bounded procedural sequence.
	return fract(sin(dot(point+vec2(bloom_frame,0.17*bloom_frame),vec2(12.9898,78.233)))*43758.5453);
}
vec3 compose_bloom(vec3 original,vec2 coordinate) {
	if (!bloom_enabled) { return original; }
	vec3 dust = texture(bloom_dust_texture,coordinate).rgb;
	vec3 blurred = texture(bloom_texture,coordinate).rgb;
	vec3 value = original*0.95 + dust*dust*blurred*2.0;
	if (grain_enabled) {
		float grain = fract(bloom_noise(floor(coordinate*bloom_source_size))+bloom_noise(floor(coordinate*bloom_source_size/128.0)))-0.5;
		value += vec3(grain*0.003);
	}
	return max(value,vec3(0.0));
}
