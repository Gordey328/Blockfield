shader_type spatial;
render_mode diffuse_lambert, specular_disabled;

// Vertex RGB is the unchanged VXL palette. Alpha carries native AO corner data;
// it is never written to ALPHA, so this material remains opaque and shadowed.
uniform bool lighting_enabled = true;
uniform float ambient_occlusion_strength : hint_range(0.0, 1.0) = 1.0;

void fragment() {
	vec3 palette = COLOR.rgb;
	float occlusion = mix(1.0, COLOR.a, ambient_occlusion_strength);
	ALBEDO = lighting_enabled ? palette : vec3(0.0);
	EMISSION = lighting_enabled ? vec3(0.0) : palette * occlusion;
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
	AO = occlusion;
	AO_LIGHT_AFFECT = 0.0;
}
