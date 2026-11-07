shader_type canvas_item;
render_mode unshaded;

uniform sampler2D screen_texture : hint_screen_texture, filter_linear_mipmap;
uniform vec2 corner_a;
uniform vec2 corner_b;
uniform vec2 corner_c;
uniform vec2 corner_d;

float cross_edge(vec2 a, vec2 b, vec2 p) {
	vec2 edge = b - a;
	return (edge.x * (p.y - a.y) - edge.y * (p.x - a.x)) / max(length(edge), 0.0001);
}

void fragment() {
	vec2 p = SCREEN_UV;
	float a = cross_edge(corner_a, corner_b, p);
	float b = cross_edge(corner_b, corner_c, p);
	float c = cross_edge(corner_c, corner_d, p);
	float d = cross_edge(corner_d, corner_a, p);
	float positive = min(min(a, b), min(c, d));
	float negative = min(min(-a, -b), min(-c, -d));
	float inside = max(positive, negative);
	float outside = 1.0 - smoothstep(-0.008, 0.005, inside);
	vec3 blurred = textureLod(screen_texture, p, 3.0).rgb;
	COLOR = vec4(blurred, outside);
}
