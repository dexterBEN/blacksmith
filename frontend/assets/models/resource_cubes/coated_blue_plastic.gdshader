shader_type spatial;

uniform sampler2D albedo_texture : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform vec4 body_tint : source_color = vec4(0.42, 0.58, 0.9, 1.0);
uniform float roughness : hint_range(0.0, 1.0) = 0.38;
uniform float specular : hint_range(0.0, 1.0) = 0.25;
uniform float clearcoat : hint_range(0.0, 1.0) = 0.18;
uniform bool replace_front_icon = false;
uniform sampler2D service_icon : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform float icon_scale : hint_range(0.1, 0.9) = 0.7;

void fragment() {
	vec3 artwork = texture(albedo_texture, UV).rgb;
	// Calibrate only the blue pigment: a global tint would also turn icons blue.
	// The supplied white icons have high R/G/B; the blue body has a low R value.
	float icon = smoothstep(0.55, 0.92, min(artwork.r, min(artwork.g, artwork.b)));
	ALBEDO = artwork * mix(body_tint.rgb, vec3(1.0), icon);
	bool front_face = UV.x >= 0.25 && UV.x <= 0.5 && UV.y >= 1.0 / 3.0 && UV.y <= 2.0 / 3.0;
	if (replace_front_icon && front_face) {
		// Recover the front's blue gradient from its clean left/right margins.
		// This removes the old painted symbol without altering the source PNG.
		vec2 face_uv = vec2((UV.x - 0.25) * 4.0, (UV.y - 1.0 / 3.0) * 3.0);
		vec3 left = texture(albedo_texture, vec2(0.255, UV.y)).rgb;
		vec3 right = texture(albedo_texture, vec2(0.495, UV.y)).rgb;
		vec3 body = mix(left, right, clamp((UV.x - 0.255) / 0.24, 0.0, 1.0)) * body_tint.rgb;
		vec2 icon_uv = (face_uv - vec2(0.5)) / icon_scale + vec2(0.5);
		float inside = step(0.0, icon_uv.x) * step(icon_uv.x, 1.0) * step(0.0, icon_uv.y) * step(icon_uv.y, 1.0);
		vec4 glyph = texture(service_icon, clamp(icon_uv, vec2(0.0), vec2(1.0)));
		ALBEDO = mix(body, glyph.rgb, glyph.a * inside);
	}
	METALLIC = 0.0;
	ROUGHNESS = roughness;
	SPECULAR = specular;
	CLEARCOAT = clearcoat;
	CLEARCOAT_ROUGHNESS = 0.3;
}
