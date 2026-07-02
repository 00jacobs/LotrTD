shader_type canvas_item;

uniform float strength : hint_range(0.0, 1.0) = 0.38;
uniform float top_bias : hint_range(0.0, 1.0) = 0.72;

void fragment() {
	vec2 uv = UV;
	float top_falloff = smoothstep(top_bias, 0.0, uv.y);
	float side_falloff = smoothstep(0.0, 0.18, uv.x) * smoothstep(1.0, 0.82, uv.x);
	float alpha = top_falloff * side_falloff * strength;
	COLOR = vec4(0.0, 0.0, 0.0, alpha);
}
