shader_type canvas_item;
// Boot animation backdrop: black with breathing grain; a blood crack opens down the left edge (where the
// menu spine will be); a heartbeat glow behind the title; at the end the black bleeds away from the crack
// to show the menu. Timeline driven by u_t (seconds) from boot_splash.gd.

uniform sampler2D u_noise : repeat_enable, filter_linear;
uniform vec2 u_size = vec2(960.0, 540.0);
uniform float u_t = 0.0;
uniform float u_crack = 0.0;      // 0…1 crack length (grows from the middle outwards)
uniform float u_glow = 0.0;       // heartbeat glow behind the title
uniform vec2 u_glow_at = vec2(0.32, 0.46);
uniform float u_bleed = 0.0;      // 0 solid black … 1 fully gone (the menu shows)
uniform float u_spine_x = 14.0;   // the spine's right edge in pixels
uniform float u_motion = 1.0;
uniform vec4 u_blood : source_color = vec4(0.62, 0.05, 0.04, 1.0);

float hash(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

// One fetch of the baked tileable FBM shared with the menu (SideMenu.noise_texture()).
float fbm(vec2 p) {
	return texture(u_noise, p * 0.25).r;
}

void fragment() {
	vec2 px = UV * u_size;
	float h = u_size.y;
	vec2 nuv = px / h;
	float t = u_t * u_motion;
	vec3 col = vec3(0.006, 0.004, 0.006);
	// Breathing grain.
	float grain = hash(floor(px / 2.0) + floor(t * 18.0));
	col += vec3(0.022, 0.012, 0.014) * grain * u_motion;
	// Slow smoke of dried blood.
	float smoke = fbm(nuv * 2.4 + vec2(t * 0.03, -t * 0.02));
	col += vec3(0.09, 0.015, 0.015) * smoothstep(0.55, 0.9, smoke) * 0.6;
	// The crack: a ragged vertical line down the spine position, growing from the middle.
	float half_len = u_crack * 0.5 * h;
	float dy = abs(px.y - h * 0.5);
	float along = smoothstep(half_len, half_len - h * 0.04, dy);
	float wob = (fbm(vec2(px.y * 0.03, 3.0)) - 0.5) * h * 0.012;
	float dx = abs(px.x - u_spine_x * 0.5 - wob);
	float core = exp(-dx / (h * 0.0025)) * along;
	float haze = exp(-dx / (h * 0.03)) * along;
	col += u_blood.rgb * (core * 1.6 + haze * 0.35);
	// Heartbeat glow behind the title.
	float g = exp(-pow(length((UV - u_glow_at) * vec2(u_size.x / h, 1.0)) / 0.22, 2.0));
	col += u_blood.rgb * g * u_glow * 0.45;
	// Bleed away: the black recedes from the crack outwards with a noisy front.
	float front = u_bleed * (u_size.x + h * 0.4);
	float edge = px.x - u_spine_x + (fbm(nuv * 5.0 + t * 0.2) - 0.5) * h * 0.25;
	float gone = smoothstep(0.0, h * 0.2, front - edge);
	float alpha = 1.0 - clamp(gone * step(0.001, u_bleed), 0.0, 1.0);
	col += u_blood.rgb * exp(-abs(edge - front) / (h * 0.03)) * 0.4 * step(0.001, u_bleed) * (1.0 - u_bleed);
	COLOR = vec4(col, alpha);
}
