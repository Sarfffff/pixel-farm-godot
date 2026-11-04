shader_type canvas_item;
uniform sampler2D season_tile : filter_nearest, repeat_enable;
uniform int season = 0;
varying vec2 world_pixel;
void vertex() { world_pixel = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy; }
void fragment() {
	vec4 original = texture(TEXTURE, UV);
	vec3 tint = COLOR.rgb / max(original.rgb, vec3(0.001));
	if (season == 1) {
		COLOR.rgb = mix(original.rgb, original.rgb * vec3(0.94, 1.01, 0.97), 0.65) * tint;
	} else if (season >= 2) {
		vec2 cell = floor(world_pixel / 16.0);
		float seed = fract(sin(dot(cell, vec2(12.9898, 78.233))) * 43758.5453);
		vec2 uv = fract(world_pixel / 16.0);
		if (seed > 0.5) uv.x = 1.0 - uv.x;
		vec3 ground = texture(season_tile, uv).rgb;
		if (season == 3 && seed > 0.25) ground = vec3(0.95, 0.96, 0.94);
		COLOR.rgb = ground * tint;
	}
}
