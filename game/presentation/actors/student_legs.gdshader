shader_type spatial;
render_mode cull_back;
void fragment() {
	if (UV.x < 0.95) { discard; }
	ALBEDO = COLOR.rgb;
	ROUGHNESS = 0.85;
}
