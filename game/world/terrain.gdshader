shader_type spatial;
render_mode diffuse_lambert, specular_disabled;

// Vertex RGB is the unchanged VXL palette. Alpha carries native AO corner data;
// it is never written to ALPHA, so this material remains opaque and shadowed.
uniform bool lighting_enabled = true;
uniform float ambient_occlusion_strength : hint_range(0.0, 1.0) = 1.0;
// Data texture: no source_color conversion or mipmaps crossing tile borders.
uniform sampler2D ambient_occlusion_atlas : filter_linear, repeat_disable;
uniform bool ambient_occlusion_atlas_enabled = true;
uniform bool irradiance_enabled = false;
uniform sampler3D irradiance_base : filter_linear, repeat_disable;
uniform sampler3D irradiance_x : filter_linear, repeat_disable;
uniform sampler3D irradiance_y : filter_linear, repeat_disable;
uniform sampler3D irradiance_z : filter_linear, repeat_disable;
uniform vec3 irradiance_origin = vec3(0.5);
uniform vec3 irradiance_size = vec3(1.0);
uniform float irradiance_spacing = 4.0;
uniform vec3 irradiance_light = vec3(1.0);
varying vec3 world_position;

void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec3 palette = COLOR.rgb;
	float native_ao = ambient_occlusion_atlas_enabled ? texture(ambient_occlusion_atlas, UV2).r : COLOR.a;
	float occlusion = mix(1.0, native_ao, ambient_occlusion_strength);
	ALBEDO = lighting_enabled ? palette : vec3(0.0);
	EMISSION = lighting_enabled ? vec3(0.0) : palette * occlusion;
	if (lighting_enabled && irradiance_enabled) {
		vec3 grid = (world_position - irradiance_origin) / irradiance_spacing;
		if (all(greaterThanEqual(grid, vec3(0.0))) && all(lessThanEqual(grid, irradiance_size - vec3(1.0)))) {
			vec3 uv = (grid + vec3(0.5)) / irradiance_size;
			vec3 normal_world = normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
			vec3 bounced = texture(irradiance_base, uv).rgb;
			bounced += normal_world.x * texture(irradiance_x, uv).rgb;
			bounced += normal_world.y * texture(irradiance_y, uv).rgb;
			bounced += normal_world.z * texture(irradiance_z, uv).rgb;
			EMISSION += palette * max(bounced, vec3(0.0)) * 1.5 * irradiance_light;
		}
	}
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
	AO = occlusion;
	AO_LIGHT_AFFECT = 0.0;
}
