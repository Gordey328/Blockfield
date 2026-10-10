shader_type canvas_item;
render_mode unshaded;
uniform sampler2D brightness_texture : filter_nearest, repeat_disable;
uniform sampler2D previous_gain : filter_nearest, repeat_disable;
uniform float min_gain = 0.3535533906;
uniform float max_gain = 1.4142135624;
uniform float adaptation_rate = 0.0;
void fragment() {
	float brightness = sqrt(sqrt(max(texture(brightness_texture, vec2(0.5)).r, 0.0000001)));
	float target = clamp(0.6 / brightness, min_gain, max_gain);
	float old = texture(previous_gain, vec2(0.5)).r;
	float gain = mix(old, target, adaptation_rate);
	COLOR = vec4(vec3(gain), 1.0);
}
