shader_type canvas_item;
render_mode unshaded;
uniform sampler2D screen_image : hint_screen_texture, repeat_disable, filter_linear_mipmap;
uniform sampler2D lens_dust : repeat_disable, filter_linear;
uniform sampler2D flare_image : repeat_disable, filter_linear;
uniform sampler2D flare_ghost : repeat_disable, filter_linear;
uniform sampler2D hurt_sprite : repeat_disable, filter_linear;
uniform sampler2D hurt_ring : repeat_disable, filter_linear;
uniform bool fxaa_enabled = true;
uniform bool bloom_enabled = true;
uniform bool lens_enabled = true;
uniform bool flare_enabled = true;
uniform bool correction_enabled = true;
uniform bool tone_map_enabled = false;
uniform float saturation = 1.0;
uniform float enhancement = 0.7;
uniform vec3 tint = vec3(1.0);
uniform float exposure = 1.0;
uniform int quality = 1;
uniform float radial_blur = 0.0;
uniform vec2 camera_motion = vec2(0.0);
uniform float hurt_flash = 0.0;
uniform float hurt_edge = 0.0;
uniform float hurt_direction_fade = 0.0;
uniform float hurt_angle = 0.0;
uniform vec4 flare_sources[4];
uniform vec4 flare_colors[4];

