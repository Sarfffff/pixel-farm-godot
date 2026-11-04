shader_type canvas_item;
uniform int season = 0;
uniform bool use_vertex_color = false;
void fragment() {
	vec4 original = use_vertex_color ? COLOR : texture(TEXTURE, UV);
	vec3 tint = use_vertex_color ? vec3(1.0) : COLOR.rgb / max(original.rgb, vec3(0.001));
	vec3 c = original.rgb;
	bool leaf = c.g > c.r * 0.99 && c.g > c.b * 1.14 && c.g - c.b > 0.06;
	if (leaf && season == 2) {
		float lightness = dot(c, vec3(0.3, 0.59, 0.11));
		c = mix(vec3(0.61, 0.39, 0.27), vec3(0.93, 0.79, 0.49), lightness);
	} else if (leaf && season == 3) {
		float lightness = dot(c, vec3(0.3, 0.59, 0.11));
		c = mix(vec3(0.68, 0.77, 0.79), vec3(0.96, 0.97, 0.94), lightness);
	}
	COLOR.rgb = c * tint;
}
