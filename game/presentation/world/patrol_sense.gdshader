shader_type spatial;
render_mode unshaded, depth_test_disabled, depth_draw_never, fog_disabled, shadows_disabled;

void fragment() {
	float rim = pow(1.0 - max(dot(normalize(NORMAL), normalize(VIEW)), 0.0), 2.0);
	ALBEDO = vec3(1.0, 0.24, 0.16);
	ALPHA = 0.34 + rim * 0.48;
}
