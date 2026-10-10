shader_type spatial;
render_mode cull_disabled, diffuse_lambert, fog_disabled;

uniform sampler2D bottom_color : source_color, filter_linear, repeat_disable;
uniform sampler2D wave_texture : filter_linear, repeat_enable;
uniform sampler2D screen_texture : hint_screen_texture, filter_nearest, repeat_disable;
uniform sampler2D depth_texture : hint_depth_texture, filter_nearest, repeat_disable;
uniform vec2 map_size = vec2(512.0);
uniform vec3 sky_color : source_color = vec3(0.65, 0.79, 0.84);
uniform vec3 fog_color : source_color = vec3(0.70, 0.78, 0.80);
uniform float fog_distance = 64.0;
uniform bool fog_enabled = true;
uniform bool waves_enabled = true;
uniform bool refraction_enabled = true;
uniform bool lighting_enabled = true;
uniform float refraction_strength : hint_range(0.0, 4.0) = 1.0;
uniform bool reflection_enabled = false;
uniform sampler2D reflection_texture : source_color, filter_linear, repeat_disable;
uniform mat4 reflection_projection_view;
uniform vec2 reflection_texel_size = vec2(0.003125, 0.004166667);
varying vec3 world_position;

void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

vec3 position_from_depth(vec2 uv, mat4 inverse_projection) {
	float depth = texture(depth_texture, uv).r;
	#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
	vec3 ndc = vec3(uv, depth) * 2.0 - 1.0;
	#else
	vec3 ndc = vec3(uv * 2.0 - 1.0, depth);
	#endif
	vec4 view = inverse_projection * vec4(ndc, 1.0);
	return view.xyz / view.w;
}

void fragment() {
	vec2 p = world_position.xz;
	vec2 slopes = vec2(0.0);
	if (waves_enabled) {
		// Water.fs samples its low-quality wave bank at three original scales.
		slopes = (texture(wave_texture, p * 0.08).rg * 2.0 - 1.0) * (0.08 / 200.0);
		slopes += (texture(wave_texture, p * 0.15704 + vec2(0.754, 0.1315)).rg * 2.0 - 1.0) * (0.15704 / 200.0);
		slopes += (texture(wave_texture, p * 0.02344 + vec2(0.154, 0.7315)).rg * 2.0 - 1.0) * (0.02344 / 200.0);
	}
	vec3 wave_normal = normalize(vec3(-slopes.x, 1.0 / 128.0, -slopes.y));
	vec3 normal_view = normalize((VIEW_MATRIX * vec4(wave_normal, 0.0)).xyz);
	vec2 refracted_uv = SCREEN_UV;
	if (refraction_enabled) {
		vec2 displacement = normal_view.xy * 0.4 * refraction_strength / max(-VERTEX.z, 0.05);
		displacement *= vec2(PROJECTION_MATRIX[0][0], PROJECTION_MATRIX[1][1]);
		refracted_uv = clamp(SCREEN_UV + displacement, vec2(0.00001), vec2(0.99999));
	}
	vec3 behind_view = position_from_depth(refracted_uv, INV_PROJECTION_MATRIX);
	vec3 behind_world = (INV_VIEW_MATRIX * vec4(behind_view, 1.0)).xyz;
	// Native envelope guard: never refract an above-water foreground object.
	if (behind_world.y > world_position.y + 0.001) {
		refracted_uv = SCREEN_UV;
		behind_view = position_from_depth(refracted_uv, INV_PROJECTION_MATRIX);
	}
	float thickness = max(0.0, -behind_view.z + VERTEX.z);
	float envelope = clamp(thickness, 0.0, 1.0);
	envelope = 1.0 - (1.0 - envelope) * (1.0 - envelope);
	vec3 view_direction = normalize(INV_VIEW_MATRIX[3].xyz - world_position);
	float fresnel = clamp(pow(clamp(1.0 - dot(view_direction, wave_normal), 0.0, 1.0), 4.0) + 0.03, 0.0, 1.0);
	vec3 floor_color = texture(bottom_color, clamp(p / map_size, vec2(0.0), vec2(1.0))).rgb;
	vec3 refracted = texture(screen_texture, refracted_uv).rgb;
	vec3 reflected = sky_color;
	if (reflection_enabled) {
		vec4 clip = reflection_projection_view * vec4(world_position, 1.0);
		vec2 reflected_uv = vec2(clip.x, -clip.y) / clip.w * 0.5 + 0.5;
		// Water2.fs distorts its mirror buffer with the same spectral slopes.
		// Keep the displacement bounded at this low render-target resolution.
		vec2 ripple = slopes * 128.0 * 0.04;
		reflected_uv += vec2(ripple.x, -abs(ripple.y * 3.0));
		if (clip.w > 0.0 && all(greaterThanEqual(reflected_uv, vec2(0.0))) && all(lessThanEqual(reflected_uv, vec2(1.0)))) {
			reflected = texture(reflection_texture, clamp(reflected_uv, reflection_texel_size * 0.5, vec2(1.0) - reflection_texel_size * 0.5)).rgb;
		}
	}
	vec2 horizontal = p - INV_VIEW_MATRIX[3].xz;
	float d = clamp(dot(horizontal, horizontal) / (fog_distance * fog_distance), 0.0, 1.0);
	vec3 density = mix(vec3(d), vec3(1.0 - (1.0 - d) * (1.0 - d)), vec3(0.0, 0.3, 1.0));
	if (!fog_enabled) { density = vec3(0.0); }
	vec3 floor_term = floor_color * envelope * (1.0 - fresnel) * (1.0 - density);
	ALBEDO = lighting_enabled ? floor_term : vec3(0.0);
	EMISSION = refracted * (1.0 - envelope) * (1.0 - fresnel) + reflected * fresnel * (1.0 - density) + fog_color * density;
	if (!lighting_enabled) { EMISSION += floor_term; }
	NORMAL = normal_view;
	ROUGHNESS = 0.04;
	SPECULAR = 0.5;
	ALPHA = 1.0;
}
