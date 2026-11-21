shader_type canvas_item;
render_mode unshaded, blend_mix;

// Android presents the 3D color attachment directly. This pass only blends
// sensory cues over it, so a missing screen copy can never replace the world.
uniform float tunnel = 0.0;
uniform float blink = 0.0;
uniform float normal = 0.0;
uniform float san = 1.0;
uniform float hurt = 0.0;
uniform float red = 0.0;
uniform float gaze = 0.0;
uniform float blur = 0.0;
uniform float focus = 0.0;
uniform float halo = 0.0;
uniform float pulse = 0.0;
uniform float ghost = 0.0;
uniform float night_vision = 0.0;
uniform vec2 ghost_dir = vec2(1.0, 0.0);

void fragment() {
	vec2 center = UV * 2.0 - 1.0;
	float edge = smoothstep(0.3, 1.25, length(center));
	float otherworld = 1.0 - clamp(normal, 0.0, 1.0);
	float strain = clamp((1.0 - san) * 0.16 + tunnel * (0.5 + 0.08 * pulse), 0.0, 0.72);
	float injury = clamp(max(hurt, red), 0.0, 1.0);
	float glare = clamp(halo * 0.20 + (blur + focus) * 0.08
		+ ghost * 0.12 * max(dot(center, ghost_dir), 0.0), 0.0, 0.32);
	vec3 tint = mix(vec3(0.025, 0.035, 0.055), vec3(0.60, 0.65, 0.68), glare * 3.0);
	tint = mix(tint, vec3(0.38, 0.035, 0.035), injury);
	tint = mix(tint, vec3(0.30, 0.21, 0.08), clamp(gaze, 0.0, 1.0) * 0.6);
	float alpha = edge * (strain + glare + 0.28 * gaze) * otherworld
		+ injury * (0.12 + 0.36 * edge);
	if (night_vision > 0.0) {
		float vision_alpha = 0.10 * night_vision * (1.0 - clamp(alpha, 0.0, 1.0));
		tint = (tint * alpha + vec3(0.15, 0.38, 0.19) * vision_alpha) / max(alpha + vision_alpha, 0.001);
		alpha += vision_alpha;
	}
	float eyelid = clamp(blink * otherworld, 0.0, 1.0);
	COLOR = vec4(mix(tint, vec3(0.0), eyelid), mix(clamp(alpha, 0.0, 0.78), 1.0, eyelid));
}
