shader_type canvas_item;
// Boot animation backdrop (2026-11-14 redesign): a dark classroom wall at 18:00. A fluorescent tube near the
// top starter-flickers on and lights a cone of grimy plaster under it (the clock hangs there, drawn by
// school_clock.gdshader); dust drifts in the light; at the end the tube dies and only black is left, which
// the menu's eyelids (menu_wake.gd) then open from. Driven by boot_splash.gd.

uniform sampler2D u_noise : repeat_enable, filter_linear;
uniform vec2 u_size = vec2(960.0, 540.0);
uniform float u_t = 0.0;
uniform float u_light = 0.0;      // the tube's output, 0 off … 1 on (the flicker is in this value)
uniform float u_glow = 0.0;       // heartbeat glow behind the title
uniform float u_after = 0.0;      // the tube's afterglow once it has died (a fading pale-red line)
uniform vec2 u_tube = vec2(0.5, 0.1); // the tube's centre (UV)
uniform float u_tube_w = 0.2;     // half length as a fraction of the width
uniform vec2 u_glow_at = vec2(0.5, 0.72);
uniform float u_motion = 1.0;
uniform vec4 u_blood : source_color = vec4(0.62, 0.05, 0.04, 1.0);

float hash(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float fbm(vec2 p) {
	return texture(u_noise, p * 0.25).r;
}

void fragment() {
	vec2 px = UV * u_size;
	float h = u_size.y;
	vec2 q = px / h;                       // square units, height 1
	vec2 tube = u_tube * u_size / h;
	float half_len = u_tube_w * u_size.x / h;
	float t = u_t * u_motion;
	// Distance to the tube segment.
	vec2 d = q - vec2(clamp(q.x, tube.x - half_len, tube.x + half_len), tube.y);
	float dist = length(d);
	// The wall: dark plaster with stains, seen only where the light reaches.
	float plaster = fbm(q * 3.0) * 0.6 + fbm(q * 11.0 + 7.0) * 0.4;
	float stain = smoothstep(0.55, 0.85, fbm(q * 1.6 + vec2(3.1, 0.0))) * smoothstep(tube.y, tube.y + 0.6, q.y);
	vec3 wall = mix(vec3(0.20, 0.21, 0.19), vec3(0.11, 0.115, 0.10), plaster) * (1.0 - stain * 0.45);
	wall = mix(wall, vec3(0.13, 0.06, 0.05), stain * 0.35);
	// Wainscot: the lower third is painted a darker green-grey with a rail line, like a classroom wall.
	float wains = smoothstep(0.80, 0.805, q.y);
	wall = mix(wall, vec3(0.07, 0.10, 0.085) * (0.8 + plaster * 0.4), wains);
	wall *= 1.0 - 0.5 * smoothstep(0.003, 0.0, abs(q.y - 0.80));
	// Light from the tube: a cone downwards with inverse-square-ish falloff; cool white.
	float below = smoothstep(-0.02, 0.06, q.y - tube.y);
	float fall = 1.0 / (1.0 + pow(dist / 0.32, 2.2));
	float cone = fall * mix(0.35, 1.0, below);
	vec3 tint = vec3(0.86, 0.95, 0.92);
	vec3 col = wall * tint * cone * u_light * 2.6;
	// The tube itself and its housing.
	float housing = smoothstep(0.022, 0.016, abs(q.y - tube.y + 0.004)) * step(abs(q.x - tube.x), half_len + 0.02);
	col = mix(col, vec3(0.05, 0.05, 0.048) + vec3(0.1) * u_light, housing);
	float core = exp(-pow(dist / 0.0055, 2.0));
	float bloom = exp(-dist / 0.05) * 0.35 + exp(-dist / 0.012) * 0.6;
	col += tint * (core * 1.6 + bloom) * u_light;
	// A dying tube leaves a dim reddish filament line for a moment.
	col += vec3(0.5, 0.12, 0.08) * core * u_after;
	// Dust motes drifting slowly in the light.
	vec2 cell = floor(q * 38.0 + vec2(0.0, t * 0.7));
	vec2 f = fract(q * 38.0 + vec2(0.0, t * 0.7)) - 0.5;
	float mote = step(0.965, hash(cell)) * smoothstep(0.12, 0.0, length(f + (vec2(hash(cell + 3.0), hash(cell + 9.0)) - 0.5) * 0.6));
	col += tint * mote * cone * u_light * 0.25 * u_motion;
	// Heartbeat glow behind the title.
	vec2 g = (UV - u_glow_at) * vec2(u_size.x / h, 1.0);
	col += u_blood.rgb * exp(-dot(g, g) / 0.035) * u_glow * 0.5;
	// Grain and a heavy vignette.
	float grain = hash(floor(px / 2.0) + floor(t * 18.0));
	col += vec3(0.02, 0.014, 0.014) * grain * u_motion;
	vec2 v = (UV - 0.5) * vec2(u_size.x / h, 1.0);
	col *= 1.0 - smoothstep(0.35, 1.05, length(v)) * 0.85;
	COLOR = vec4(max(col, vec3(0.004, 0.003, 0.004)), 1.0);
}
