shader_type canvas_item;
// Side main menu: crawling background shadow, black-iron spine, a cracked water-stained frosted-glass
// panel joined to the spine by a concave seam (it tears open from the spine on entry), the "peephole" of
// the active item, and the green shadow pulse after a choice. Signed distance fields for every shape.
//
// Cost-conscious version (2026-11-11): no screen-texture read (that copied and mip-mapped the whole frame
// every frame); the shell is alpha-composited over whatever is behind it. All noise comes from one
// pre-baked tileable FBM texture (u_noise) instead of per-pixel procedural octaves, and the frosted glass
// samples a tiny pre-blurred copy of the menu background (u_frost). All rects are in pixels of this rect.

uniform sampler2D u_noise : repeat_enable, filter_linear;
uniform sampler2D u_frost : filter_linear;
uniform vec2 u_size = vec2(960.0, 540.0);
uniform float u_time = 0.0;
uniform vec4 u_spine = vec4(0.0, 0.0, 14.0, 540.0);
uniform vec4 u_body = vec4(14.0, 240.0, 46.0, 300.0);
uniform float u_radius = 10.0;
uniform float u_seam = 18.0;           // smooth-union width of the concave seam
uniform float u_open = 0.0;            // 0 torn sliver … 1 open panel (glass detail fades in)
uniform float u_tear = 0.0;            // ragged edge strength while the body tears open
uniform vec4 u_hole = vec4(0.0);       // the active item's wiped window (x0, y0, x1, y1)
uniform float u_hole_on = 0.0;
// Palette A (blood scab, abyss black) and B (corpse grey, ghost green); u_shift blends A→B.
uniform vec4 u_a0 : source_color = vec4(0.23, 0.035, 0.035, 1.0);
uniform vec4 u_a1 : source_color = vec4(0.012, 0.008, 0.012, 1.0);
uniform vec4 u_b0 : source_color = vec4(0.36, 0.40, 0.38, 1.0);
uniform vec4 u_b1 : source_color = vec4(0.18, 0.78, 0.48, 1.0);
uniform float u_shift = 0.0;
uniform vec2 u_pulse_origin = vec2(0.0);
uniform float u_pulse_r = 0.0;
uniform float u_pulse_a = 0.0;
uniform float u_refraction = 1.0;      // glass distortion (0 clean … 2 heavy)
uniform float u_stain = 1.0;           // cracks and water stains (0 clean … 2 heavy)
uniform float u_bg_dim = 0.5;          // how much the crawling shadow covers the background
uniform float u_motion = 1.0;          // 0 for reduced motion: everything holds still

// One fetch of the baked FBM (0…1). The texture tiles, so any scale or offset is seamless.
float fbm(vec2 p) {
	return texture(u_noise, p * 0.25).r;
}

// Ridged lines for cracks, from the same texture.
float ridged(vec2 p) {
	float n = 1.0 - abs(texture(u_noise, p * 0.25 + 0.37).r * 2.0 - 1.0);
	return n * n;
}

float sd_box(vec2 p, vec4 r, float rad) {
	vec2 c = (r.xy + r.zw) * 0.5;
	vec2 hs = max((r.zw - r.xy) * 0.5 - rad, vec2(0.0));
	vec2 d = abs(p - c) - hs;
	return length(max(d, 0.0)) + min(max(d.x, d.y), 0.0) - rad;
}

float smin(float a, float b, float k) {
	float hh = clamp(0.5 + 0.5 * (b - a) / k, 0.0, 1.0);
	return mix(b, a, hh) - k * hh * (1.0 - hh);
}

// Premultiplied accumulation over the unseen background: final = background * (1 - acc.a) + acc.rgb.
vec4 toward(vec4 acc, vec3 c, float k) {
	k = clamp(k, 0.0, 1.0);
	return vec4(acc.rgb * (1.0 - k) + c * k, acc.a * (1.0 - k) + k);
}

