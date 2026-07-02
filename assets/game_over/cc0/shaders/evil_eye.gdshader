// Procedural evil eye — original shader for LotrTD (CC0).
shader_type spatial;
render_mode unshaded, cull_disabled, depth_test_disabled, fog_disabled;

uniform float eye_open : hint_range(0.0, 1.0) = 1.0;
uniform float pulse : hint_range(0.0, 1.0) = 0.5;
uniform float pulse_deep : hint_range(0.0, 1.0) = 0.5;
uniform float time_scale : hint_range(0.0, 4.0) = 1.0;
uniform vec3 sclera_inner = vec3(0.58, 0.32, 0.08);
uniform vec3 sclera_outer = vec3(0.52, 0.06, 0.015);
uniform vec3 glow_color = vec3(0.68, 0.08, 0.02);
uniform float emission_strength : hint_range(0.0, 32.0) = 5.5;
uniform float rim_strength : hint_range(0.0, 2.0) = 0.18;
uniform float depth_strength : hint_range(0.0, 1.5) = 0.85;
uniform float pulse_strength : hint_range(0.0, 1.0) = 0.55;

varying vec2 v_eye_uv;

float hash21(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise2d(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	float a = hash21(i);
	float b = hash21(i + vec2(1.0, 0.0));
	float c = hash21(i + vec2(0.0, 1.0));
	float d = hash21(i + vec2(1.0, 1.0));
	return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

float fbm(vec2 p) {
	float value = 0.0;
	float amplitude = 0.5;
	for (int i = 0; i < 4; i++) {
		value += amplitude * noise2d(p);
		p *= 2.05;
		amplitude *= 0.5;
	}
	return value;
}

void vertex() {
	// Perspective-correct screen-space UV so the mask matches at any distance.
	vec4 view_pos = VIEW_MATRIX * MODEL_MATRIX * vec4(VERTEX, 1.0);
	float depth = max(-view_pos.z, 0.05);
	v_eye_uv = view_pos.xy / depth;
}

void fragment() {
	float open = clamp(eye_open, 0.0, 1.0);
	vec2 uv = v_eye_uv;
	float vertical_scale = mix(0.35, 1.0, open);
	uv.y *= vertical_scale;

	float rx = 0.5;
	float ry = 0.22 * vertical_scale;
	float eye_mask = 1.0 - smoothstep(0.0, 0.06, (uv.x * uv.x) / (rx * rx) + (uv.y * uv.y) / (ry * ry) - 1.0);
	if (eye_mask < 0.01) {
		discard;
	}

	vec2 sclera_uv = uv * vec2(1.05, 1.35);
	float radial = length(sclera_uv);
	float angle = atan(sclera_uv.y, sclera_uv.x);
	float t_anim = TIME * time_scale;

	float sclera_t = smoothstep(0.08, 0.68, radial);
	vec3 sclera = mix(sclera_inner, sclera_outer, sclera_t);

	float bowl = 1.0 - smoothstep(0.0, 0.9, radial);
	bowl = pow(max(bowl, 0.0), 1.25);
	sclera *= mix(1.0, 0.68 + bowl * 0.42, depth_strength);

	float tissue = fbm(sclera_uv * 5.2 + vec2(t_anim * 0.07, t_anim * 0.04));
	float fine = fbm(sclera_uv * 13.0 - vec2(t_anim * 0.11, t_anim * 0.06));
	sclera *= mix(1.0, mix(0.86, 1.1, tissue), depth_strength * 0.65);
	sclera *= mix(1.0, mix(0.93, 1.05, fine), depth_strength * 0.45);

	float spokes_a = sin(angle * 10.0 + radial * 7.0 - t_anim * 0.45);
	float spokes_b = sin(angle * 6.0 - radial * 4.5 + t_anim * 0.28);
	float spokes = smoothstep(0.35, 0.9, spokes_a * 0.5 + spokes_b * 0.5 + 0.5);
	spokes *= smoothstep(0.12, 0.78, radial);
	vec3 vein_tint = vec3(0.18, 0.02, 0.008);
	sclera = mix(sclera, sclera * 0.72 + vein_tint, spokes * depth_strength * 0.55);

	float breathe = 0.5 + 0.5 * pulse_deep;
	float ripple_fast = sin(radial * 14.0 - t_anim * 2.4 + pulse * TAU);
	float ripple_slow = sin(radial * 8.0 - t_anim * 0.85 + breathe * TAU);
	float ripple = mix(ripple_slow, ripple_fast, 0.45) * 0.5 + 0.5;
	sclera *= mix(1.0, mix(0.9, 1.12, ripple), pulse_strength * 0.35);

	float pulse_gain = 1.0 + pulse_strength * (0.06 + pulse * 0.1 + breathe * 0.05);
	sclera *= pulse_gain;

	float slit_w = max(mix(0.02, 0.055, pulse) * open, 0.001);
	float slit_h = max(0.78 * open, 0.001);
	float slit = 1.0 - smoothstep(0.0, 0.02, abs(uv.x) / slit_w + abs(uv.y) / slit_h - 1.0);

	float slit_edge = abs(uv.x) / slit_w + abs(uv.y) / slit_h;
	float inner_rim = 1.0 - smoothstep(0.92, 1.18, slit_edge);
	inner_rim *= smoothstep(0.0, 0.55, open);
	sclera += glow_color * inner_rim * (0.12 + pulse * 0.18) * (0.7 + breathe * 0.3);

	vec3 col = mix(sclera, vec3(0.0), slit);

	float edge = 1.0 - smoothstep(0.78, 1.0, radial);
	col += glow_color * edge * rim_strength * (0.4 + pulse * 0.35);

	float flicker = 0.97 + 0.03 * sin(t_anim * 5.5 + radial * 12.0 + angle * 3.0);
	col *= flicker * eye_mask;

	ALBEDO = col * emission_strength;
	EMISSION = ALBEDO;
}