float luma(vec3 value) { return dot(value, vec3(0.299, 0.587, 0.114)); }
vec3 sample_color(vec2 uv) { return texture(screen_image, clamp(uv, vec2(0.001), vec2(0.999))).rgb; }
vec3 aces(vec3 x) { return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), vec3(0.0), vec3(1.0)); }
vec3 antialias(vec2 uv, vec2 pixel) {
	vec3 center = sample_color(uv);
	vec3 nw = sample_color(uv + pixel * vec2(-1.0,-1.0));
	vec3 ne = sample_color(uv + pixel * vec2(1.0,-1.0));
	vec3 sw = sample_color(uv + pixel * vec2(-1.0,1.0));
	vec3 se = sample_color(uv + pixel * vec2(1.0,1.0));
	float low = min(luma(center), min(min(luma(nw),luma(ne)),min(luma(sw),luma(se))));
	float high = max(luma(center), max(max(luma(nw),luma(ne)),max(luma(sw),luma(se))));
	vec2 direction = vec2(-((luma(nw)+luma(ne))-(luma(sw)+luma(se))), (luma(nw)+luma(sw))-(luma(ne)+luma(se)));
	float reduction = max((luma(nw)+luma(ne)+luma(sw)+luma(se)) * 0.03125, 0.0078125);
	direction = clamp(direction / (min(abs(direction.x),abs(direction.y)) + reduction), vec2(-8.0),vec2(8.0)) * pixel;
	vec3 a = 0.5 * (sample_color(uv + direction * -0.16667) + sample_color(uv + direction * 0.16667));
	vec3 b = a * 0.5 + 0.25 * (sample_color(uv + direction * -0.5) + sample_color(uv + direction * 0.5));
	return luma(b) < low || luma(b) > high ? a : b;
}
vec3 flare(vec2 uv, vec2 center, float radius, vec3 color, vec2 pixel_size) {
	vec2 aspect = vec2(pixel_size.y / pixel_size.x,1.0);
	vec2 coord = (uv-center)*aspect/max(radius,0.00001)+0.5;
	if (any(lessThan(coord,vec2(0.0))) || any(greaterThan(coord,vec2(1.0)))) { return vec3(0.0); }
	vec4 image = texture(flare_image,coord);
	return image.rgb * image.a * color;
}
void fragment() {
	vec2 uv = SCREEN_UV;
	vec2 from_center = uv - 0.5;
	vec3 color = fxaa_enabled ? antialias(uv,SCREEN_PIXEL_SIZE) : sample_color(uv);
	if (radial_blur > 0.0001 || length(camera_motion) > 0.0001) {
		vec3 blurred = color;
		for (int index=1;index<5;index++) {
			float amount = float(index)/4.0;
			blurred += sample_color(uv - from_center*radial_blur*0.06*amount + camera_motion*amount);
		}
		color = blurred/5.0;
	}
	if (lens_enabled) {
		vec2 shift = from_center*0.008;
		color.r = mix(color.r,sample_color(uv+shift*0.7).r,0.65);
		color.b = mix(color.b,sample_color(uv-shift*0.3).b,0.65);
		color *= 1.0-0.12*dot(from_center,from_center);
	}
	if (bloom_enabled) {
		vec3 glow = vec3(0.0);
		// Generated screen mip levels approximate the source downsample pyramid.
		float lod = quality == 0 ? 2.0 : (quality == 1 ? 3.0 : 4.0);
		float weight_sum = 0.0;
		for (int y=-1;y<=1;y++) {
			for (int x=-1;x<=1;x++) {
				float weight = (x == 0 ? 2.0 : 1.0)*(y == 0 ? 2.0 : 1.0);
				vec2 shift = vec2(float(x),float(y))*SCREEN_PIXEL_SIZE*exp2(lod);
				vec3 bright = textureLod(screen_image,clamp(uv+shift,vec2(0.001),vec2(0.999)),lod).rgb;
				glow += bright*max(luma(bright)-0.45,0.0)*weight;
				weight_sum += weight;
			}
		}
		vec3 dust = texture(lens_dust,uv).rgb;
		color += glow/weight_sum*(vec3(0.45)+dust*0.35);
	}
	if (flare_enabled) {
		for (int index=0;index<4;index++) {
			vec4 source = flare_sources[index];
			if (source.w <= 0.0) { continue; }
			vec3 light = flare_colors[index].rgb*source.w;
			color += flare(uv,source.xy,source.z*3.0,light*0.18,SCREEN_PIXEL_SIZE);
			color += flare(uv,source.xy,source.z,light*0.7,SCREEN_PIXEL_SIZE);
			vec2 ghost_position = mix(source.xy,vec2(0.5),1.5);
			vec2 aspect = vec2(SCREEN_PIXEL_SIZE.y/SCREEN_PIXEL_SIZE.x,1.0);
			vec2 coord = (uv-ghost_position)*aspect/max(source.z*2.0,0.0001)+0.5;
			if (all(greaterThanEqual(coord,vec2(0.0))) && all(lessThanEqual(coord,vec2(1.0)))) {
				vec4 ghost = texture(flare_ghost,coord);
				color += ghost.rgb*ghost.a*light*0.1;
			}
		}
	}
	if (correction_enabled || tone_map_enabled) {
		color *= tint*exposure;
		vec3 gray = vec3((color.r+color.g+color.b)/3.0);
		color = mix(gray,color,saturation);
		if (tone_map_enabled) { color = sqrt(aces(color*color*0.8)); }
		if (correction_enabled) { color = mix(color,smoothstep(vec3(0.0),vec3(1.0),color),enhancement); }
	}
	// Client_Draw.cpp: screen multiplication + .1 red overlay, .35 s decay.
	color.gb *= 1.0-hurt_flash;
	color = mix(color,vec3(1.0,0.0,0.0),hurt_flash*0.1);
	if (hurt_edge > 0.0) {
		float angle = atan(from_center.y,from_center.x);
		vec2 coord = vec2(fract(angle/6.283185+0.5),clamp((length(from_center)-0.25)*3.0,0.0,1.0));
		float alpha = texture(hurt_sprite,coord).a*smoothstep(0.25,0.58,length(from_center));
		color *= 1.0-alpha*hurt_edge;
	}
	if (hurt_direction_fade > 0.0) {
		float c=cos(hurt_angle); float s=sin(hurt_angle);
		vec2 ring_uv = mat2(vec2(c,-s),vec2(s,c))*from_center/0.3+vec2(0.5,0.0);
		if (all(greaterThanEqual(ring_uv,vec2(0.0))) && all(lessThanEqual(ring_uv,vec2(1.0)))) {
			vec4 ring = texture(hurt_ring,ring_uv);
			color += ring.rgb*ring.a*hurt_direction_fade;
		}
	}
	COLOR = vec4(color,1.0);
}
