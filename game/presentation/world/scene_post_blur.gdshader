shader_type canvas_item;
render_mode unshaded;
// Compile the screen mip-copy path only while a defocus effect actually uses it.
uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
#include "scene_post_body.gdshaderinc"