void fragment() {
	vec2 px = UV * u_size;
	float t = u_time * u_motion;
	float h = u_size.y;
	vec2 nuv = px / h;

	// ---- background: a slowly crawling shadow over the campus ----
	vec2 crawl = vec2(t * 0.012, -t * 0.008);
	float n1 = fbm(nuv * 2.2 + crawl + vec2(fbm(nuv * 1.3 - crawl * 1.7), 0.0));
	vec3 pal_a = mix(u_a1.rgb, u_a0.rgb, smoothstep(0.35, 0.85, n1));
	vec3 pal_b = mix(u_b0.rgb * 0.35, u_b1.rgb * 0.55, smoothstep(0.4, 0.9, n1));
	vec3 shade = mix(pal_a, pal_b, u_shift);
	float side = smoothstep(0.95, 0.15, UV.x);
	vec4 acc = toward(vec4(0.0), shade, u_bg_dim * (0.55 + 0.45 * side) + 0.18 * (1.0 - n1));
	float vig = smoothstep(0.35, 1.15, length((UV - vec2(0.55, 0.5)) * vec2(1.1, 1.35)));
	acc = toward(acc, u_a1.rgb, vig * 0.85);

	// ---- the shadow pulse after a choice ----
	if (u_pulse_a > 0.001) {
		float dist = length(px - u_pulse_origin);
		float front = u_pulse_r + (n1 - 0.5) * h * 0.08;
		float inside = smoothstep(front + 2.0, front - h * 0.25, dist);
		float ring = exp(-pow((dist - front) / (h * 0.035), 2.0));
		vec3 green = mix(u_b0.rgb, u_b1.rgb, 0.5 + 0.5 * n1);
		acc = toward(acc, green * (0.35 + 0.65 * ring), u_pulse_a * (0.55 * inside + 0.9 * ring));
	}

	// ---- spine and body (joined with a concave seam) ----
	float d_spine = sd_box(px, u_spine, 0.0);
	float ragged = 0.0;
	if (u_tear > 0.001) {
		ragged = (fbm(vec2(px.x * 0.06, px.y * 0.135) + vec2(t * 0.6, 0.0)) - 0.5) * u_tear * h * 0.05;
	}
	float d_body = sd_box(px, u_body, u_radius) + ragged;
	float d_shell = smin(d_spine, d_body, u_seam);
	float in_shell = smoothstep(1.2, -1.2, d_shell);
	// Drop shadow beside the shell.
	acc = toward(acc, vec3(0.0), smoothstep(h * 0.06, 0.0, d_shell) * (1.0 - in_shell) * 0.5);

	if (in_shell > 0.0) {
		float in_body = smoothstep(1.2, -1.2, d_body - u_seam * 0.35);
		float rust = fbm(nuv * vec2(9.0, 3.5) + 4.2);
		vec3 iron = mix(vec3(0.035, 0.032, 0.034), vec3(0.11, 0.05, 0.04), smoothstep(0.55, 0.85, rust));
		float rivets = smoothstep(0.25, 0.0, abs(fract(px.y / (h * 0.07)) - 0.5) * 2.0 - 0.75) * step(abs(px.x - (u_spine.x + u_spine.z) * 0.5), (u_spine.z - u_spine.x) * 0.18);
		iron += vec3(0.06, 0.05, 0.05) * rivets;
		iron += vec3(0.05) * smoothstep(3.0, 0.0, abs(px.x - u_spine.z + 1.5));

		// Glass: the pre-blurred background bent by stains, tinted near-black.
		float s1 = fbm(nuv * 6.0 + 1.3);
		vec2 warp = vec2(s1, fbm(nuv * 6.0 + 7.9)) - 0.5;
		vec3 frost = texture(u_frost, UV + warp * 0.018 * u_refraction).rgb;
		vec3 tint_a = mix(u_a1.rgb * 1.6, u_a0.rgb * 0.45, 0.35);
		vec3 tint_b = mix(u_b0.rgb * 0.18, u_b1.rgb * 0.22, 0.5);
		vec3 glass = mix(frost * 0.32, mix(tint_a, tint_b, u_shift), 0.62);
		float under = exp(-max(px.x - u_spine.z, 0.0) / (h * 0.16)) * (0.55 + 0.45 * n1);
		glass += mix(u_a0.rgb, u_b1.rgb * 0.6, u_shift) * under * 0.55;
		// Hairline cracks: the ridge of a finer sample, kept thin and faint.
		float crack = smoothstep(0.93, 0.995, ridged(nuv * 26.0 + 2.3)) * u_stain;
		float stain = smoothstep(0.012, 0.0, abs(s1 - 0.58)) * 0.35 + smoothstep(0.6, 0.78, s1) * 0.2;
		glass += vec3(0.16, 0.15, 0.16) * crack * 0.4;
		glass = mix(glass, frost * 0.5 + vec3(0.02, 0.025, 0.03), stain * 0.35 * u_stain);
		float edge = smoothstep(h * 0.012, 0.0, abs(d_body)) * u_open;
		glass += vec3(0.62, 0.68, 0.72) * edge * 0.28 * (0.6 + 0.4 * n1);
		// While still a torn sliver the glass glows blood-red from inside.
		glass = mix(u_a0.rgb * (0.7 + 0.6 * n1), glass, smoothstep(0.0, 0.55, u_open));

		float clear = 0.0;
		if (u_hole_on > 0.001) {
			float r_hole = min(u_hole.w - u_hole.y, u_hole.z - u_hole.x) * 0.3;
			float smear = (fbm(vec2(px.x * 0.05, px.y * 0.6) + t * 0.05) - 0.5) * h * 0.012;
			float d_hole = sd_box(px, u_hole, r_hole) + smear;
			float hole = smoothstep(2.0, -h * 0.012, d_hole) * u_hole_on;
			vec3 blood = mix(vec3(0.78, 0.07, 0.05), u_b1.rgb, u_shift);
			// Wiped clear: the real background shows through (alpha drops), tinted by the red light.
			glass = mix(glass, blood * 0.35 * (0.75 + 0.25 * n1), hole);
			clear = hole * 0.55;
			float rim = exp(-abs(d_hole) / (h * 0.006)) * 0.55 + exp(-max(d_hole, 0.0) / (h * 0.022)) * 0.25 * step(0.0, d_hole);
			glass += blood * rim * (0.7 + 0.3 * n1) * u_hole_on;
		}
		vec3 shell = mix(iron, glass, in_body);
		acc = toward(acc, shell, in_shell * (1.0 - clear * in_body));
	}
	COLOR = acc.a > 0.0001 ? vec4(acc.rgb / acc.a, acc.a) : vec4(0.0);
}
