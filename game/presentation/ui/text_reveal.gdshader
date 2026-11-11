shader_type canvas_item;
// Menu text surfacing out of defocus and noise: blurred (TEXTURE averaged around the glyph) and
// dissolved by coarse flickering noise while u_reveal < 1; sharp and solid at 1.

uniform float u_reveal = 1.0;
uniform float u_time = 0.0;
varying vec4 v_color;

void vertex() {
	v_color = COLOR;
}

float hash(vec2 p) {
	p = fract(p * vec2(443.897, 441.423));
	p += dot(p, p.yx + 19.19);
	return fract((p.x + p.y) * p.x);
}

void fragment() {
	float r = clamp(u_reveal, 0.0, 1.0);
	vec4 sharp = texture(TEXTURE, UV);
	if (r >= 0.999) {
		COLOR = v_color * sharp;
	} else {
		vec2 s = TEXTURE_PIXEL_SIZE * (1.0 - r) * 3.0;
		vec4 blur = sharp * 0.2;
		blur += texture(TEXTURE, UV + vec2(s.x, 0.0)) * 0.1;
		blur += texture(TEXTURE, UV - vec2(s.x, 0.0)) * 0.1;
		blur += texture(TEXTURE, UV + vec2(0.0, s.y)) * 0.1;
		blur += texture(TEXTURE, UV - vec2(0.0, s.y)) * 0.1;
		blur += texture(TEXTURE, UV + s) * 0.1;
		blur += texture(TEXTURE, UV - s) * 0.1;
		blur += texture(TEXTURE, UV + vec2(s.x, -s.y)) * 0.1;
		blur += texture(TEXTURE, UV + vec2(-s.x, s.y)) * 0.1;
		vec4 c = mix(blur, sharp, r * r);
		float grain = hash(floor(FRAGCOORD.xy / 2.0) + floor(u_time * 20.0));
		float keep = step(grain, r * 1.25);
		COLOR = v_color * c;
		COLOR.a *= r * mix(1.0, keep, 1.0 - r);
	}
}
