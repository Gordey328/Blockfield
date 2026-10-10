shader_type spatial;
render_mode unshaded, fog_disabled, cull_disabled, depth_draw_never, depth_test_disabled;
uniform sampler2D scene_image : hint_screen_texture, repeat_disable, filter_linear;
uniform sampler2D scene_depth : hint_depth_texture, repeat_disable, filter_nearest;
uniform bool ssao_enabled = false;
uniform bool dof_enabled = false;
uniform float ssao_strength = 1.0;
uniform float dof_strength = 1.0;
uniform float focus_distance = 10.0;
uniform float focus_focal_length = 0.054;
uniform bool manual_focus_enabled = false;
uniform int quality = 1;
vec3 view_position(vec2 uv, mat4 inverse_projection) {
	float depth = texture(scene_depth,uv).r;
	#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
	vec3 ndc = vec3(uv,depth)*2.0-1.0;
	#else
	vec3 ndc = vec3(uv*2.0-1.0,depth);
	#endif
	vec4 position = inverse_projection*vec4(ndc,1.0);
	return position.xyz/max(position.w,0.000001);
}
void vertex() { POSITION = vec4(VERTEX.xy,1.0,1.0); }
void fragment() {
	vec2 uv = SCREEN_UV;
	vec3 origin = view_position(uv,INV_PROJECTION_MATRIX);
	float depth = max(-origin.z,0.001);
	vec3 color = texture(scene_image,uv).rgb;
	if (dof_enabled) {
		// DoFCoCGen.fs: signed CoC = 1-depth/focalRange. Auto near-only;
		// manual focus gives equal half-strength near and far blur.
		float focal_range = manual_focus_enabled ? max(focus_distance,0.054) : focus_focal_length;
		float signed_blur = 1.0-depth/max(focal_range,0.054);
		float blur = manual_focus_enabled ? abs(signed_blur)*0.5 : max(signed_blur,0.0);
		float center_scale = min(length((uv-0.5)*vec2(2.0,2.0*VIEWPORT_SIZE.y/VIEWPORT_SIZE.x))*10.0,1.0);
		float circle = min(blur*dof_strength,1.0)*0.007*center_scale;
		vec3 blurred = color;
		int samples = quality >= 2 ? 12 : 6;
		for (int index=0;index<12;index++) {
			if (index >= samples) { break; }
			float angle = float(index)*2.399963;
			vec2 offset = vec2(cos(angle),sin(angle))*circle*sqrt((float(index)+1.0)/float(samples));
			blurred += texture(scene_image,clamp(uv+offset,vec2(0.001),vec2(0.999))).rgb;
		}
		color = blurred/float(samples+1);
	}
	if (ssao_enabled && depth < 180.0) {
		vec3 normal = normalize(cross(dFdx(origin),dFdy(origin)));
		if (dot(normal,-origin)<0.0) { normal=-normal; }
		float occlusion=0.0;
		float radius=0.8;
		float screen_radius=clamp(radius*PROJECTION_MATRIX[1][1]/depth*0.5,0.001,0.05);
		int samples=quality >= 2 ? 12 : 6;
		for (int index=0;index<12;index++) {
			if (index >= samples) { break; }
			float angle=float(index)*2.399963;
			vec2 offset=vec2(cos(angle),sin(angle))*screen_radius*sqrt((float(index)+1.0)/float(samples));
			vec3 difference=view_position(clamp(uv+offset,vec2(0.001),vec2(0.999)),INV_PROJECTION_MATRIX)-origin;
			float distance=length(difference);
			float facing=max(dot(normal,difference/max(distance,0.0001))-0.1,0.0);
			occlusion += facing*smoothstep(radius,0.0,distance)*step(0.025,distance);
		}
		color *= 1.0-clamp(occlusion/float(samples)*ssao_strength*2.0,0.0,0.65);
	}
	ALBEDO=color;
	ALPHA=1.0;
}
