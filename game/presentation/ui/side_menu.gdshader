shader_type canvas_item;
// Side main menu: crawling background shadow, black-iron spine, a torn rune tag that tears open into a
// cracked, water-stained frosted-glass panel joined to the spine by a concave seam, the "peephole" of
// the active item, and the green shadow pulse after a choice. FBM noise for every texture, signed
// distance fields for every shape. All rects arrive in pixels of this ColorRect (origin top-left).

uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform vec2 u_size = vec2(960.0, 540.0);
uniform float u_time = 0.0;
// Spine rect (x0, y0, x1, y1) and the morphing body: the folded tag, the torn strip, then the panel.
uniform vec4 u_spine = vec4(0.0, 0.0, 14.0, 540.0);
uniform vec4 u_body = vec4(14.0, 240.0, 46.0, 300.0);
uniform float u_radius = 10.0;
uniform float u_seam = 18.0;           // smooth-union width of the concave seam
uniform float u_open = 0.0;            // 0 folded tag … 1 open panel (glass detail fades in)
uniform float u_tear = 0.0;            // ragged edge strength while the body tears / folds
uniform float u_hover = 0.0;           // pointer near the folded tag
uniform float u_beat = 0.0;            // heartbeat swell 0…1
// The active item: a wiped-clear window in the glass (x0, y0, x1, y1) and how present it is.
uniform vec4 u_hole = vec4(0.0);
uniform float u_hole_on = 0.0;
// Palette A (blood scab, abyss black) and B (corpse grey, ghost green); u_shift blends A→B.
uniform vec4 u_a0 : source_color = vec4(0.23, 0.035, 0.035, 1.0);
uniform vec4 u_a1 : source_color = vec4(0.012, 0.008, 0.012, 1.0);
uniform vec4 u_b0 : source_color = vec4(0.36, 0.40, 0.38, 1.0);
uniform vec4 u_b1 : source_color = vec4(0.18, 0.78, 0.48, 1.0);
uniform float u_shift = 0.0;
uniform vec2 u_pulse_origin = vec2(0.0);
uniform float u_pulse_r = 0.0;         // radius of the spreading pulse front in pixels
uniform float u_pulse_a = 0.0;         // strength of the pulse
uniform float u_refraction = 1.0;      // glass distortion (0 clean … 2 heavy)
uniform float u_stain = 1.0;           // cracks and water stains (0 clean … 2 heavy)
uniform float u_bg_dim = 0.62;         // how much the crawling shadow covers the live campus
uniform float u_motion = 1.0;          // 0 for reduced motion: everything holds still

float hash(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	mat2 r = mat2(vec2(0.8, 0.6), vec2(-0.6, 0.8));
	for (int i = 0; i < 5; i++) {
		v += a * vnoise(p);
		p = r * p * 2.03 + 11.7;
		a *= 0.5;
	}
	return v;
}

// Ridged FBM: thin bright lines for cracks.
float ridged(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 4; i++) {
		float n = 1.0 - abs(vnoise(p) * 2.0 - 1.0);
		v += a * n * n;
		p = p * 2.17 + 3.1;
		a *= 0.5;
	}
	return v;
}

float sd_box(vec2 p, vec4 r, float rad) {
	vec2 c = (r.xy + r.zw) * 0.5;
	vec2 h = max((r.zw - r.xy) * 0.5 - rad, vec2(0.0));
	vec2 d = abs(p - c) - h;
	return length(max(d, 0.0)) + min(max(d.x, d.y), 0.0) - rad;
}

// Polynomial smooth minimum: the concave fillet between spine and body.
float smin(float a, float b, float k) {
	float h = clamp(0.5 + 0.5 * (b - a) / k, 0.0, 1.0);
	return mix(b, a, h) - k * h * (1.0 - h);
}

float sd_segment(vec2 p, vec2 a, vec2 b) {
	vec2 pa = p - a;
	vec2 ba = b - a;
	float h = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
	return length(pa - ba * h);
}

// A broken rune scratched into the tag: a stem, two hooks and a cut, eaten away by noise.
float rune(vec2 p, vec4 r, float t) {
	vec2 c = (r.xy + r.zw) * 0.5;
	float s = min(r.z - r.x, r.w - r.y) * 0.34;
	vec2 q = (p - c) / max(s, 1.0);
	float d = sd_segment(q, vec2(0.0, -1.0), vec2(0.0, 1.0));
	d = min(d, sd_segment(q, vec2(0.0, -0.55), vec2(-0.55, -0.9)));
	d = min(d, sd_segment(q, vec2(0.0, -0.05), vec2(0.6, -0.45)));
	d = min(d, sd_segment(q, vec2(0.0, 0.4), vec2(-0.5, 0.75)));
	d = min(d, sd_segment(q, vec2(-0.35, 0.15), vec2(0.35, 0.15)));
	float erode = fbm(q * 3.0 + vec2(0.0, t * 0.05));
	return smoothstep(0.16, 0.07, d) * smoothstep(0.28, 0.5, erode);
}

