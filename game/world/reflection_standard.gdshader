shader_type spatial;
render_mode diffuse_burley;
// Reflection proxy adapter for original vertex-colored StandardMaterial meshes.
// Arbitrary PBR normal/parallax/ORM features of extension materials are not baked.
uniform float reflection_clip_level = 1.0;
uniform vec4 albedo_color : source_color = vec4(1.0);
uniform sampler2D albedo_texture : source_color, filter_linear, repeat_enable;
uniform bool texture_enabled = false;
uniform bool vertex_color_enabled = true;
uniform bool billboard_enabled = false;
uniform vec3 emission_color : source_color = vec3(0.0);
uniform float emission_energy = 1.0;
uniform float roughness = 1.0;
uniform float metallic = 0.0;
uniform float specular = 0.5;
uniform float alpha_scissor = 0.0;

void vertex() {
	if (billboard_enabled) {
		MODELVIEW_MATRIX = VIEW_MATRIX * mat4(
			vec4(INV_VIEW_MATRIX[0].xyz * length(MODEL_MATRIX[0].xyz), 0.0),
			vec4(INV_VIEW_MATRIX[1].xyz * length(MODEL_MATRIX[1].xyz), 0.0),
			vec4(INV_VIEW_MATRIX[2].xyz * length(MODEL_MATRIX[2].xyz), 0.0), MODEL_MATRIX[3]);
		MODELVIEW_NORMAL_MATRIX = mat3(MODELVIEW_MATRIX);
	}
}

void fragment() {
	if ((INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).y < reflection_clip_level - 0.0001) { discard; }
	vec4 color = albedo_color;
	if (vertex_color_enabled) { color *= COLOR; }
	if (texture_enabled) { color *= texture(albedo_texture, UV); }
	ALBEDO = color.rgb;
	EMISSION = emission_color * emission_energy;
	ROUGHNESS = roughness;
	METALLIC = metallic;
	SPECULAR = specular;
	// ALPHA_OUTPUT
}
