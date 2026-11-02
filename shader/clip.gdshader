shader_type canvas_item;

uniform sampler2D mask;
uniform float opacity;
uniform vec4 modulate = vec4(1.0, 1.0, 1.0, 1.0);

void fragment() {
	COLOR.rgba = texture(TEXTURE, UV) * modulate;
	COLOR.a = opacity * texture(mask, UV).a;
}