void fragment() {
	vec2 px = UV * u_size;
	float t = u_time * u_motion;
	float h = u_size.y;
	vec2 nuv = px / h;

	// ---- background: the live campus seen through a slowly crawling shadow ----
	vec3 scene = texture(screen_tex, SCREEN_UV).rgb;
	vec2 crawl = vec2(t * 0.012, -t * 0.008);
	float n1 = fbm(nuv * 2.2 + crawl + vec2(fbm(nuv * 1.3 - crawl * 1.7), 0.0));
	vec3 pal_a = mix(u_a1.rgb, u_a0.rgb, smoothstep(0.35, 0.85, n1));
	vec3 pal_b = mix(u_b0.rgb * 0.35, u_b1.rgb * 0.55, smoothstep(0.4, 0.9, n1));
	vec3 shade = mix(pal_a, pal_b, u_shift);
	// Heavier on the menu side, thinner over the right where the campus turns.
	float side = smoothstep(0.95, 0.15, UV.x);
	float veil = clamp(u_bg_dim * (0.55 + 0.45 * side) + 0.18 * (1.0 - n1), 0.0, 0.94);
	vec3 col = mix(scene, shade, veil);
	// Edge darkness (the abyss).
	float vig = smoothstep(0.35, 1.15, length((UV - vec2(0.55, 0.5)) * vec2(1.1, 1.35)));
	col = mix(col, u_a1.rgb, vig * 0.85);

	// ---- the shadow pulse after a choice: a viscous ring spreading out from the chosen item ----
	if (u_pulse_a > 0.001) {
		float dist = length(px - u_pulse_origin);
		float wob = (fbm(nuv * 4.0 + t * 0.3) - 0.5) * h * 0.08;
		float front = u_pulse_r + wob;
		float inside = smoothstep(front + 2.0, front - h * 0.25, dist);
		float ring = exp(-pow((dist - front) / (h * 0.035), 2.0));
		vec3 green = mix(u_b0.rgb, u_b1.rgb, 0.5 + 0.5 * n1);
		col = mix(col, green * (0.35 + 0.65 * ring), clamp(u_pulse_a * (0.55 * inside + 0.9 * ring), 0.0, 1.0));
	}

	// ---- spine: mottled black iron ----
	float d_spine = sd_box(px, u_spine, 0.0);
	// ---- body: tag → torn strip → glass panel, joined to the spine with a concave seam ----
	vec2 tear_p = vec2(px.x * 0.02, px.y * 0.045);
	float ragged = (fbm(tear_p * 3.0 + vec2(t * 0.6, 0.0)) - 0.5) * u_tear * h * 0.05;
	float d_body = sd_box(px, u_body, u_radius) + ragged;
	float d_shell = smin(d_spine, d_body, u_seam);
	float aa = 1.2;
	float in_shell = smoothstep(aa, -aa, d_shell);
	float in_body = smoothstep(aa, -aa, d_body - u_seam * 0.35);

	if (in_shell > 0.0) {
		// Iron: near-black with rust blotches and vertical rivet lines.
		float rust = fbm(nuv * vec2(9.0, 3.5) + 4.2);
		vec3 iron = mix(vec3(0.035, 0.032, 0.034), vec3(0.11, 0.05, 0.04), smoothstep(0.55, 0.85, rust));
		float rivets = smoothstep(0.25, 0.0, abs(fract(px.y / (h * 0.07)) - 0.5) * 2.0 - 0.75) * step(abs(px.x - (u_spine.x + u_spine.z) * 0.5), (u_spine.z - u_spine.x) * 0.18);
		iron += vec3(0.06, 0.05, 0.05) * rivets;
		iron += vec3(0.05) * smoothstep(3.0, 0.0, abs(px.x - u_spine.z + 1.5));

		// Glass: the background blurred (frosted) and bent by stains, tinted near-black.
		vec2 warp = vec2(fbm(nuv * 6.0 + 1.3), fbm(nuv * 6.0 + 7.9)) - 0.5;
		vec2 guv = SCREEN_UV + warp * 0.018 * u_refraction;
		vec3 frost = textureLod(screen_tex, guv, 3.6).rgb;
		vec3 tint_a = mix(u_a1.rgb * 1.6, u_a0.rgb * 0.45, 0.35);
		vec3 tint_b = mix(u_b0.rgb * 0.18, u_b1.rgb * 0.22, 0.5);
		vec3 glass = mix(frost * 0.32, mix(tint_a, tint_b, u_shift), 0.62);
		// Blood light leaking up from beneath, strongest along the seam.
		float under = exp(-max(px.x - u_spine.z, 0.0) / (h * 0.16)) * (0.55 + 0.45 * fbm(nuv * 3.0 + vec2(0.0, t * 0.04)));
		glass += mix(u_a0.rgb, u_b1.rgb * 0.6, u_shift) * under * 0.55;
		// Fine cracks and water stains (rings of darker, slightly clearer glass).
		float crack = smoothstep(0.62, 0.78, ridged(nuv * 7.0 + 2.3)) * u_stain;
		float stain_n = fbm(nuv * 4.5 + 9.1);
		float stain = smoothstep(0.02, 0.0, abs(stain_n - 0.58)) * 0.6 + smoothstep(0.55, 0.75, stain_n) * 0.25;
		glass += vec3(0.16, 0.15, 0.16) * crack * 0.55;
		glass = mix(glass, frost * 0.5 + vec3(0.02, 0.025, 0.03), stain * 0.35 * u_stain);
		// Damp refraction rim with a pale cold outline.
		float edge = smoothstep(h * 0.012, 0.0, abs(d_body)) * u_open;
		float wet = 0.6 + 0.4 * fbm(vec2(px.y * 0.04, t * 0.25));
		glass += vec3(0.62, 0.68, 0.72) * edge * 0.28 * wet;
		glass += textureLod(screen_tex, SCREEN_UV - warp * 0.03, 1.0).rgb * edge * 0.25;

		// The folded tag: dark red glimmer and the rune, swelling with the heartbeat.
		vec3 tag = mix(vec3(0.08, 0.02, 0.02), u_a0.rgb * 1.3, 0.35 + 0.35 * fbm(nuv * 8.0 + t * 0.1));
		float glow = 0.35 + 0.65 * (0.5 * u_hover + u_beat);
		tag += u_a0.rgb * 1.8 * rune(px, u_body, t) * glow;
		tag += vec3(0.5, 0.06, 0.05) * smoothstep(h * 0.02, 0.0, abs(d_body)) * glow * 0.6;
		glass = mix(tag, glass, smoothstep(0.0, 0.55, u_open));

		// The active item: a peephole wiped into the black fog, the red light seeping brighter through it.
		if (u_hole_on > 0.001) {
			float r_hole = min(u_hole.w - u_hole.y, u_hole.z - u_hole.x) * 0.3;
			float smear = (fbm(vec2(px.x * 0.02, px.y * 0.2) + t * 0.05) - 0.5) * h * 0.012;
			float d_hole = sd_box(px, u_hole, r_hole) + smear;
			float hole = smoothstep(2.0, -h * 0.012, d_hole) * u_hole_on;
			// Wiped clear: the campus shows sharper through it, tinted by the red light beneath.
			vec3 clear_v = textureLod(screen_tex, SCREEN_UV, 0.4).rgb * 0.75;
			vec3 blood = mix(vec3(0.78, 0.07, 0.05), u_b1.rgb, u_shift);
			float streak = 0.75 + 0.25 * fbm(vec2(px.x * 0.012, px.y * 0.16) + t * 0.03);
			glass = mix(glass, clear_v * 0.6 + blood * 0.2 * streak, hole);
			// The glare seeps out around the rim (strongest along the wiped edge, fading into the fog).
			float rim = exp(-abs(d_hole) / (h * 0.006)) * 0.55 + exp(-max(d_hole, 0.0) / (h * 0.022)) * 0.25 * step(0.0, d_hole);
			float flick = 0.7 + 0.3 * fbm(vec2(px.x * 0.03, t * 0.5));
			glass += blood * rim * flick * u_hole_on;
		}

		vec3 shell = mix(iron, glass, in_body);
		col = mix(col, shell, in_shell);
	}
	// A soft drop shadow beside the shell keeps the panel lifted off the campus.
	float drop = smoothstep(h * 0.06, 0.0, d_shell) * (1.0 - in_shell);
	col *= 1.0 - drop * 0.5;
	COLOR = vec4(col, 1.0);
}
