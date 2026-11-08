shader_type spatial;
render_mode unshaded, depth_draw_never, shadows_disabled;

uniform vec4 dust_color : source_color = vec4(0.188235294, 0.188235294, 0.188235294, 0.65);
uniform float point_size = 0.012;

void vertex() {
	// Three.js PointsMaterial uses half the viewport height, independent of the camera FOV.
	float depth = -(MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).z;
	POINT_SIZE = max(1.0, point_size * VIEWPORT_SIZE.y * 0.5 / max(0.001, depth));
}

void fragment() {
	ALBEDO = dust_color.rgb;
	ALPHA = dust_color.a;
}
