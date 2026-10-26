shader_type canvas_item;
render_mode unshaded;
uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_linear;
uniform float strength = 2.0;
// Soft nine-sample blur of what is behind the menu.
void fragment() {
    vec2 step_size = SCREEN_PIXEL_SIZE * strength;
    vec4 color = texture(screen_texture, SCREEN_UV) * 0.25;
    color += texture(screen_texture, SCREEN_UV + vec2(step_size.x, 0.0)) * 0.125;
    color += texture(screen_texture, SCREEN_UV - vec2(step_size.x, 0.0)) * 0.125;
    color += texture(screen_texture, SCREEN_UV + vec2(0.0, step_size.y)) * 0.125;
    color += texture(screen_texture, SCREEN_UV - vec2(0.0, step_size.y)) * 0.125;
    color += texture(screen_texture, SCREEN_UV + step_size) * 0.0625;
    color += texture(screen_texture, SCREEN_UV - step_size) * 0.0625;
    color += texture(screen_texture, SCREEN_UV + vec2(step_size.x, -step_size.y)) * 0.0625;
    color += texture(screen_texture, SCREEN_UV + vec2(-step_size.x, step_size.y)) * 0.0625;
    COLOR = vec4(color.rgb, 1.0);
}
