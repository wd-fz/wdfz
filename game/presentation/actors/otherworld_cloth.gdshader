shader_type spatial;
render_mode diffuse_lambert, specular_disabled;

// A little diffuse fill keeps the painted sockets and uniform legible in campus fog.
// The same opaque pass writes depth for the coat, eyes, hair and insignia.
void fragment() {
	ALBEDO = COLOR.rgb;
	ROUGHNESS = 1.0;
	EMISSION = COLOR.rgb * 0.17;
}
