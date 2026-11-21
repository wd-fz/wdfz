shader_type spatial;
render_mode unshaded, cull_front, fog_disabled, shadows_disabled;

void vertex() {
	VERTEX += NORMAL * 0.045;
}

void fragment() {
	ALBEDO = vec3(1.0, 0.60, 0.16);
}
