// Procedural volcanic ground — original shader for LotrTD (CC0).
shader_type spatial;
render_mode unshaded;

uniform float scroll_speed : hint_range(0.0, 2.0) = 0.35;
uniform float crack_scale : hint_range(0.5, 16.0) = 4.5;
uniform float glow_strength : hint_range(0.0, 24.0) = 5.0;
uniform vec3 lava_hot = vec3(0.72, 0.28, 0.04);
uniform vec3 lava_cool = vec3(0.22, 0.03, 0.008);
uniform vec3 rock = vec3(0.035, 0.022, 0.018);

varying vec3 v_world;

float hash21(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise(vec2 p) {
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
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 5; i++) {
		v += a * noise(p);
		p *= 2.05;
		a *= 0.5;
	}
	return v;
}

void vertex() {
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 uv = v_world.xz * crack_scale + vec2(TIME * scroll_speed, TIME * scroll_speed * 0.6);
	float cracks = fbm(uv);
	float veins = fbm(uv * 2.4 + vec2(3.1, 1.7));
	float heat = smoothstep(0.42, 0.78, cracks + veins * 0.35);
	vec3 col = mix(rock, mix(lava_cool, lava_hot, heat), heat);
	float pulse = 0.94 + 0.06 * sin(TIME * 2.2 + cracks * 8.0);
	col *= pulse;
	ALBEDO = col * glow_strength;
	EMISSION = ALBEDO;
}
