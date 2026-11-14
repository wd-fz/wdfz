shader_type canvas_item;
// A classroom wall clock drawn on a square rect: a grimy cream face in a dark rim, sixty ticks, black hour
// and minute hands and a thin red second hand. Shared by the boot animation (it ticks to 18:00 under a
// fluorescent tube) and the loading screen (the minute hand follows the progress). Lit from above by
// u_light; u_dread reddens and warps the face slightly for the moment something is wrong.

uniform float u_minutes = 1079.0;   // minutes since 12:00 (hour hand), any value; 1080 = 18:00
uniform float u_minute_hand = 59.0; // 0–60, the minute hand on its own (it may jump while the hour creeps)
uniform float u_second = 52.0;      // 0–60, the second hand
uniform float u_light = 1.0;        // 0 dark … 1 fully lit by the tube above
uniform float u_dread = 0.0;        // 0 normal … 1 red-tinged and warped
uniform float u_time = 0.0;
uniform vec4 u_blood : source_color = vec4(0.62, 0.05, 0.04, 1.0);


float hash(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

// Distance from p to a hand of the given angle (clockwise from 12), length and half width.
float hand(vec2 p, float turns, float len, float tail, float half_w) {
	float a = turns * TAU;
	vec2 dir = vec2(sin(a), -cos(a));
	float along = clamp(dot(p, dir), -tail, len);
	float d = length(p - dir * along);
	// Taper towards the tip.
	float w = half_w * mix(1.0, 0.45, clamp(along / len, 0.0, 1.0));
	return d - w;
}

void fragment() {
	vec2 p = (UV - 0.5) * 2.0;            // -1…1, the rim's outer edge at radius 1
	float aa = fwidth(p.x) * 1.2;
	// A faint warp when dread rises (the face breathes).
	p *= 1.0 + u_dread * 0.025 * sin(u_time * 7.0 + length(p) * 9.0);
	float r = length(p);
	if (r > 1.0 + aa) {
		discard;
	}
	// Face: cream with grime and a darker edge, lit from above.
	float grime = vnoise(p * 6.0) * 0.6 + vnoise(p * 23.0) * 0.4;
	vec3 face = mix(vec3(0.86, 0.82, 0.72), vec3(0.62, 0.57, 0.48), grime * 0.55 + smoothstep(0.5, 0.86, r) * 0.35);
	// Rim: dark metal with a highlight on top.
	float rim = smoothstep(0.86 - aa, 0.86 + aa, r);
	vec3 rim_col = vec3(0.08, 0.075, 0.07) + vec3(0.18) * smoothstep(0.2, -0.9, p.y) * smoothstep(0.98, 0.9, r);
	vec3 col = mix(face, rim_col, rim);
	// Ticks: sixty thin, twelve bold.
	float ang = atan(p.x, -p.y) / TAU;     // 0 at 12, clockwise
	float k60 = abs(fract(ang * 60.0 + 0.5) - 0.5) / 60.0 * TAU * r;
	float k12 = abs(fract(ang * 12.0 + 0.5) - 0.5) / 12.0 * TAU * r;
	float tick_s = (1.0 - smoothstep(0.006, 0.006 + aa, k60)) * step(0.74, r) * step(r, 0.82);
	float tick_b = (1.0 - smoothstep(0.018, 0.018 + aa, k12)) * step(0.64, r) * step(r, 0.82);
	col = mix(col, vec3(0.08, 0.07, 0.065), max(tick_s, tick_b) * (1.0 - rim));
	// Hands.
	float hour_turns = fract(u_minutes / 720.0);
	float h = hand(p, hour_turns, 0.42, 0.08, 0.045);
	float m = hand(p, u_minute_hand / 60.0, 0.68, 0.1, 0.03);
	float s = hand(p, u_second / 60.0, 0.74, 0.18, 0.009);
	// A soft shadow under the hands (light from above: shadows fall downwards).
	float shadow = min(hand(p - vec2(0.0, 0.03), hour_turns, 0.42, 0.08, 0.05), hand(p - vec2(0.0, 0.03), u_minute_hand / 60.0, 0.68, 0.1, 0.035));
	col *= 1.0 - 0.35 * (1.0 - smoothstep(0.0, 0.05, shadow)) * (1.0 - rim);
	col = mix(col, vec3(0.05, 0.045, 0.04), 1.0 - smoothstep(0.0, aa, min(h, m)));
	col = mix(col, u_blood.rgb * 1.1, 1.0 - smoothstep(0.0, aa, s));
	col = mix(col, vec3(0.05), 1.0 - smoothstep(0.035, 0.035 + aa, r));
	// Glass: a faint highlight arc at the top.
	col += vec3(0.12) * smoothstep(0.08, 0.0, abs(r - 0.7)) * smoothstep(-0.2, -0.8, p.y) * (1.0 - rim);
	// Light from the tube above: brighter at the top, falling off downwards.
	float lit = u_light * mix(1.0, 0.55, clamp(p.y * 0.5 + 0.5, 0.0, 1.0));
	col *= lit;
	col = mix(col, col * vec3(1.15, 0.5, 0.45) + u_blood.rgb * 0.05 * u_light, u_dread * 0.45);
	float alpha = 1.0 - smoothstep(1.0 - aa, 1.0 + aa, r);
	COLOR = vec4(col, alpha);
}
