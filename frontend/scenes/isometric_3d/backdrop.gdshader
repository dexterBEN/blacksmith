shader_type spatial;
render_mode ambient_light_disabled, specular_disabled;

uniform sampler2D backdrop_texture : source_color, filter_linear, repeat_disable;
varying flat vec2 backdrop_crop;

void vertex() {
	vec2 image_size = vec2(textureSize(backdrop_texture, 0));
	float image_aspect = image_size.x / image_size.y;
	float viewport_aspect = VIEWPORT_SIZE.x / VIEWPORT_SIZE.y;
	// Centered cover: preserve the artwork's proportions, crop excess edges.
	backdrop_crop = vec2(min(1.0, viewport_aspect / image_aspect),
		min(1.0, image_aspect / viewport_aspect));
}

void fragment() {
	vec2 uv = (SCREEN_UV - vec2(0.5)) * backdrop_crop + vec2(0.5);
	ALBEDO = texture(backdrop_texture, uv).rgb;
	SPECULAR = 0.0;
	ROUGHNESS = 1.0;
}

void light() {
	// Ground receives only the existing key light. Keep its native shadows,
	// without tinting the artwork or adding a second background draw pass.
	DIFFUSE_LIGHT += vec3(ATTENUATION);
}
