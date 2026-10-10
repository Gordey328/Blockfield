shader_type spatial;
render_mode unshaded, cull_disabled;

uniform sampler2D bottom_color : source_color, filter_nearest, repeat_disable;
uniform vec2 map_size = vec2(512.0);
uniform vec3 sky_color : source_color = vec3(0.65, 0.79, 0.84);
uniform vec3 fog_color : source_color = vec3(0.70, 0.78, 0.80);
uniform float fog_distance = 64.0;
varying vec3 world_position;

void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 p = world_position.xz;
	float a = p.x * 0.50 + p.y * 0.35 + TIME * 1.2;
	float b = p.x * -0.28 + p.y * 0.44 - TIME * 0.8;
	vec3 wave_normal = normalize(vec3(cos(a) * 0.10 + cos(b) * -0.06, 1.0, cos(a) * 0.07 + cos(b) * 0.08));
	vec3 view_direction = normalize(INV_VIEW_MATRIX[3].xyz - world_position);
	float fresnel = pow(clamp(1.0 - dot(view_direction, wave_normal), 0.0, 1.0), 4.0) + 0.03;
	vec3 floor_color = texture(bottom_color, clamp(p / map_size, vec2(0.0), vec2(1.0))).rgb;
	vec3 water_color = mix(floor_color * 0.72, vec3(0.22, 0.39, 0.40), 0.45);
	water_color = mix(water_color, sky_color, clamp(fresnel, 0.0, 1.0));
	float glitter = pow(max(dot(reflect(-view_direction, wave_normal), normalize(vec3(0.0, 1.0, -1.0))), 0.0), 70.0);
	water_color += glitter * 0.28;
	vec2 horizontal = p - INV_VIEW_MATRIX[3].xz;
	float d = clamp(dot(horizontal, horizontal) / (fog_distance * fog_distance), 0.0, 1.0);
	vec3 density = mix(vec3(d), vec3(1.0 - (1.0 - d) * (1.0 - d)), vec3(0.0, 0.3, 1.0));
	ALBEDO = mix(water_color, fog_color, density);
}
