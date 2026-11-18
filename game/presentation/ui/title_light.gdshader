shader_type canvas_item;
render_mode unshaded;

uniform float progress : hint_range(0.0, 1.0) = 0.0;
uniform float title_width = 240.0;
varying float text_x;

void vertex() {
	text_x = VERTEX.x / max(title_width, 1.0);
}

void fragment() {
	float head = mix(-0.25, 1.23, progress);
	float reveal = 1.0 - smoothstep(head - 0.12, head + 0.18, text_x);
	float light = 1.0 - smoothstep(0.0, 0.13, abs(text_x - head));
	COLOR.rgb = mix(COLOR.rgb, vec3(0.62, 0.88, 1.0), light * 0.75);
	COLOR.a *= mix(0.46, 1.0, reveal);
}
