shader_type spatial;
render_mode specular_disabled;

// The pale mask shines in the dark while its vertex-painted mouth and eyes stay black.
void fragment() {
	ALBEDO = vec3(0.0);
	EMISSION = COLOR.rgb * 1.18;
}
