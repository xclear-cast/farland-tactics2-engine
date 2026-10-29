shader_type canvas_item;
render_mode unshaded;
uniform sampler2D palette_texture : filter_nearest, repeat_disable;
void fragment() {
	float index = floor(texture(TEXTURE, UV).r * 255.0 + 0.5);
	COLOR = vec4(texture(palette_texture, vec2((index + 0.5) / 256.0, 0.5)).rgb, 1.0);
}
